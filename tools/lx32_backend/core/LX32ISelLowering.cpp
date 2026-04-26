//===-- LX32ISelLowering.cpp - LX32 SelectionDAG Lowering ----------------===//
//
// Part of the LX32 Project
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

#include "LX32ISelLowering.h"

#include "LX32InstrInfo.h"
#include "LX32RegisterInfo.h"
#include "LX32Subtarget.h"

#include "llvm/CodeGen/MachineBasicBlock.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
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

  // No sign-extend-inreg hardware; expand to shift pairs (sll + sra).
  setOperationAction(ISD::SIGN_EXTEND_INREG, MVT::i16, Expand);
  setOperationAction(ISD::SIGN_EXTEND_INREG, MVT::i8,  Expand);
  setOperationAction(ISD::SIGN_EXTEND_INREG, MVT::i1,  Expand);

  // ── i64 expansion support ───────────────────────────────────────────────────
  // LX32 is a 32-bit integer-only target.  i64 values are split into two i32
  // registers.  LLVM needs all carry/overflow helpers explicitly marked Expand
  // so the legalizer uses the pure-i32 ADD+SETULT fallback (not a non-existent
  // hardware instruction).
  //
  // Without these, UADDO/UADDO_CARRY/ADDC etc. default to "Legal" (because
  // MVT::i32 is a legal type) but have no TableGen patterns — crashing during
  // instruction selection for any function that uses 64-bit arithmetic.
  setOperationAction(ISD::ADDC,        MVT::i32, Expand);
  setOperationAction(ISD::ADDE,        MVT::i32, Expand);
  setOperationAction(ISD::SUBC,        MVT::i32, Expand);
  setOperationAction(ISD::SUBE,        MVT::i32, Expand);
  setOperationAction(ISD::UADDO,       MVT::i32, Expand);
  setOperationAction(ISD::USUBO,       MVT::i32, Expand);
  setOperationAction(ISD::UADDO_CARRY, MVT::i32, Expand);
  setOperationAction(ISD::USUBO_CARRY, MVT::i32, Expand);

  // i64 shifts: no *_PARTS instruction exists; fall back to __ashldi3 etc.
  // libcalls provided by compiler_builtins.
  setOperationAction(ISD::SHL_PARTS, MVT::i32, Expand);
  setOperationAction(ISD::SRL_PARTS, MVT::i32, Expand);
  setOperationAction(ISD::SRA_PARTS, MVT::i32, Expand);

  // SELECT_CC: lower to LX32ISD::SELECT_CC which PseudoSELECT_CC selects and
  // EmitInstrWithCustomInserter expands to a branch diamond.
  setOperationAction(ISD::SELECT_CC, MVT::i32, Custom);

  // SELECT: LX32 has no conditional-move instruction.  Lower to a branch
  // sequence (see lowerSELECT) so the DAG-to-DAG pass can emit real branches.
  setOperationAction(ISD::SELECT, MVT::i32, Custom);

  // Keep setcc/branch boolean semantics explicit for DAG combines.
  setBooleanContents(ZeroOrOneBooleanContent);

  // Lower branches with explicit condition codes to a target node so the
  // selector never has to re-interpret generic BR_CC/SETCC combinations.
  setOperationAction(ISD::BR_CC, MVT::i32, Custom);
  setOperationAction(ISD::BRCOND, MVT::Other, Custom);

  setOperationAction(ISD::INTRINSIC_WO_CHAIN, MVT::Other, Custom);
  setOperationAction(ISD::INTRINSIC_W_CHAIN,  MVT::Other, Custom);
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

  // ── Soft-float: arithmetic ─────────────────────────────────────────────────
  // LX32 has no FPU; all f32/f64 ops map to standard compiler_builtins/libgcc
  // soft-float routines.  The RTLIB system needs explicit impl registrations
  // because setTargetRuntimeLibcallSets() does not know about the lx32 triple.
  setLibcallImpl(RTLIB::ADD_F32, RTLIB::impl___addsf3);
  setLibcallImpl(RTLIB::ADD_F64, RTLIB::impl___adddf3);
  setLibcallImpl(RTLIB::SUB_F32, RTLIB::impl___subsf3);
  setLibcallImpl(RTLIB::SUB_F64, RTLIB::impl___subdf3);
  setLibcallImpl(RTLIB::MUL_F32, RTLIB::impl___mulsf3);
  setLibcallImpl(RTLIB::MUL_F64, RTLIB::impl___muldf3);
  setLibcallImpl(RTLIB::DIV_F32, RTLIB::impl___divsf3);
  setLibcallImpl(RTLIB::DIV_F64, RTLIB::impl___divdf3);

  // ── Soft-float: type conversions ───────────────────────────────────────────
  setLibcallImpl(RTLIB::FPROUND_F64_F32,   RTLIB::impl___truncdfsf2);
  setLibcallImpl(RTLIB::FPEXT_F32_F64,     RTLIB::impl___extendsfdf2);
  setLibcallImpl(RTLIB::FPTOSINT_F32_I32,  RTLIB::impl___fixsfsi);
  setLibcallImpl(RTLIB::FPTOSINT_F32_I64,  RTLIB::impl___fixsfdi);
  setLibcallImpl(RTLIB::FPTOSINT_F64_I32,  RTLIB::impl___fixdfsi);
  setLibcallImpl(RTLIB::FPTOSINT_F64_I64,  RTLIB::impl___fixdfdi);
  setLibcallImpl(RTLIB::FPTOUINT_F32_I32,  RTLIB::impl___fixunssfsi);
  setLibcallImpl(RTLIB::FPTOUINT_F32_I64,  RTLIB::impl___fixunssfdi);
  setLibcallImpl(RTLIB::FPTOUINT_F64_I32,  RTLIB::impl___fixunsdfsi);
  setLibcallImpl(RTLIB::FPTOUINT_F64_I64,  RTLIB::impl___fixunsdfdi);
  setLibcallImpl(RTLIB::SINTTOFP_I32_F32,  RTLIB::impl___floatsisf);
  setLibcallImpl(RTLIB::SINTTOFP_I32_F64,  RTLIB::impl___floatsidf);
  setLibcallImpl(RTLIB::SINTTOFP_I64_F32,  RTLIB::impl___floatdisf);
  setLibcallImpl(RTLIB::SINTTOFP_I64_F64,  RTLIB::impl___floatdidf);
  setLibcallImpl(RTLIB::UINTTOFP_I32_F32,  RTLIB::impl___floatunsisf);
  setLibcallImpl(RTLIB::UINTTOFP_I32_F64,  RTLIB::impl___floatunsidf);
  setLibcallImpl(RTLIB::UINTTOFP_I64_F32,  RTLIB::impl___floatundisf);
  setLibcallImpl(RTLIB::UINTTOFP_I64_F64,  RTLIB::impl___floatundidf);

  // ── Soft-float: comparisons ────────────────────────────────────────────────
  setLibcallImpl(RTLIB::OEQ_F32, RTLIB::impl___eqsf2);
  setLibcallImpl(RTLIB::OEQ_F64, RTLIB::impl___eqdf2);
  setLibcallImpl(RTLIB::OGE_F32, RTLIB::impl___gesf2);
  setLibcallImpl(RTLIB::OGE_F64, RTLIB::impl___gedf2);
  setLibcallImpl(RTLIB::OGT_F32, RTLIB::impl___gtsf2);
  setLibcallImpl(RTLIB::OGT_F64, RTLIB::impl___gtdf2);
  setLibcallImpl(RTLIB::OLE_F32, RTLIB::impl___lesf2);
  setLibcallImpl(RTLIB::OLE_F64, RTLIB::impl___ledf2);
  setLibcallImpl(RTLIB::OLT_F32, RTLIB::impl___ltsf2);
  setLibcallImpl(RTLIB::OLT_F64, RTLIB::impl___ltdf2);
  setLibcallImpl(RTLIB::UNE_F32, RTLIB::impl___nesf2);
  setLibcallImpl(RTLIB::UNE_F64, RTLIB::impl___nedf2);
  setLibcallImpl(RTLIB::UO_F32,  RTLIB::impl___unordsf2);
  setLibcallImpl(RTLIB::UO_F64,  RTLIB::impl___unorddf2);

  // ── Soft-float: math functions ─────────────────────────────────────────────
  setLibcallImpl(RTLIB::CEIL_F32,      RTLIB::impl_ceilf);
  setLibcallImpl(RTLIB::CEIL_F64,      RTLIB::impl_ceil);
  setLibcallImpl(RTLIB::COPYSIGN_F32,  RTLIB::impl_copysignf);
  setLibcallImpl(RTLIB::COPYSIGN_F64,  RTLIB::impl_copysign);
  setLibcallImpl(RTLIB::FLOOR_F32,     RTLIB::impl_floorf);
  setLibcallImpl(RTLIB::FLOOR_F64,     RTLIB::impl_floor);
  setLibcallImpl(RTLIB::FMAX_F32,      RTLIB::impl_fmaxf);
  setLibcallImpl(RTLIB::FMAX_F64,      RTLIB::impl_fmax);
  setLibcallImpl(RTLIB::FMAXIMUM_F32,  RTLIB::impl_fmaximumf);
  setLibcallImpl(RTLIB::FMAXIMUM_F64,  RTLIB::impl_fmaximum);
  setLibcallImpl(RTLIB::FMIN_F32,      RTLIB::impl_fminf);
  setLibcallImpl(RTLIB::FMIN_F64,      RTLIB::impl_fmin);
  setLibcallImpl(RTLIB::FMINIMUM_F32,  RTLIB::impl_fminimumf);
  setLibcallImpl(RTLIB::FMINIMUM_F64,  RTLIB::impl_fminimum);
  setLibcallImpl(RTLIB::NEARBYINT_F32, RTLIB::impl_nearbyintf);
  setLibcallImpl(RTLIB::NEARBYINT_F64, RTLIB::impl_nearbyint);
  setLibcallImpl(RTLIB::RINT_F32,      RTLIB::impl_rintf);
  setLibcallImpl(RTLIB::RINT_F64,      RTLIB::impl_rint);
  setLibcallImpl(RTLIB::ROUND_F32,     RTLIB::impl_roundf);
  setLibcallImpl(RTLIB::ROUND_F64,     RTLIB::impl_round);
  setLibcallImpl(RTLIB::ROUNDEVEN_F32, RTLIB::impl_roundevenf);
  setLibcallImpl(RTLIB::ROUNDEVEN_F64, RTLIB::impl_roundeven);
  setLibcallImpl(RTLIB::SQRT_F32,      RTLIB::impl_sqrtf);
  setLibcallImpl(RTLIB::SQRT_F64,      RTLIB::impl_sqrt);
  setLibcallImpl(RTLIB::TRUNC_F32,     RTLIB::impl_truncf);
  setLibcallImpl(RTLIB::TRUNC_F64,     RTLIB::impl_trunc);

  // ── Integer: division/remainder (Expand → library call) ───────────────────
  setLibcallImpl(RTLIB::SDIV_I32, RTLIB::impl___divsi3);
  setLibcallImpl(RTLIB::UDIV_I32, RTLIB::impl___udivsi3);
  setLibcallImpl(RTLIB::SREM_I32, RTLIB::impl___modsi3);
  setLibcallImpl(RTLIB::UREM_I32, RTLIB::impl___umodsi3);
  setLibcallImpl(RTLIB::SDIV_I64, RTLIB::impl___divdi3);
  setLibcallImpl(RTLIB::UDIV_I64, RTLIB::impl___udivdi3);
  setLibcallImpl(RTLIB::SREM_I64, RTLIB::impl___moddi3);
  setLibcallImpl(RTLIB::UREM_I64, RTLIB::impl___umoddi3);

  // ── Integer: 64-bit helpers ────────────────────────────────────────────────
  setLibcallImpl(RTLIB::MUL_I64, RTLIB::impl___muldi3);
  setLibcallImpl(RTLIB::SHL_I64, RTLIB::impl___ashldi3);
  setLibcallImpl(RTLIB::SRA_I64, RTLIB::impl___ashrdi3);
  setLibcallImpl(RTLIB::SRL_I64, RTLIB::impl___lshrdi3);

  // ── Integer: 32-bit multiply ───────────────────────────────────────────────
  setLibcallImpl(RTLIB::MUL_I32, RTLIB::impl___mulsi3);

  // ── Integer: 128-bit helpers ───────────────────────────────────────────────
  setLibcallImpl(RTLIB::MUL_I128,  RTLIB::impl___multi3);
  setLibcallImpl(RTLIB::SDIV_I128, RTLIB::impl___divti3);
  setLibcallImpl(RTLIB::UDIV_I128, RTLIB::impl___udivti3);
  setLibcallImpl(RTLIB::SREM_I128, RTLIB::impl___modti3);
  setLibcallImpl(RTLIB::UREM_I128, RTLIB::impl___umodti3);
  setLibcallImpl(RTLIB::SHL_I128,  RTLIB::impl___ashlti3);
  setLibcallImpl(RTLIB::SRA_I128,  RTLIB::impl___ashrti3);
  setLibcallImpl(RTLIB::SRL_I128,  RTLIB::impl___lshrti3);

  // ── Memory functions ───────────────────────────────────────────────────────
  setLibcallImpl(RTLIB::MEMCPY,  RTLIB::impl_memcpy);
  setLibcallImpl(RTLIB::MEMMOVE, RTLIB::impl_memmove);
  setLibcallImpl(RTLIB::MEMSET,  RTLIB::impl_memset);
  setLibcallImpl(RTLIB::MEMCMP,  RTLIB::impl_memcmp);

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
  if (const auto *GA = dyn_cast<GlobalAddressSDNode>(Callee)) {
    Callee = DAG.getTargetGlobalAddress(GA->getGlobal(), DL, PtrVT, GA->getOffset());
  } else if (const auto *ES = dyn_cast<ExternalSymbolSDNode>(Callee)) {
    Callee = DAG.getTargetExternalSymbol(ES->getSymbol(), PtrVT);
  }
  // else: indirect call through a register — Callee is already an SDValue

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

  MachineFrameInfo &MFI = MF.getFrameInfo();
  for (unsigned I = 0, E = RetLocs.size(); I != E; ++I) {
    const CCValAssign &VA = RetLocs[I];
    SDValue Ret;
    if (VA.isRegLoc()) {
      Ret = DAG.getCopyFromReg(Chain, DL, VA.getLocReg(), VA.getLocVT(), Glue);
      Chain = Ret.getValue(1);
      Glue = Ret.getValue(2);
    } else {
      int FI = MFI.CreateFixedObject(VA.getLocVT().getStoreSize(),
                                     VA.getLocMemOffset(), false);
      SDValue FIN = DAG.getFrameIndex(FI, PtrVT);
      Ret = DAG.getLoad(VA.getLocVT(), DL, Chain, FIN,
                        MachinePointerInfo::getFixedStack(MF, FI));
      Chain = Ret.getValue(1);
    }
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

    if (VA.isRegLoc()) {
      Chain = DAG.getCopyToReg(Chain, DL, VA.getLocReg(), Val, Flag);
      Flag = Chain.getValue(1);
    } else {
      int FI = MF.getFrameInfo().CreateFixedObject(VA.getLocVT().getStoreSize(),
                                     VA.getLocMemOffset(), true);
      SDValue FIN = DAG.getFrameIndex(FI, getPointerTy(DAG.getDataLayout()));
      Chain = DAG.getStore(Chain, DL, Val, FIN,
                           MachinePointerInfo::getFixedStack(MF, FI));
    }
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
  case ISD::SELECT_CC:
    return lowerSELECT_CC(Op, DAG);
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
  // Normalise: "cond != 0" maps directly to PseudoSELECT_CC.
  // Store condition code as an i32 integer constant (ISD::CondCode enum value).
  // After type legalization Cond is already the legal integer type (i32).
  // Compare Cond != 0 to select TrueV or FalseV.
  return DAG.getNode(LX32ISD::SELECT_CC, DL, Op.getValueType(),
                     Cond,
                     DAG.getConstant(0, DL, Cond.getValueType()),
                     TrueV, FalseV,
                     DAG.getConstant((unsigned)ISD::SETNE, DL, MVT::i32));
}

