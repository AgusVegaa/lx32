//===-- LX32MCCodeEmitter.cpp - Convert LX32 code to machine code --------===//
// Part of the LX32 Project
// SPDX-License-Identifier: MIT
//===----------------------------------------------------------------------===//
#include "LX32MCTargetDesc.h"
#include "llvm/MC/MCCodeEmitter.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/Support/EndianStream.h"
#include "llvm/Support/Endian.h"
#include "llvm/Support/ErrorHandling.h"

using namespace llvm;

#define GET_INSTRINFO_ENUM
#include "LX32GenInstrInfo.inc"

#define DEBUG_TYPE "mccodeemitter"

namespace {
class LX32MCCodeEmitter : public MCCodeEmitter {
  const MCInstrInfo &MCII;
  MCContext &Ctx;

public:
  LX32MCCodeEmitter(const MCInstrInfo &mcii, MCContext &ctx)
      : MCII(mcii), Ctx(ctx) {}

  void encodeInstruction(const MCInst &MI, SmallVectorImpl<char> &CB,
                         SmallVectorImpl<MCFixup> &Fixups,
                         const MCSubtargetInfo &STI) const override;

  uint64_t getBinaryCodeForInstr(const MCInst &MI,
                                 SmallVectorImpl<MCFixup> &Fixups,
                                 const MCSubtargetInfo &STI) const;

  unsigned getMachineOpValue(const MCInst &MI, const MCOperand &MO,
                             SmallVectorImpl<MCFixup> &Fixups,
                             const MCSubtargetInfo &STI) const;

  unsigned getImmOpValue(const MCInst &MI, unsigned OpNo,
                         SmallVectorImpl<MCFixup> &Fixups,
                         const MCSubtargetInfo &STI) const {
    return getMachineOpValue(MI, MI.getOperand(OpNo), Fixups, STI);
  }

  unsigned getBranchTargetOpValue(const MCInst &MI, unsigned OpNo,
                                  SmallVectorImpl<MCFixup> &Fixups,
                                  const MCSubtargetInfo &STI) const {
    const MCOperand &MO = MI.getOperand(OpNo);
    if (MO.isExpr()) {
      Fixups.push_back(MCFixup::create(0, MO.getExpr(),
                                       (MCFixupKind)LX32Fixups::fixup_lx32_branch,
                                       /*PCRel=*/true));
      return 0;
    }
    return getMachineOpValue(MI, MO, Fixups, STI);
  }

  unsigned getJumpTargetOpValue(const MCInst &MI, unsigned OpNo,
                                SmallVectorImpl<MCFixup> &Fixups,
                                const MCSubtargetInfo &STI) const {
    const MCOperand &MO = MI.getOperand(OpNo);
    if (MO.isExpr()) {
      Fixups.push_back(MCFixup::create(0, MO.getExpr(),
                                       (MCFixupKind)LX32Fixups::fixup_lx32_jump,
                                       /*PCRel=*/true));
      return 0;
    }
    return getMachineOpValue(MI, MO, Fixups, STI);
  }
};
} // end anonymous namespace

MCCodeEmitter *llvm::createLX32MCCodeEmitter(const MCInstrInfo &MCII,
                                             MCContext &Ctx) {
  return new LX32MCCodeEmitter(MCII, Ctx);
}

void LX32MCCodeEmitter::encodeInstruction(const MCInst &MI, SmallVectorImpl<char> &CB,
                                          SmallVectorImpl<MCFixup> &Fixups,
                                          const MCSubtargetInfo &STI) const {
  // PseudoLA is expanded to LUI+ADDI by the AsmParser and must never reach here.
  if (MI.getOpcode() == LX32::PseudoLA)
    report_fatal_error("lx32: PseudoLA reached the code emitter unexpanded");
  uint64_t Bits = getBinaryCodeForInstr(MI, Fixups, STI);
  support::endian::write<uint32_t>(CB, Bits, llvm::endianness::little);
}

unsigned LX32MCCodeEmitter::getMachineOpValue(const MCInst &MI, const MCOperand &MO,
                                              SmallVectorImpl<MCFixup> &Fixups,
                                              const MCSubtargetInfo &STI) const {
  if (MO.isReg())
    return Ctx.getRegisterInfo()->getEncodingValue(MO.getReg());

  if (MO.isImm())
    return static_cast<unsigned>(MO.getImm());

  if (MO.isExpr()) {
    // Choose fixup kind based on the instruction: LUI→hi20, others→lo12_i.
    MCFixupKind Kind = (MI.getOpcode() == LX32::LUI)
        ? (MCFixupKind)LX32Fixups::fixup_lx32_hi20
        : (MCFixupKind)LX32Fixups::fixup_lx32_lo12_i;
    Fixups.push_back(MCFixup::create(0, MO.getExpr(), Kind, /*PCRel=*/false));
    return 0;
  }
  return 0;
}

#include "../TableGen/LX32GenMCCodeEmitter.inc"

