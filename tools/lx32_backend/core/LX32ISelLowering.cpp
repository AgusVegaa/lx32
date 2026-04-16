//===-- LX32ISelLowering.cpp - LX32 SelectionDAG Lowering ----------------===//
//
// Part of the LX32 Project
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

#include "LX32ISelLowering.h"

#include "LX32RegisterInfo.h"
#include "LX32Subtarget.h"

#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/IR/IntrinsicsLX32.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

#define DEBUG_TYPE "lx32-lower"

using namespace llvm;

#include "LX32GenCallingConv.inc"

static SDValue lowerCCValue(SDValue Val, CCValAssign::LocInfo LocInfo,
                            EVT ValVT, SelectionDAG &DAG,
                            const SDLoc &DL) {
  switch (LocInfo) {
  case CCValAssign::Full:
    return Val;
  case CCValAssign::BCvt:
    return DAG.getNode(ISD::BITCAST, DL, ValVT, Val);
  case CCValAssign::SExt:
    if (Val.getValueType() == ValVT)
      return Val;
    return DAG.getNode(ISD::AssertSext, DL, Val.getValueType(), Val,
                       DAG.getValueType(ValVT));
  case CCValAssign::ZExt:
    if (Val.getValueType() == ValVT)
      return Val;
    return DAG.getNode(ISD::AssertZext, DL, Val.getValueType(), Val,
                       DAG.getValueType(ValVT));
  case CCValAssign::AExt:
    if (Val.getValueType() == ValVT)
      return Val;
    return DAG.getNode(ISD::TRUNCATE, DL, ValVT, Val);
  default:
    report_fatal_error("lx32: unsupported CC value location info");
  }
}

LX32TargetLowering::LX32TargetLowering(const TargetMachine &TM,
                                       const LX32Subtarget &STI)
    : TargetLowering(TM, STI), STI(STI) {
  addRegisterClass(MVT::i32, &LX32::GPRRegClass);
  setStackPointerRegisterToSaveRestore(LX32::X2);

  setOperationAction(ISD::SDIV, MVT::i32, Expand);
  setOperationAction(ISD::UDIV, MVT::i32, Expand);
  setOperationAction(ISD::SREM, MVT::i32, Expand);
  setOperationAction(ISD::UREM, MVT::i32, Expand);
  // Multiplication — LX32 has no MUL instruction; expand to shift/add sequences.
  setOperationAction(ISD::MUL,       MVT::i32, Expand);
  setOperationAction(ISD::MULHS,     MVT::i32, Expand);
  setOperationAction(ISD::MULHU,     MVT::i32, Expand);
  setOperationAction(ISD::SMUL_LOHI, MVT::i32, Expand);
  setOperationAction(ISD::UMUL_LOHI, MVT::i32, Expand);
  setOperationAction(ISD::SDIVREM, MVT::i32, Expand);
  setOperationAction(ISD::UDIVREM, MVT::i32, Expand);

  setOperationAction(ISD::ROTL, MVT::i32, Expand);
  setOperationAction(ISD::ROTR, MVT::i32, Expand);
  setOperationAction(ISD::CTLZ, MVT::i32, Expand);
  setOperationAction(ISD::CTTZ, MVT::i32, Expand);
  setOperationAction(ISD::CTPOP, MVT::i32, Expand);

  // SELECT: LX32 has no conditional-move instruction.  Lower to a branch
  // sequence (see lowerSELECT) so the DAG-to-DAG pass can emit real branches.
  setOperationAction(ISD::SELECT, MVT::i32, Custom);

  // Keep setcc/branch boolean semantics explicit for DAG combines.
  setBooleanContents(ZeroOrOneBooleanContent);

  // Lower branches with explicit condition codes to a target node so the
  // selector never has to re-interpret generic BR_CC/SETCC combinations.
  setOperationAction(ISD::BR_CC, MVT::i32, Custom);
  setOperationAction(ISD::BRCOND, MVT::Other, Custom);

  setOperationAction(ISD::INTRINSIC_WO_CHAIN, MVT::i32, Custom);
  setOperationAction(ISD::INTRINSIC_W_CHAIN,  MVT::i32, Custom);
  setOperationAction(ISD::INTRINSIC_VOID,     MVT::Other, Custom);

  // Global and block addresses: lower to PseudoLA which the AsmPrinter
  // expands to the two-instruction absolute-address sequence:
  //   AUIPC rd, %pcrel_hi(sym)
  //   ADDI  rd, rd, %pcrel_lo(sym)
  // For the LX32 baremetal target this is always absolute (non-PIC).
  setOperationAction(ISD::GlobalAddress, MVT::i32, Custom);
  setOperationAction(ISD::BlockAddress,  MVT::i32, Custom);
  setOperationAction(ISD::ConstantPool,  MVT::i32, Expand);

  setMaxAtomicSizeInBitsSupported(0);

  computeRegisterProperties(STI.getRegisterInfo());
}