SDValue LX32TargetLowering::lowerSELECT_CC(SDValue Op,
                                            SelectionDAG &DAG) const {
  SDLoc DL(Op);
  ISD::CondCode CC = cast<CondCodeSDNode>(Op.getOperand(4))->get();
  // ISD::SELECT_CC(lhs, rhs, truev, falsev, cc) →
  // LX32ISD::SELECT_CC(lhs, rhs, truev, falsev, cc_as_i32_constant).
  return DAG.getNode(LX32ISD::SELECT_CC, DL, Op.getValueType(),
                     Op.getOperand(0), Op.getOperand(1),
                     Op.getOperand(2), Op.getOperand(3),
                     DAG.getConstant((unsigned)CC, DL, MVT::i32));
}

// Expand PseudoSELECT_CC (usesCustomInserter) into a branch diamond.
//
// Layout after expansion:
//   HeadMBB:  bcc lhs, rhs, IfTrueMBB   (branch-if-true)
//             (fall through to TailMBB when condition is false)
//   IfTrueMBB: j TailMBB
//   TailMBB:  dst = phi [truev, IfTrueMBB], [falsev, HeadMBB]
//             <rest of original BB>
//
// This mirrors RISC-V's EmitInstrWithCustomInserter pattern.
MachineBasicBlock *LX32TargetLowering::EmitInstrWithCustomInserter(
    MachineInstr &MI, MachineBasicBlock *HeadMBB) const {
  const TargetInstrInfo *TII =
      HeadMBB->getParent()->getSubtarget().getInstrInfo();
  DebugLoc DL = MI.getDebugLoc();
  MachineFunction *MF = HeadMBB->getParent();

  assert(MI.getOpcode() == LX32::PseudoSELECT_CC &&
         "Expected PseudoSELECT_CC");

  // Operands: dst, lhs, rhs, cc_imm, truev, falsev
  Register DstReg  = MI.getOperand(0).getReg();
  Register LHSReg  = MI.getOperand(1).getReg();
  Register RHSReg  = MI.getOperand(2).getReg();
  int64_t  CCVal   = MI.getOperand(3).getImm();
  Register TrueReg = MI.getOperand(4).getReg();
  Register FalseReg= MI.getOperand(5).getReg();

  // Map ISD::CondCode enum value to the corresponding conditional branch.
  unsigned BranchOpc;
  switch (static_cast<ISD::CondCode>(CCVal)) {
  default: llvm_unreachable("lx32: unsupported condition in PseudoSELECT_CC");
  case ISD::SETEQ:  BranchOpc = LX32::PseudoBEQ;  break;
  case ISD::SETNE:  BranchOpc = LX32::PseudoBNE;  break;
  case ISD::SETLT:  BranchOpc = LX32::PseudoBLT;  break;
  case ISD::SETGE:  BranchOpc = LX32::PseudoBGE;  break;
  case ISD::SETULT: BranchOpc = LX32::PseudoBLTU; break;
  case ISD::SETUGE: BranchOpc = LX32::PseudoBGEU; break;
  case ISD::SETGT:
    std::swap(LHSReg, RHSReg);
    BranchOpc = LX32::PseudoBLT;
    break;
  case ISD::SETLE:
    std::swap(LHSReg, RHSReg);
    BranchOpc = LX32::PseudoBGE;
    break;
  case ISD::SETUGT:
    std::swap(LHSReg, RHSReg);
    BranchOpc = LX32::PseudoBLTU;
    break;
  case ISD::SETULE:
    std::swap(LHSReg, RHSReg);
    BranchOpc = LX32::PseudoBGEU;
    break;
  }

  const BasicBlock *LLVMBB = HeadMBB->getBasicBlock();
  MachineBasicBlock *IfTrueMBB = MF->CreateMachineBasicBlock(LLVMBB);
  MachineBasicBlock *TailMBB   = MF->CreateMachineBasicBlock(LLVMBB);

  // Insert in layout order: HeadMBB → IfTrueMBB → TailMBB → (rest).
  MF->insert(std::next(HeadMBB->getIterator()), IfTrueMBB);
  MF->insert(std::next(IfTrueMBB->getIterator()), TailMBB);

  // Move instructions after MI (and HeadMBB's successors) into TailMBB.
  TailMBB->splice(TailMBB->begin(), HeadMBB,
                  std::next(MI.getIterator()), HeadMBB->end());
  TailMBB->transferSuccessors(HeadMBB);

  // HeadMBB: branch to IfTrueMBB if condition holds; fall through to TailMBB.
  BuildMI(HeadMBB, DL, TII->get(BranchOpc))
      .addReg(LHSReg).addReg(RHSReg).addMBB(IfTrueMBB);
  HeadMBB->addSuccessor(IfTrueMBB);
  HeadMBB->addSuccessor(TailMBB);

  // IfTrueMBB: unconditional jump to TailMBB.
  BuildMI(IfTrueMBB, DL, TII->get(LX32::PseudoBR)).addMBB(TailMBB);
  IfTrueMBB->addSuccessor(TailMBB);

  // TailMBB: PHI selects TrueReg (from IfTrueMBB) or FalseReg (from HeadMBB).
  BuildMI(*TailMBB, TailMBB->begin(), DL, TII->get(TargetOpcode::PHI), DstReg)
      .addReg(TrueReg).addMBB(IfTrueMBB)
      .addReg(FalseReg).addMBB(HeadMBB);

  MI.eraseFromParent();
  return TailMBB;
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
