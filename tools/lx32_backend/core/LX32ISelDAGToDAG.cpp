//===-- LX32ISelDAGToDAG.cpp - LX32 DAG->DAG Instruction Selector --------===//
//
// Part of the LX32 Project
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

#include "LX32ISelDAGToDAG.h"

#include "LX32ISelLowering.h"
#include "LX32Subtarget.h"
#include "LX32TargetMachine.h"

#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/SelectionDAGISel.h"
#include "llvm/Support/ErrorHandling.h"

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

void LX32DAGToDAGISel::Select(SDNode *Node) {
  if (Node->isMachineOpcode()) {
    Node->setNodeId(-1);
    return;
  }

  switch (Node->getOpcode()) {
  case ISD::BR: {
    SDLoc DL(Node);

    if (Node->getNumOperands() < 2)
      report_fatal_error("lx32: malformed BR node");

    SDValue Chain = Node->getOperand(0);
    SDValue Target = Node->getOperand(1);

    // Create a PseudoBR pseudo-instruction that will be expanded later
    SmallVector<SDValue, 2> BrOps;
    BrOps.push_back(Target);
    BrOps.push_back(Chain);
    SDNode *Jump = CurDAG->getMachineNode(
        LX32::PseudoBR, DL, MVT::Other, BrOps);
    ReplaceNode(Node, Jump);
    return;
  }
  case LX32ISD::CALL: {
    SDLoc DL(Node);

    if (Node->getNumOperands() < 2)
      report_fatal_error("lx32: malformed CALL node");

    SDValue Callee = Node->getOperand(1);
    if (Callee.getOpcode() != ISD::TargetGlobalAddress &&
        Callee.getOpcode() != ISD::TargetExternalSymbol)
      report_fatal_error("lx32: CALL expects target global/external symbol");

    SmallVector<SDValue, 4> Ops;
    Ops.push_back(Node->getOperand(0)); // chain
    Ops.push_back(Callee);              // direct call target symbol
    if (Node->getNumOperands() > 2)
      Ops.push_back(Node->getOperand(2)); // optional glue

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