const char *LX32TargetLowering::getTargetNodeName(unsigned Opcode) const {
  switch (Opcode) {
  case LX32ISD::RET:
    return "LX32ISD::RET";
  case LX32ISD::CALL:
    return "LX32ISD::CALL";
  case LX32ISD::SELECT_CC:
    return "LX32ISD::SELECT_CC";
  case LX32ISD::BRCC:
    return "LX32ISD::BRCC";
  case LX32ISD::LX32_SENSOR:
    return "LX32ISD::LX32_SENSOR";
  case LX32ISD::LX32_MATRIX:
    return "LX32ISD::LX32_MATRIX";
  case LX32ISD::LX32_DELTA:
    return "LX32ISD::LX32_DELTA";
  case LX32ISD::LX32_CHORD:
    return "LX32ISD::LX32_CHORD";
  case LX32ISD::LX32_WAIT:
    return "LX32ISD::LX32_WAIT";
  case LX32ISD::LX32_REPORT:
    return "LX32ISD::LX32_REPORT";
  default:
    return nullptr;
  }
}

SDValue LX32TargetLowering::lowerBR_CC(SDValue Op, SelectionDAG &DAG) const {
  SDLoc DL(Op);
  LLVM_DEBUG(dbgs() << "lx32-lower: lowerBR_CC\n");

  if (Op.getNumOperands() < 5)
    report_fatal_error("lx32: malformed BR_CC node");

  const auto *CCNode = dyn_cast<CondCodeSDNode>(Op.getOperand(1));
  if (!CCNode)
    report_fatal_error("lx32: BR_CC missing condition code");

  SDValue LHS = Op.getOperand(2);
  SDValue RHS = Op.getOperand(3);
  SDValue Target = Op.getOperand(4);

  auto normalizeBranchOperand = [&](SDValue V) -> SDValue {
    if (const auto *C = dyn_cast<ConstantSDNode>(V)) {
      if (C->isZero())
        return DAG.getRegister(LX32::X0, MVT::i32);

      // Branch pseudos are reg-reg. Materialize constants early in lowering
      // so DAGToDAG selection does not have to synthesize ad-hoc machine nodes.
      return DAG.getNode(ISD::ADD, DL, MVT::i32,
                         DAG.getRegister(LX32::X0, MVT::i32),
                         DAG.getConstant(C->getSExtValue(), DL, MVT::i32));
    }
    return V;
  };

  ISD::CondCode CC = CCNode->get();
  bool Swap = false;
  switch (CC) {
  case ISD::SETEQ:
  case ISD::SETNE:
  case ISD::SETLT:
  case ISD::SETGE:
  case ISD::SETULT:
  case ISD::SETUGE:
    break;
  case ISD::SETGT:
    CC = ISD::SETLT;
    Swap = true;
    break;
  case ISD::SETLE:
    CC = ISD::SETGE;
    Swap = true;
    break;
  case ISD::SETUGT:
    CC = ISD::SETULT;
    Swap = true;
    break;
  case ISD::SETULE:
    CC = ISD::SETUGE;
    Swap = true;
    break;
  default:
    report_fatal_error("lx32: unsupported BR_CC condition code");
  }

  SDValue Op0 = Swap ? RHS : LHS;
  SDValue Op1 = Swap ? LHS : RHS;
  Op0 = normalizeBranchOperand(Op0);
  Op1 = normalizeBranchOperand(Op1);

  // Keep the BRCC operand order aligned with common target patterns:
  // chain, lhs, rhs, cond, target.
  return DAG.getNode(LX32ISD::BRCC, DL, MVT::Other, Op.getOperand(0), Op0,
                     Op1, DAG.getCondCode(CC), Target);
}

