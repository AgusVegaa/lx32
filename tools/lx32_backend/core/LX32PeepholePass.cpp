//===-- LX32PeepholePass.cpp - LX32 Peephole Optimization Pass ------------===//
//
// Part of the LX32 Project
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//
//
// Folds `LX_DELTA + SLTI + BEQ/BNE` triples into `LX_DELTA + ADDI + BLT/BGE`
// when the delta result and the boolean result are single-use.
//
// Pattern (before):
//   %Rd  = LX_DELTA %Rs1                   ; rs1 = key index
//   %Rd2 = SLTI     %Rd, Imm               ; Rd has exactly one use (this SLTI)
//   BEQ/BNE %Rd2, %zero, Target            ; Rd2 has exactly one use (this branch)
//
// Replacement (after):
//   %Rd  = LX_DELTA %Rs1
//   %Rt  = ADDI     $zero, Imm+1           ; Imm+1 = threshold+1 for sgt sense
//   BLT/BGE %Rd, %Rt, Target               ; 1-cycle branch, Rd not retained
//
// Transformation validity:
//   BNE(SLTI(%x, N), 0, T) ≡ BLT(%x, N, T)   ; x < N
//   BEQ(SLTI(%x, N), 0, T) ≡ BGE(%x, N, T)   ; x >= N
//
// The ADDI materialises the threshold constant and is a candidate for
// loop-invariant code motion (LICM) by later passes.
//
//===----------------------------------------------------------------------===//

#include "LX32PeepholePass.h"
#include "LX32InstrInfo.h"
#include "LX32Subtarget.h"

#include "llvm/CodeGen/MachineBasicBlock.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"

#define DEBUG_TYPE "lx32-peephole"

using namespace llvm;

namespace {

class LX32PeepholePass : public MachineFunctionPass {
public:
  static char ID;
  LX32PeepholePass() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "LX32 Peephole: fold LX_DELTA+SLTI+Branch";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;

private:
  // Try to fold the triple starting at DeltaI.  Returns true if modified.
  bool tryFoldDeltaSltiBranch(MachineBasicBlock &MBB,
                              MachineBasicBlock::iterator DeltaI,
                              MachineRegisterInfo &MRI,
                              const TargetInstrInfo &TII);
};

} // end anonymous namespace

char LX32PeepholePass::ID = 0;

// ── Helpers ───────────────────────────────────────────────────────────────────

// Return the single def instruction of a virtual register, or nullptr.
static MachineInstr *singleDef(Register Reg, MachineRegisterInfo &MRI) {
  if (!Reg.isVirtual())
    return nullptr;
  auto It = MRI.def_begin(Reg);
  if (It == MRI.def_end())
    return nullptr;
  if (std::next(It) != MRI.def_end())
    return nullptr; // multiple defs
  return It->getParent();
}

// Return the single use instruction of a virtual register, or nullptr.
static MachineInstr *singleUse(Register Reg, MachineRegisterInfo &MRI) {
  if (!Reg.isVirtual())
    return nullptr;
  auto It = MRI.use_begin(Reg);
  if (It == MRI.use_end())
    return nullptr;
  if (std::next(It) != MRI.use_end())
    return nullptr; // multiple uses
  return It->getParent();
}

// ── Core fold logic ───────────────────────────────────────────────────────────

