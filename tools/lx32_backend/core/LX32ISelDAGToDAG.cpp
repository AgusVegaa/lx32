//===-- LX32ISelDAGToDAG.cpp - LX32 DAG->DAG Instruction Selector --------===//
//
// Part of the LX32 Project
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//
//
// Instruction selection for the LX32 backend.
//
// The pipeline entering this pass has already been through ISelLowering, which
// converts all ISD::INTRINSIC_* nodes into LX32ISD::LX32_* nodes.  By the
// time Select() is called, no raw intrinsic nodes remain — only the target
// custom opcodes.
//
// Custom instruction shapes:
//
//   "Read" ops  (SENSOR / MATRIX / DELTA / CHORD):
//     Inputs : (rs1 : i32)
//     Outputs: (rd  : i32)          — no chain, never stall
//
//   "Chain" ops (WAIT / REPORT):
//     Inputs : (chain : Other, rs1 : i32)
//     Outputs: (chain : Other)      — side-effecting; may stall
//
//===----------------------------------------------------------------------===//

#include "LX32ISelDAGToDAG.h"

#include "LX32ISelLowering.h"
#include "LX32Subtarget.h"
#include "LX32TargetMachine.h"

#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/SelectionDAGISel.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

#include <memory>

using namespace llvm;

#define DEBUG_TYPE "lx32-isel"

namespace {

class LX32DAGToDAGISel : public SelectionDAGISel {
  const LX32Subtarget *Subtarget = nullptr;

public:
  explicit LX32DAGToDAGISel(LX32TargetMachine &TM, CodeGenOptLevel OptLevel)
      : SelectionDAGISel(TM, OptLevel) {}

  bool runOnMachineFunction(MachineFunction &MF) override {
    Subtarget = &MF.getSubtarget<LX32Subtarget>();
    return SelectionDAGISel::runOnMachineFunction(MF);
  }

  void Select(SDNode *Node) override;

private:
  void SelectFrameIndex(SDNode *Node);

  // materializeRegOperand — ensure a custom-instruction argument is in a GPR.
  //
  // Custom instructions accept only register operands.  When the caller passes
  // a compile-time constant (e.g. lx_sensor(3), lx_wait(5000)) the constant
  // must be materialized into a register first.  Three cases:
  //
  //   0            → alias x0 (no instruction)
  //   fits simm12  → ADDI rd, x0, imm  (1 instruction)
  //   large        → LUI rd, hi20; ADDI rd, rd, lo12  (1–2 instructions)
  //                  The ADDI is suppressed when lo12 == 0.
  SDValue materializeRegOperand(SDValue Op, const SDLoc &DL);

  // selectLXReadOp — emit a value-producing custom instruction.
  //
  // Handles SENSOR / MATRIX / DELTA / CHORD.
  // Expected node: (rs1 : i32) → (rd : i32)
  void selectLXReadOp(SDNode *Node, unsigned MachOpc);

  // selectLXChainOp — emit a side-effecting custom instruction.
  //
  // Handles WAIT / REPORT.
  // Expected node: (chain : Other, rs1 : i32) → (chain : Other)
  void selectLXChainOp(SDNode *Node, unsigned MachOpc);

  // Include the auto-generated selection matcher.
  #include "LX32GenDAGISel.inc"
};

class LX32DAGToDAGISelLegacy : public SelectionDAGISelLegacy {
public:
  static char ID;

  LX32DAGToDAGISelLegacy(LX32TargetMachine &TM, CodeGenOptLevel OptLevel)
      : SelectionDAGISelLegacy(
            ID, std::make_unique<LX32DAGToDAGISel>(TM, OptLevel)) {}

  StringRef getPassName() const override {
    return "LX32 DAG->DAG Instruction Selection";
  }
};

} // end anonymous namespace

char LX32DAGToDAGISelLegacy::ID = 0;

void LX32DAGToDAGISel::SelectFrameIndex(SDNode *Node) {
  SDLoc DL(Node);
  int FI = cast<FrameIndexSDNode>(Node)->getIndex();
  SDValue TFI = CurDAG->getTargetFrameIndex(FI, MVT::i32);
  SDValue Zero = CurDAG->getTargetConstant(0, DL, MVT::i32);

  SDNode *Result = CurDAG->getMachineNode(LX32::ADDI, DL, MVT::i32, TFI, Zero);
  ReplaceNode(Node, Result);
}