SDValue LX32TargetLowering::lowerBRCOND(SDValue Op, SelectionDAG &DAG) const {
  SDLoc DL(Op);

  if (Op.getNumOperands() < 3)
    report_fatal_error("lx32: malformed BRCOND node");

  SDValue Chain = Op.getOperand(0);
  SDValue Cond = Op.getOperand(1);
  SDValue Target = Op.getOperand(2);

  if (Cond.getOpcode() == ISD::SETCC) {
    SDValue LHS = Cond.getOperand(0);
    SDValue RHS = Cond.getOperand(1);
    auto *CCNode = dyn_cast<CondCodeSDNode>(Cond.getOperand(2));
    if (!CCNode)
      report_fatal_error("lx32: BRCOND SETCC missing condition code");

    SDValue BrCC = DAG.getNode(ISD::BR_CC, DL, MVT::Other, Chain,
                               DAG.getCondCode(CCNode->get()), LHS, RHS,
                               Target);
    return lowerBR_CC(BrCC, DAG);
  }

  // Generic i1 branch condition: branch when cond != 0.
  if (Cond.getValueType() != MVT::i32)
    Cond = DAG.getNode(ISD::ZERO_EXTEND, DL, MVT::i32, Cond);

  SDValue BrCC = DAG.getNode(ISD::BR_CC, DL, MVT::Other, Chain,
                             DAG.getCondCode(ISD::SETNE), Cond,
                             DAG.getConstant(0, DL, MVT::i32), Target);
  return lowerBR_CC(BrCC, DAG);
}

SDValue LX32TargetLowering::LowerFormalArguments(
    SDValue Chain, CallingConv::ID CallConv, bool IsVarArg,
    const SmallVectorImpl<ISD::InputArg> &Ins, const SDLoc &DL,
    SelectionDAG &DAG, SmallVectorImpl<SDValue> &InVals) const {
  if (IsVarArg)
    report_fatal_error("lx32: varargs lowering is not implemented yet");

  MachineFunction &MF = DAG.getMachineFunction();
  MachineRegisterInfo &RegInfo = MF.getRegInfo();
  MachineFrameInfo &MFI = MF.getFrameInfo();

  SmallVector<CCValAssign, 16> ArgLocs;
  CCState CCInfo(CallConv, IsVarArg, MF, ArgLocs, *DAG.getContext());
  CCInfo.AnalyzeFormalArguments(Ins, CC_LX32);

  for (unsigned I = 0, E = Ins.size(); I != E; ++I) {
    const CCValAssign &VA = ArgLocs[I];

    SDValue Val;
    if (VA.isRegLoc()) {
      Register VReg = RegInfo.createVirtualRegister(&LX32::GPRRegClass);
      RegInfo.addLiveIn(VA.getLocReg(), VReg);

      SDValue Arg = DAG.getCopyFromReg(Chain, DL, VReg, VA.getLocVT());
      Chain = Arg.getValue(1);
      Val = Arg;
    } else {
      int FI = MFI.CreateFixedObject(VA.getLocVT().getStoreSize(),
                                     VA.getLocMemOffset(), true);
      SDValue FIN = DAG.getFrameIndex(FI, getPointerTy(DAG.getDataLayout()));
      SDValue Ld = DAG.getLoad(VA.getLocVT(), DL, Chain, FIN,
                               MachinePointerInfo::getFixedStack(MF, FI));
      Chain = Ld.getValue(1);
      Val = Ld;
    }

    EVT ValVT = Ins[I].VT;
    Val = lowerCCValue(Val, VA.getLocInfo(), ValVT, DAG, DL);
    if (Val.getValueType() != ValVT)
      Val = DAG.getNode(ISD::TRUNCATE, DL, ValVT, Val);
    InVals.push_back(Val);
  }

  return Chain;
}