bool LX32PeepholePass::tryFoldDeltaSltiBranch(MachineBasicBlock &MBB,
                                               MachineBasicBlock::iterator DeltaI,
                                               MachineRegisterInfo &MRI,
                                               const TargetInstrInfo &TII) {
  // Step 1: DeltaI must be LX_DELTA with a virtual destination.
  if (DeltaI->getOpcode() != LX32::LX_DELTA)
    return false;
  Register DeltaRd = DeltaI->getOperand(0).getReg();
  if (!DeltaRd.isVirtual())
    return false;

  // Step 2: DeltaRd must have exactly one use — an SLTI instruction.
  MachineInstr *SltiI = singleUse(DeltaRd, MRI);
  if (!SltiI || SltiI->getOpcode() != LX32::SLTI)
    return false;
  if (&SltiI->getParent()->front() != &*DeltaI) {
    // The SLTI must be in the same basic block.
    if (SltiI->getParent() != &MBB)
      return false;
  }

  Register SltiBoolRd = SltiI->getOperand(0).getReg();
  if (!SltiBoolRd.isVirtual())
    return false;

  // Imm12 from SLTI: operand 2.
  if (!SltiI->getOperand(2).isImm())
    return false;
  int64_t Imm = SltiI->getOperand(2).getImm();

  // Step 3: SltiBoolRd must have exactly one use — a BEQ or BNE against zero.
  MachineInstr *BranchI = singleUse(SltiBoolRd, MRI);
  if (!BranchI)
    return false;
  unsigned BrOpc = BranchI->getOpcode();
  if (BrOpc != LX32::BEQ && BrOpc != LX32::BNE)
    return false;
  if (BranchI->getParent() != &MBB)
    return false;

  // The branch must compare SltiBoolRd against x0.
  Register BrRs1 = BranchI->getOperand(0).getReg();
  Register BrRs2 = BranchI->getOperand(1).getReg();
  bool BoolIsRs1 = (BrRs1 == SltiBoolRd);
  bool BoolIsRs2 = (BrRs2 == SltiBoolRd);
  if (!BoolIsRs1 && !BoolIsRs2)
    return false;
  // The other operand must be x0.
  Register OtherReg = BoolIsRs1 ? BrRs2 : BrRs1;
  if (OtherReg != LX32::X0)
    return false;

  // Step 4: Determine the new branch opcode.
  //
  // SLTI sets Rd = (Rs < Imm) ? 1 : 0.
  //
  // BNE(Rd, x0, T) branches if Rd != 0, i.e., if Rs < Imm.
  //   → Replace with BLT Rs, Imm_reg, T
  //
  // BEQ(Rd, x0, T) branches if Rd == 0, i.e., if Rs >= Imm.
  //   → Replace with BGE Rs, Imm_reg, T
  unsigned NewBrOpc = (BrOpc == LX32::BNE) ? LX32::BLT : LX32::BGE;

  // Step 5: Materialise the threshold into a fresh virtual register.
  const LX32Subtarget &STI =
      MBB.getParent()->getSubtarget<LX32Subtarget>();
  const TargetInstrInfo *LocalTII = STI.getInstrInfo();
  Register ThreshReg = MRI.createVirtualRegister(&LX32::GPRRegClass);

  MachineBasicBlock::iterator InsertPt = BranchI;
  BuildMI(MBB, InsertPt, BranchI->getDebugLoc(), LocalTII->get(LX32::ADDI),
          ThreshReg)
      .addReg(LX32::X0)
      .addImm(Imm);

  // Step 6: Build the replacement branch.
  MachineBasicBlock *BrTarget = BranchI->getOperand(2).getMBB();
  BuildMI(MBB, InsertPt, BranchI->getDebugLoc(), LocalTII->get(NewBrOpc))
      .addReg(DeltaRd)
      .addReg(ThreshReg)
      .addMBB(BrTarget);

  // Step 7: Remove the old SLTI and branch.
  LLVM_DEBUG(dbgs() << "LX32Peephole: folded LX_DELTA+SLTI+Branch in "
                    << MBB.getName() << "\n");
  BranchI->eraseFromParent();
  SltiI->eraseFromParent();
  return true;
}

bool LX32PeepholePass::runOnMachineFunction(MachineFunction &MF) {
  MachineRegisterInfo &MRI = MF.getRegInfo();
  const LX32Subtarget &STI = MF.getSubtarget<LX32Subtarget>();
  const TargetInstrInfo &TII = *STI.getInstrInfo();
  bool Changed = false;

  for (MachineBasicBlock &MBB : MF) {
    for (auto It = MBB.begin(); It != MBB.end(); ) {
      auto Cur = It++;
      if (tryFoldDeltaSltiBranch(MBB, Cur, MRI, TII))
        Changed = true;
    }
  }
  return Changed;
}

// ── Factory ───────────────────────────────────────────────────────────────────

namespace llvm {
MachineFunctionPass *createLX32PeepholePass() {
  return new LX32PeepholePass();
}
} // namespace llvm