SDValue LX32DAGToDAGISel::materializeRegOperand(SDValue Op, const SDLoc &DL) {
  const auto *C = dyn_cast<ConstantSDNode>(Op);
  if (!C)
    return Op; // already a register value

  int64_t V = C->getSExtValue();
  LLVM_DEBUG(dbgs() << "lx32-isel: materializing constant " << V
                    << " for custom instruction operand\n");

  if (V == 0)
    return CurDAG->getRegister(LX32::X0, MVT::i32);

  if (isInt<12>(V)) {
    SDValue X0  = CurDAG->getRegister(LX32::X0, MVT::i32);
    SDValue Imm = CurDAG->getTargetConstant(V, DL, MVT::i32);
    SDNode *Mat = CurDAG->getMachineNode(LX32::ADDI, DL, MVT::i32, X0, Imm);
    return SDValue(Mat, 0);
  }

  // Large constant: LUI + optional ADDI.
  // The +0x800 bias compensates for ADDI's sign-extension of its 12-bit field.
  int64_t Hi20 = ((V + 0x800) >> 12) & 0xFFFFF;
  int64_t Lo12 = V - (Hi20 << 12);
  SDNode *LUI = CurDAG->getMachineNode(
      LX32::LUI, DL, MVT::i32, CurDAG->getTargetConstant(Hi20, DL, MVT::i32));
  if (Lo12 == 0)
    return SDValue(LUI, 0);
  SDNode *ADDI = CurDAG->getMachineNode(
      LX32::ADDI, DL, MVT::i32, SDValue(LUI, 0),
      CurDAG->getTargetConstant(Lo12, DL, MVT::i32));
  return SDValue(ADDI, 0);
}

void LX32DAGToDAGISel::selectLXReadOp(SDNode *Node, unsigned MachOpc) {
  if (Node->getNumOperands() < 1)
    report_fatal_error("lx32: malformed LX custom read node (missing rs1)");
  SDLoc DL(Node);
  SDValue RS1 = materializeRegOperand(Node->getOperand(0), DL);
  LLVM_DEBUG(dbgs() << "lx32-isel: selecting LX read op → machine opc "
                    << MachOpc << "\n");
  SDNode *N = CurDAG->getMachineNode(MachOpc, DL, Node->getValueType(0), RS1);
  ReplaceNode(Node, N);
}

void LX32DAGToDAGISel::selectLXChainOp(SDNode *Node, unsigned MachOpc) {
  if (Node->getNumOperands() < 2)
    report_fatal_error("lx32: malformed LX custom chain node (missing chain or rs1)");
  SDLoc DL(Node);
  SDValue Chain = Node->getOperand(0);
  SDValue RS1   = materializeRegOperand(Node->getOperand(1), DL);
  LLVM_DEBUG(dbgs() << "lx32-isel: selecting LX chain op → machine opc "
                    << MachOpc << "\n");
  SDNode *N = CurDAG->getMachineNode(MachOpc, DL, MVT::Other, RS1, Chain);
  ReplaceNode(Node, N);
}