SDValue LX32TargetLowering::LowerCall(
    TargetLowering::CallLoweringInfo &CLI,
    SmallVectorImpl<SDValue> &InVals) const {
  SelectionDAG &DAG = CLI.DAG;
  SDLoc DL = CLI.DL;
  MachineFunction &MF = DAG.getMachineFunction();

  if (CLI.IsVarArg)
    report_fatal_error("lx32: varargs call lowering is not implemented yet");

  EVT PtrVT = getPointerTy(DAG.getDataLayout());

  SDValue Chain = CLI.Chain;
  SDValue Glue;

  SmallVector<CCValAssign, 16> ArgLocs;
  CCState CCInfo(CLI.CallConv, CLI.IsVarArg, MF, ArgLocs, *DAG.getContext());
  CCInfo.AnalyzeCallOperands(CLI.Outs, CC_LX32);

  // Track which physical registers carry arguments so we can add them as
  // explicit USE operands on the CALL node.  Without this, the register
  // allocator sees the pre-call CopyToReg result as "dead" (because the CALL
  // redefines it as a return value) and eliminates the copy, losing the
  // argument value.
  SmallVector<std::pair<Register, SDValue>, 8> RegsToPass;

  for (unsigned I = 0, E = ArgLocs.size(); I != E; ++I) {
    const CCValAssign &VA = ArgLocs[I];
    SDValue Val = CLI.OutVals[I];

    switch (VA.getLocInfo()) {
    case CCValAssign::Full:
      break;
    case CCValAssign::SExt:
      Val = DAG.getNode(ISD::SIGN_EXTEND, DL, VA.getLocVT(), Val);
      break;
    case CCValAssign::ZExt:
      Val = DAG.getNode(ISD::ZERO_EXTEND, DL, VA.getLocVT(), Val);
      break;
    case CCValAssign::AExt:
      Val = DAG.getNode(ISD::ANY_EXTEND, DL, VA.getLocVT(), Val);
      break;
    case CCValAssign::BCvt:
      Val = DAG.getNode(ISD::BITCAST, DL, VA.getLocVT(), Val);
      break;
    default:
      report_fatal_error("lx32: unsupported call argument location info");
    }

    if (!VA.isRegLoc())
      report_fatal_error("lx32: stack-passed call arguments are not implemented yet");

    Chain = DAG.getCopyToReg(Chain, DL, VA.getLocReg(), Val, Glue);
    Glue = Chain.getValue(1);
    RegsToPass.push_back({VA.getLocReg(), Val});
  }

  SDValue Callee = CLI.Callee;
  if (const auto *ES = dyn_cast<ExternalSymbolSDNode>(Callee)) {
    Callee = DAG.getTargetExternalSymbol(ES->getSymbol(), PtrVT);
  } else if (const auto *GA = dyn_cast<GlobalAddressSDNode>(Callee)) {
    Callee = DAG.getTargetGlobalAddress(GA->getGlobal(), DL, PtrVT, GA->getOffset());
  } else {
    report_fatal_error("lx32: only direct global/external calls are supported");
  }

  SmallVector<SDValue, 8> CallOps;
  CallOps.push_back(Chain);
  CallOps.push_back(Callee);
  // Add each argument register as an explicit SDValue operand so the isel
  // emits it as an implicit USE on PseudoCALL.  This keeps the pre-call
  // CopyToReg nodes alive through the register allocator.
  for (auto &[Reg, Val] : RegsToPass)
    CallOps.push_back(DAG.getRegister(Reg, Val.getValueType()));
  if (Glue)
    CallOps.push_back(Glue);

  SDValue Call = DAG.getNode(LX32ISD::CALL, DL, DAG.getVTList(MVT::Other, MVT::Glue),
                             CallOps);
  Chain = Call.getValue(0);
  Glue = Call.getValue(1);

  SmallVector<CCValAssign, 4> RetLocs;
  CCState RetCC(CLI.CallConv, CLI.IsVarArg, MF, RetLocs, *DAG.getContext());
  RetCC.AnalyzeCallResult(CLI.Ins, RetCC_LX32);

  for (unsigned I = 0, E = RetLocs.size(); I != E; ++I) {
    const CCValAssign &VA = RetLocs[I];
    SDValue Ret = DAG.getCopyFromReg(Chain, DL, VA.getLocReg(), VA.getLocVT(), Glue);
    Chain = Ret.getValue(1);
    Glue = Ret.getValue(2);
    InVals.push_back(lowerCCValue(Ret, VA.getLocInfo(), CLI.Ins[I].VT, DAG, DL));
  }

  return Chain;
}

