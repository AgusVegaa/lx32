//===-- LX32FrameLowering.cpp - LX32 Frame Lowering Implementation -------===//
//
// Part of the LX32 Project
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

#include "LX32FrameLowering.h"

#include "LX32InstrInfo.h"
#include "LX32RegisterInfo.h"
#include "LX32Subtarget.h"

#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/Target/TargetMachine.h"

using namespace llvm;

LX32FrameLowering::LX32FrameLowering(const LX32Subtarget &STI)
    : TargetFrameLowering(StackGrowsDown, Align(16), 0), STI(STI) {}

void LX32FrameLowering::emitPrologue(MachineFunction &MF,
                                     MachineBasicBlock &MBB) const {
  const MachineFrameInfo &MFI = MF.getFrameInfo();
  int64_t StackSize = MFI.getStackSize();
  if (StackSize == 0)
    return;

  const LX32InstrInfo &TII = static_cast<const LX32InstrInfo &>(*STI.getInstrInfo());
  MachineBasicBlock::iterator MBBI = MBB.begin();
  DebugLoc DL = (MBBI != MBB.end()) ? MBBI->getDebugLoc() : DebugLoc();
  TII.adjustReg(MBB, MBBI, DL, LX32::X2, LX32::X2, -StackSize,
                MachineInstr::FrameSetup);

  if (hasFP(MF))
    TII.adjustReg(MBB, MBBI, DL, LX32::X8, LX32::X2, 0,
                  MachineInstr::FrameSetup);
}

void LX32FrameLowering::emitEpilogue(MachineFunction &MF,
                                     MachineBasicBlock &MBB) const {
  const MachineFrameInfo &MFI = MF.getFrameInfo();
  int64_t StackSize = MFI.getStackSize();
  if (StackSize == 0)
    return;

  const LX32InstrInfo &TII = static_cast<const LX32InstrInfo &>(*STI.getInstrInfo());
  MachineBasicBlock::iterator MBBI = MBB.getFirstTerminator();
  DebugLoc DL = (MBBI != MBB.end()) ? MBBI->getDebugLoc() : DebugLoc();

  if (hasFP(MF))
    TII.adjustReg(MBB, MBBI, DL, LX32::X2, LX32::X8, 0,
                  MachineInstr::FrameDestroy);

  TII.adjustReg(MBB, MBBI, DL, LX32::X2, LX32::X2, StackSize,
                MachineInstr::FrameDestroy);
}

bool LX32FrameLowering::hasFPImpl(const MachineFunction &MF) const {
  // Never use a dedicated frame-pointer register (x8).  Emitting
  //   ADD x8, x2, x0   in the prologue without first saving x8 breaks
  // the ILP32 calling convention: x8 is callee-saved (CSR_LX32_ILP32),
  // so every callee that adopts it as FP silently clobbers the caller's
  // x8.  SP-relative addressing (x2) works fine for LX32's fixed-size
  // frames and avoids the issue entirely.
  const MachineFrameInfo &MFI = MF.getFrameInfo();
  return MFI.hasVarSizedObjects() || MFI.isFrameAddressTaken();
}

bool LX32FrameLowering::hasReservedCallFrame(const MachineFunction &MF) const {
  return !MF.getFrameInfo().hasVarSizedObjects();
}

MachineBasicBlock::iterator LX32FrameLowering::eliminateCallFramePseudoInstr(
    MachineFunction &MF, MachineBasicBlock &MBB,
    MachineBasicBlock::iterator MI) const {
  if (!hasReservedCallFrame(MF)) {
    const LX32InstrInfo &TII =
        static_cast<const LX32InstrInfo &>(*STI.getInstrInfo());
    DebugLoc DL = MI->getDebugLoc();
    int64_t Amount = MI->getOperand(0).getImm();

    if (Amount != 0) {
      if (MI->getOpcode() == LX32::ADJCALLSTACKDOWN)
        Amount = -Amount;
      TII.adjustReg(MBB, MI, DL, LX32::X2, LX32::X2, Amount,
                    MI->getOpcode() == LX32::ADJCALLSTACKDOWN
                        ? MachineInstr::FrameSetup
                        : MachineInstr::FrameDestroy);
    }
  }

  return MBB.erase(MI);
}

StackOffset LX32FrameLowering::getFrameIndexReference(const MachineFunction &MF,
                                                      int FI,
                                                      Register &FrameReg) const {
  const MachineFrameInfo &MFI = MF.getFrameInfo();
  FrameReg = hasFP(MF) ? LX32::X8 : LX32::X2;
  return StackOffset::getFixed(MFI.getObjectOffset(FI) + MFI.getStackSize());
}