void LX32DAGToDAGISel::Select(SDNode *Node) {
  if (Node->isMachineOpcode()) {
    Node->setNodeId(-1);
    return;
  }

  LLVM_DEBUG(dbgs() << "lx32-isel: Select node opc=" << Node->getOpcode()
                    << "\n");

  switch (Node->getOpcode()) {
  case ISD::Constant: {
    // Optimize large constant materialization.
    //
    // The TableGen pattern always emits LUI + ADDI for constants that do not
    // fit in simm12.  When the lower 12 bits are zero that ADDI is redundant
    // ("ADDI rd, rd, 0").  Intercept here to suppress it.
    //
    //   isInt<12>(val)             → TableGen small-constant pattern handles it
    //   lo12 == 0, hi20 != 0       → LUI only (saves 1 cycle)
    //   lo12 != 0                  → fall through to TableGen LUI+ADDI pattern
    const auto *CI = cast<ConstantSDNode>(Node);
    int64_t Val = CI->getSExtValue();

    if (isInt<12>(Val))
      break; // handled by TableGen

    int64_t Hi20 = ((Val + 0x800) >> 12) & 0xFFFFF;
    int64_t Lo12 = Val - (Hi20 << 12);

    if (Lo12 == 0) {
      LLVM_DEBUG(dbgs() << "lx32-isel: large const " << Val
                        << " — emitting LUI only (lo12=0)\n");
      SDNode *LUI = CurDAG->getMachineNode(
          LX32::LUI, SDLoc(Node), MVT::i32,
          CurDAG->getTargetConstant(Hi20, SDLoc(Node), MVT::i32));
      ReplaceNode(Node, LUI);
      return;
    }
    break; // lo12 != 0: TableGen emits LUI+ADDI
  }

  // Custom PULSAR read instructions: (rs1) → i32, no chain, latency 1.
  case LX32ISD::LX32_SENSOR: selectLXReadOp(Node, LX32::LX_SENSOR); return;
  case LX32ISD::LX32_MATRIX: selectLXReadOp(Node, LX32::LX_MATRIX); return;
  case LX32ISD::LX32_DELTA:  selectLXReadOp(Node, LX32::LX_DELTA);  return;
  case LX32ISD::LX32_CHORD:  selectLXReadOp(Node, LX32::LX_CHORD);  return;

  // Custom PULSAR chain instructions: (chain, rs1) → chain, side-effecting.
  case LX32ISD::LX32_WAIT:   selectLXChainOp(Node, LX32::LX_WAIT);   return;
  case LX32ISD::LX32_REPORT: selectLXChainOp(Node, LX32::LX_REPORT); return;

  case LX32ISD::CALL: {
    SDLoc DL(Node);

    if (Node->getNumOperands() < 2)
      report_fatal_error("lx32: malformed CALL node");

    SDValue Callee = Node->getOperand(1);
    if (Callee.getOpcode() != ISD::TargetGlobalAddress &&
        Callee.getOpcode() != ISD::TargetExternalSymbol)
      report_fatal_error("lx32: CALL expects target global/external symbol");

    SmallVector<SDValue, 4> Ops;
    Ops.push_back(Callee);              // explicit call target symbol
    Ops.push_back(Node->getOperand(0)); // chain
    // Forward glue (if any); skip ISD::Register operands added by LowerCall
    // since PseudoCALL's Uses list in TableGen already declares the arg regs.
    for (unsigned I = 2, E = Node->getNumOperands(); I != E; ++I) {
      SDValue Op = Node->getOperand(I);
      if (Op.getValueType() == MVT::Glue)
        Ops.push_back(Op);
    }

    SDNode *Call = CurDAG->getMachineNode(
        LX32::PseudoCALL, DL, CurDAG->getVTList(MVT::Other, MVT::Glue), Ops);
    ReplaceNode(Node, Call);
    return;
  }
  case LX32ISD::RET: {
    SDLoc DL(Node);
    SmallVector<SDValue, 4> RetOps;
    for (const SDValue &Op : Node->ops())
      RetOps.push_back(Op);

    SDVTList VTs = CurDAG->getVTList(MVT::Other);
    SDNode *Ret = CurDAG->getMachineNode(LX32::PseudoRET, DL, VTs, RetOps);
    ReplaceNode(Node, Ret);
    return;
  }
  case LX32ISD::BRCC: {
    SDLoc DL(Node);
    if (Node->getNumOperands() < 5)
      report_fatal_error("lx32: malformed BRCC node");

    // Canonical BRCC order is: chain, lhs, rhs, cc, target.
    SDValue LHS = Node->getOperand(1);
    SDValue RHS = Node->getOperand(2);
    const auto *CCNode = dyn_cast<CondCodeSDNode>(Node->getOperand(3));
    SDValue Target = Node->getOperand(4);
    if (!CCNode)
      report_fatal_error("lx32: BRCC missing condition code");

    auto normalizeBranchOperand = [&](SDValue Op) -> SDValue {
      if (const auto *C = dyn_cast<ConstantSDNode>(Op)) {
        if (C->isZero())
          return CurDAG->getRegister(LX32::X0, MVT::i32);
        report_fatal_error(
            "lx32: BRCC non-zero constants must be materialized in lowering");
      }
      return Op;
    };

    unsigned BrOpc = 0;
    switch (CCNode->get()) {
    case ISD::SETEQ:
      BrOpc = LX32::PseudoBEQ;
      break;
    case ISD::SETNE:
      BrOpc = LX32::PseudoBNE;
      break;
    case ISD::SETLT:
      BrOpc = LX32::PseudoBLT;
      break;
    case ISD::SETGE:
      BrOpc = LX32::PseudoBGE;
      break;
    case ISD::SETULT:
      BrOpc = LX32::PseudoBLTU;
      break;
    case ISD::SETUGE:
      BrOpc = LX32::PseudoBGEU;
      break;
    default:
      report_fatal_error("lx32: unsupported BRCC condition code");
    }

    SmallVector<SDValue, 4> BrOps;
    BrOps.push_back(normalizeBranchOperand(LHS));
    BrOps.push_back(normalizeBranchOperand(RHS));
    BrOps.push_back(Target);
    BrOps.push_back(Node->getOperand(0)); // chain
    SDNode *Br = CurDAG->getMachineNode(BrOpc, DL, MVT::Other, BrOps);
    ReplaceNode(Node, Br);
    return;
  }
  case ISD::BR_CC:
    report_fatal_error("lx32: unexpected generic BR_CC during instruction selection");
  case ISD::FrameIndex:
    SelectFrameIndex(Node);
    return;
  default:
    break;
  }

  SelectCode(Node);
}

FunctionPass *llvm::createLX32ISelDag(LX32TargetMachine &TM,
                                      CodeGenOptLevel OptLevel) {
  return new LX32DAGToDAGISelLegacy(TM, OptLevel);
}