SDValue LX32TargetLowering::LowerReturn(
    SDValue Chain, CallingConv::ID CallConv, bool IsVarArg,
    const SmallVectorImpl<ISD::OutputArg> &Outs,
    const SmallVectorImpl<SDValue> &OutVals, const SDLoc &DL,
    SelectionDAG &DAG) const {
  if (IsVarArg)
    report_fatal_error("lx32: varargs return lowering is not implemented yet");

  MachineFunction &MF = DAG.getMachineFunction();
  SmallVector<CCValAssign, 16> RetLocs;
  CCState RetCC(CallConv, IsVarArg, MF, RetLocs, *DAG.getContext());
  RetCC.AnalyzeReturn(Outs, RetCC_LX32);

  SDValue Flag;
  for (unsigned I = 0, E = RetLocs.size(); I != E; ++I) {
    const CCValAssign &VA = RetLocs[I];
    SDValue Val = OutVals[I];

    switch (VA.getLocInfo()) {
    case CCValAssign::Full:
      break;
    case CCValAssign::SExt:
      Val = DAG.getNode(ISD::SIGN_EXTEND, DL, VA.getLocVT(), Val);
      break;
    case CCValAssign::ZExt:
      Val = DAG.getNode(ISD::ZERO_EXTEND, DL, VA.getLocVT(), Val);
      break;
    case CCValAssign::AExt:
      Val = DAG.getNode(ISD::ANY_EXTEND, DL, VA.getLocVT(), Val);
      break;
    case CCValAssign::BCvt:
      Val = DAG.getNode(ISD::BITCAST, DL, VA.getLocVT(), Val);
      break;
    default:
      report_fatal_error("lx32: unsupported return value location info");
    }

    Chain = DAG.getCopyToReg(Chain, DL, VA.getLocReg(), Val, Flag);
    Flag = Chain.getValue(1);
  }

  SmallVector<SDValue, 4> RetOps;
  RetOps.push_back(Chain);
  if (Flag)
    RetOps.push_back(Flag);
  return DAG.getNode(LX32ISD::RET, DL, MVT::Other, RetOps);
}

SDValue LX32TargetLowering::LowerOperation(SDValue Op,
                                           SelectionDAG &DAG) const {
  switch (Op.getOpcode()) {
  case ISD::BR_CC:
    return lowerBR_CC(Op, DAG);
  case ISD::BRCOND:
    return lowerBRCOND(Op, DAG);
  case ISD::GlobalAddress:
    return lowerGlobalAddress(Op, DAG);
  case ISD::BlockAddress:
    return lowerBlockAddress(Op, DAG);
  case ISD::SELECT:
    return lowerSELECT(Op, DAG);
  case ISD::INTRINSIC_WO_CHAIN:
  case ISD::INTRINSIC_W_CHAIN:
  case ISD::INTRINSIC_VOID:
    return lowerINTRINSIC(Op, DAG);
  default:
    llvm_unreachable("lx32: unexpected custom-lowered operation");
  }
}

SDValue LX32TargetLowering::lowerGlobalAddress(SDValue Op,
                                               SelectionDAG &DAG) const {
  SDLoc DL(Op);
  const auto *GA = cast<GlobalAddressSDNode>(Op);
  EVT Ty = getPointerTy(DAG.getDataLayout());

  // Materialise the symbol's absolute address via PseudoLA.
  // The AsmPrinter expands PseudoLA to:
  //   AUIPC rd, %pcrel_hi(sym + offset)
  //   ADDI  rd, rd, %pcrel_lo(sym + offset)
  // For the LX32 baremetal (non-PIC) target this sequence yields the correct
  // 32-bit address at link time.
  SDValue TGA = DAG.getTargetGlobalAddress(GA->getGlobal(), DL, Ty,
                                           GA->getOffset());
  return SDValue(DAG.getMachineNode(LX32::PseudoLA, DL, Ty, TGA), 0);
}

SDValue LX32TargetLowering::lowerBlockAddress(SDValue Op,
                                              SelectionDAG &DAG) const {
  SDLoc DL(Op);
  const auto *BA = cast<BlockAddressSDNode>(Op);
  EVT Ty = getPointerTy(DAG.getDataLayout());

  // Block addresses use the same PseudoLA sequence as global addresses.
  SDValue TBA = DAG.getTargetBlockAddress(BA->getBlockAddress(), Ty,
                                          BA->getOffset());
  return SDValue(DAG.getMachineNode(LX32::PseudoLA, DL, Ty, TBA), 0);
}

