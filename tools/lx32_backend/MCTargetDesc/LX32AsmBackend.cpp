//===-- LX32AsmBackend.cpp - LX32 Assembler Backend -------------------------===//
//
// Part of the LX32 Project
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

#include "LX32MCTargetDesc.h"
#include "llvm/MC/MCAsmBackend.h"
#include "llvm/MC/MCAssembler.h"
#include "llvm/MC/MCDirectives.h"
#include "llvm/MC/MCELFObjectWriter.h"
#include "llvm/MC/MCObjectWriter.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCValue.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

namespace {
class LX32AsmBackend : public MCAsmBackend {
public:
  LX32AsmBackend(const MCSubtargetInfo &STI, uint8_t OSABI)
      : MCAsmBackend(llvm::endianness::little) {}
  ~LX32AsmBackend() override {}

  MCFixupKindInfo getFixupKindInfo(MCFixupKind Kind) const override {
    static const MCFixupKindInfo Infos[LX32Fixups::NumTargetFixupKinds -
                                       FirstTargetFixupKind] = {
        {"fixup_lx32_branch", 0, 32, 0},
        {"fixup_lx32_jump",   0, 32, 0},
    };

    if (Kind < FirstTargetFixupKind)
      return MCAsmBackend::getFixupKindInfo(Kind);

    unsigned Idx = Kind - FirstTargetFixupKind;
    if (Idx >= (LX32Fixups::NumTargetFixupKinds - FirstTargetFixupKind))
      report_fatal_error("lx32: invalid fixup kind");
    return Infos[Idx];
  }

  // Force all JAL and branch fixups to emit ELF relocations.
  //
  // Without this override the MC assembler would try to resolve jal/branch
  // targets inline.  That path computes the wrong PC-relative offset (the
  // fragment layout visible at assembly time does not match the final linked
  // layout) and — critically — leaves external symbols (e.g. "main" in
  // crt0.S) completely unpatched, producing an infinite loop.
  //
  // Returning false (unresolved) here makes applyFixup emit an R_RISCV_JAL
  // or R_RISCV_BRANCH relocation; the linker then applies the correct
  // PC-relative offset at link time.  This mirrors how the RISC-V backend
  // handles these fixups.
  std::optional<bool> evaluateFixup(const MCFragment &, MCFixup &Fixup,
                                    MCValue &, uint64_t &Value) override {
    MCFixupKind Kind = Fixup.getKind();
    if (Kind == (MCFixupKind)LX32Fixups::fixup_lx32_jump ||
        Kind == (MCFixupKind)LX32Fixups::fixup_lx32_branch) {
      Value = 0; // placeholder; linker fills the real offset
      return false; // unresolved → recordRelocation path
    }
    return {}; // default handling for all other fixups
  }

  void applyFixup(const MCFragment &Fragment, const MCFixup &Fixup,
                  const MCValue &Target, uint8_t *Data, uint64_t Value,
                  bool IsResolved) override {
    if (!IsResolved) {
      // Emit an ELF relocation so the linker can patch the PC-relative
      // offset at link time.  This is reached for all JAL/branch fixups
      // (forced unresolved by evaluateFixup above) and for any other
      // fixup whose target could not be resolved at assembly time.
      Asm->getWriter().recordRelocation(Fragment, Fixup, Target, Value);
      return;
    }
    uint32_t CurVal = 0;
    CurVal =  (uint32_t)Data[0] | ((uint32_t)Data[1] << 8) |
             ((uint32_t)Data[2] << 16) | ((uint32_t)Data[3] << 24);

    if (Fixup.getKind() == (MCFixupKind)LX32Fixups::fixup_lx32_branch) {
      // B-type: the LLVM MC framework passes Value = target - branch_pc
      // (FKF_IsPCRel subtracts the fixup address before calling us).
      // That is exactly the RISC-V branch offset — no bias needed.
      uint32_t imm = (uint32_t)(int32_t)(int64_t)Value;
      uint32_t bit11  = (imm >> 11) & 1;
      uint32_t bit4_1 = (imm >> 1)  & 0xF;
      uint32_t bit10_5 = (imm >> 5) & 0x3F;
      uint32_t bit12  = (imm >> 12) & 1;
      CurVal |= (bit11 << 7) | (bit4_1 << 8) | (bit10_5 << 25) | (bit12 << 31);
    } else if (Fixup.getKind() == (MCFixupKind)LX32Fixups::fixup_lx32_jump) {
      // J-type: same reasoning — Value = target - jal_pc, no bias needed.
      uint32_t imm = (uint32_t)(int32_t)(int64_t)Value;
      uint32_t bit19_12 = (imm >> 12) & 0xFF;
      uint32_t bit11    = (imm >> 11) & 1;
      uint32_t bit10_1  = (imm >> 1)  & 0x3FF;
      uint32_t bit20    = (imm >> 20) & 1;
      CurVal |= (bit19_12 << 12) | (bit11 << 20) | (bit10_1 << 21) | (bit20 << 31);
    }

    Data[0] = CurVal & 0xFF;
    Data[1] = (CurVal >> 8) & 0xFF;
    Data[2] = (CurVal >> 16) & 0xFF;
    Data[3] = (CurVal >> 24) & 0xFF;
  }

  bool writeNopData(raw_ostream &OS, uint64_t Count,
                    const MCSubtargetInfo *STI) const override {
    // 4-byte NOPs = addi x0, x0, 0 = 0x00000013
    uint64_t NumNops = Count / 4;
    for (uint64_t i = 0; i != NumNops; ++i)
      OS.write("\x13\x00\x00\x00", 4);

    OS.write_zeros(Count % 4);
    return true;
  }

  std::unique_ptr<MCObjectTargetWriter>
  createObjectTargetWriter() const override {
    return createLX32ELFObjectWriter(0);
  }
};
} // end anonymous namespace

MCAsmBackend *llvm::createLX32AsmBackend(const Target &T,
                                         const MCSubtargetInfo &STI,
                                         const MCRegisterInfo &MRI,
                                         const MCTargetOptions &Options) {
  return new LX32AsmBackend(STI, 0); // OSABI 0
}
