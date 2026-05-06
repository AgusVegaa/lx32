//===-- LX32Disassembler.cpp - LX32 Instruction Disassembler -------------===//
//
// Part of the LX32 Project
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

#include "../MCTargetDesc/LX32MCTargetDesc.h"
#include "../TargetInfo/LX32TargetInfo.h"

#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCDecoder.h"
#include "llvm/MC/MCDecoderOps.h"
#include "llvm/MC/MCDisassembler/MCDisassembler.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Compiler.h"
#include "llvm/Support/Endian.h"

using namespace llvm;

#define DEBUG_TYPE "lx32-disassembler"

typedef MCDisassembler::DecodeStatus DecodeStatus;

// ── Step 1: pull in register and instruction enums ────────────────────────
// LX32::X0 … LX32::X31 are defined by GET_REGINFO_ENUM; they must be
// available before the GPRDecoderTable initialiser below.

#define GET_REGINFO_ENUM
#include "../TableGen/LX32GenRegisterInfo.inc"

#define GET_INSTRINFO_ENUM
#include "../TableGen/LX32GenInstrInfo.inc"

// ── Step 2: decoder helper functions ─────────────────────────────────────
// These are referenced by name in the auto-generated decoder table (Step 3).
// They must be defined before the table include.

static DecodeStatus DecodeGPRRegisterClass(MCInst &Inst, uint64_t RegNo,
                                            uint64_t /*Addr*/,
                                            const MCDisassembler * /*D*/) {
  static const MCPhysReg Table[32] = {
    LX32::X0,  LX32::X1,  LX32::X2,  LX32::X3,
    LX32::X4,  LX32::X5,  LX32::X6,  LX32::X7,
    LX32::X8,  LX32::X9,  LX32::X10, LX32::X11,
    LX32::X12, LX32::X13, LX32::X14, LX32::X15,
    LX32::X16, LX32::X17, LX32::X18, LX32::X19,
    LX32::X20, LX32::X21, LX32::X22, LX32::X23,
    LX32::X24, LX32::X25, LX32::X26, LX32::X27,
    LX32::X28, LX32::X29, LX32::X30, LX32::X31
  };
  if (RegNo >= 32)
    return MCDisassembler::Fail;
  Inst.addOperand(MCOperand::createReg(Table[RegNo]));
  return MCDisassembler::Success;
}

// GPRNOX0 — identical decode but reject register 0.
static DecodeStatus DecodeGPRNOX0RegisterClass(MCInst &Inst, uint64_t RegNo,
                                                uint64_t Addr,
                                                const MCDisassembler *D) {
  if (RegNo == 0)
    return MCDisassembler::Fail;
  return DecodeGPRRegisterClass(Inst, RegNo, Addr, D);
}

// ── Step 3: auto-generated decode table ───────────────────────────────────
// The generated table uses bare OPC_* names from llvm::MCD.
using namespace llvm::MCD;
#include "../TableGen/LX32GenDisassemblerTables.inc"

// ── Disassembler class ────────────────────────────────────────────────────

namespace {
class LX32Disassembler : public MCDisassembler {
public:
  LX32Disassembler(const MCSubtargetInfo &STI, MCContext &Ctx)
      : MCDisassembler(STI, Ctx) {}

  DecodeStatus getInstruction(MCInst &MI, uint64_t &Size,
                              ArrayRef<uint8_t> Bytes, uint64_t Address,
                              raw_ostream &CS) const override;
};
} // anonymous namespace

DecodeStatus LX32Disassembler::getInstruction(MCInst &MI, uint64_t &Size,
                                               ArrayRef<uint8_t> Bytes,
                                               uint64_t Address,
                                               raw_ostream &CS) const {
  if (Bytes.size() < 4) {
    Size = 0;
    return MCDisassembler::Fail;
  }
  Size = 4;
  uint32_t Inst = support::endian::read32le(Bytes.data());
  return decodeInstruction(DecoderTableLX3232, MI, Inst, Address, this, STI);
}

// ── Registration ──────────────────────────────────────────────────────────

static MCDisassembler *createLX32Disassembler(const Target & /*T*/,
                                               const MCSubtargetInfo &STI,
                                               MCContext &Ctx) {
  return new LX32Disassembler(STI, Ctx);
}

extern "C" LLVM_ABI LLVM_EXTERNAL_VISIBILITY void
LLVMInitializeLX32Disassembler() {
  TargetRegistry::RegisterMCDisassembler(getTheLX32TargetInfo(),
                                         createLX32Disassembler);
}