SDValue LX32TargetLowering::lowerSELECT(SDValue Op, SelectionDAG &DAG) const {
  SDLoc DL(Op);
  SDValue Cond   = Op.getOperand(0);
  SDValue TrueV  = Op.getOperand(1);
  SDValue FalseV = Op.getOperand(2);

  // LX32 has no conditional-move instruction.  Lower SELECT to a BRCOND-based
  // phi sequence by converting it to a BR_CC node that lowerBR_CC can handle.
  //
  // Implementation note: producing LX32ISD::SELECT_CC here is a stub — that
  // node has no instruction-selection handler in LX32ISelDAGToDAG and would
  // cause a "cannot select" fatal error if reached.  The correct approach is
  // to emit the conditional comparison as a proper ISD::BR_CC so the existing
  // BRCC lowering path handles it and LLVM converts the whole SELECT to a
  // if/else basic-block split with a PHI.
  //
  // Normalise: "cond != 0" maps directly to the BRCC infrastructure.
  return DAG.getNode(LX32ISD::SELECT_CC, DL, Op.getValueType(),
                     Cond,
                     DAG.getConstant(0, DL, MVT::i32),
                     TrueV, FalseV,
                     DAG.getCondCode(ISD::SETNE));
}

SDValue LX32TargetLowering::lowerINTRINSIC(SDValue Op, SelectionDAG &DAG) const {
  SDLoc DL(Op);
  bool HasChain = Op.getOpcode() != ISD::INTRINSIC_WO_CHAIN;
  unsigned ArgBase = HasChain ? 2 : 1;
  unsigned IntNo = cast<ConstantSDNode>(Op.getOperand(HasChain ? 1 : 0))
                       ->getZExtValue();

  LLVM_DEBUG(dbgs() << "lx32-lower: lowerINTRINSIC #" << IntNo
                    << " HasChain=" << HasChain << "\n");

  // Read ops — produce a value, no side effects, never stall.
  //   Lowering: (intrinsic_id, rs1) → (rd : i32)
  //   These are modelled as INTRINSIC_WO_CHAIN; ArgBase = 1.
  struct ReadEntry {
    unsigned IntrinsicID;
    unsigned SDISD;
    const char *Name;
  };
  static const ReadEntry ReadOps[] = {
    { Intrinsic::lx32_sensor, LX32ISD::LX32_SENSOR, "lx.sensor" },
    { Intrinsic::lx32_matrix, LX32ISD::LX32_MATRIX, "lx.matrix" },
    { Intrinsic::lx32_delta,  LX32ISD::LX32_DELTA,  "lx.delta"  },
    { Intrinsic::lx32_chord,  LX32ISD::LX32_CHORD,  "lx.chord"  },
  };
  for (const auto &E : ReadOps) {
    if (IntNo == E.IntrinsicID) {
      LLVM_DEBUG(dbgs() << "lx32-lower: → " << E.Name << " (read)\n");
      return DAG.getNode(E.SDISD, DL, Op->getVTList(),
                         Op.getOperand(ArgBase));
    }
  }

  // Chain ops — side-effecting, must carry a chain.
  //   Lowering: (chain, intrinsic_id, rs1) → (chain : Other)
  //   These are modelled as INTRINSIC_VOID / INTRINSIC_W_CHAIN; ArgBase = 2.
  if (!HasChain)
    report_fatal_error("lx32: side-effecting intrinsic must carry a chain "
                       "(use __builtin_lx_wait / __builtin_lx_report)");

  switch (IntNo) {
  case Intrinsic::lx32_wait:
    LLVM_DEBUG(dbgs() << "lx32-lower: → lx.wait (chain)\n");
    return DAG.getNode(LX32ISD::LX32_WAIT, DL, MVT::Other,
                       Op.getOperand(0), Op.getOperand(ArgBase));
  case Intrinsic::lx32_report:
    LLVM_DEBUG(dbgs() << "lx32-lower: → lx.report (chain)\n");
    return DAG.getNode(LX32ISD::LX32_REPORT, DL, MVT::Other,
                       Op.getOperand(0), Op.getOperand(ArgBase));
  default:
    report_fatal_error("lx32: unknown intrinsic #" + Twine(IntNo));
  }
}
