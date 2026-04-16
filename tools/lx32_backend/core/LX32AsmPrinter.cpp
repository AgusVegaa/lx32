//===-- LX32AsmPrinter.cpp - LX32 Assembly Printer ------------------------===//
//
// Part of the LX32 Project
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

#include "LX32InstrInfo.h"
#include "LX32TargetMachine.h"

#include "../TargetInfo/LX32TargetInfo.h"

#include "llvm/CodeGen/AsmPrinter.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstBuilder.h"
#include "llvm/MC/MCStreamer.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

#define DEBUG_TYPE "lx32-asmprinter"

using namespace llvm;

namespace {

class LX32MCInstLower {
  AsmPrinter &Printer;
  MCContext &Ctx;

public:
  explicit LX32MCInstLower(AsmPrinter &Printer, MCContext &Ctx)
      : Printer(Printer), Ctx(Ctx) {}

  const MCExpr *lowerSymbolOperand(const MachineOperand &MO) const {
    const MCSymbol *Sym = nullptr;
    int64_t Offset = 0;

    switch (MO.getType()) {
    default:
      return nullptr;
    case MachineOperand::MO_GlobalAddress:
      Sym = Printer.getSymbol(MO.getGlobal());
      Offset = MO.getOffset();
      break;
    case MachineOperand::MO_MachineBasicBlock:
      Sym = MO.getMBB()->getSymbol();
      break;
    case MachineOperand::MO_ExternalSymbol:
      Sym = Printer.GetExternalSymbolSymbol(MO.getSymbolName());
      break;
    case MachineOperand::MO_BlockAddress:
      Sym = Printer.GetBlockAddressSymbol(MO.getBlockAddress());
      Offset = MO.getOffset();
      break;
    case MachineOperand::MO_ConstantPoolIndex:
      Sym = Printer.GetCPISymbol(MO.getIndex());
      Offset = MO.getOffset();
      break;
    case MachineOperand::MO_JumpTableIndex:
      Sym = Printer.GetJTISymbol(MO.getIndex());
      break;
    }

    const MCExpr *Expr = MCSymbolRefExpr::create(Sym, Ctx);
    if (Offset != 0)
      Expr = MCBinaryExpr::createAdd(
          Expr, MCConstantExpr::create(Offset, Ctx), Ctx);
    return Expr;
  }

  bool lowerOperand(const MachineOperand &MO, MCOperand &MCOp) const {
    switch (MO.getType()) {
    default:
      return false;
    case MachineOperand::MO_Register:
      if (MO.isImplicit())
        return false;
      MCOp = MCOperand::createReg(MO.getReg());
      return true;
    case MachineOperand::MO_Immediate:
      MCOp = MCOperand::createImm(MO.getImm());
      return true;
    case MachineOperand::MO_CImmediate:
      MCOp = MCOperand::createImm(MO.getCImm()->getSExtValue());
      return true;
    case MachineOperand::MO_FPImmediate:
      return false;
    case MachineOperand::MO_MachineBasicBlock:
    case MachineOperand::MO_GlobalAddress:
    case MachineOperand::MO_ExternalSymbol:
    case MachineOperand::MO_BlockAddress:
    case MachineOperand::MO_ConstantPoolIndex:
    case MachineOperand::MO_JumpTableIndex: {
      const MCExpr *Expr = lowerSymbolOperand(MO);
      if (!Expr)
        return false;
      MCOp = MCOperand::createExpr(Expr);
      return true;
    }
    }
  }

  void lower(const MachineInstr *MI, MCInst &OutMI) const {
    OutMI.setOpcode(MI->getOpcode());
    for (const MachineOperand &MO : MI->operands()) {
      MCOperand MCOp;
      if (lowerOperand(MO, MCOp))
        OutMI.addOperand(MCOp);
    }
  }
};

class LX32AsmPrinter : public AsmPrinter {
  LX32MCInstLower MCILower;

public:
  explicit LX32AsmPrinter(TargetMachine &TM,
                          std::unique_ptr<MCStreamer> Streamer)
      : AsmPrinter(TM, std::move(Streamer)), MCILower(*this, OutContext) {}

  StringRef getPassName() const override { return "LX32 Assembly Printer"; }

  void emitInstruction(const MachineInstr *MI) override {
    LLVM_DEBUG({
      dbgs() << "lx32-asmprinter: emitting opc=" << MI->getOpcode();
      if (MI->getNumOperands() > 0) {
        dbgs() << " (";
        for (unsigned I = 0, E = MI->getNumOperands(); I != E; ++I) {
          if (I) dbgs() << ", ";
          MI->getOperand(I).print(dbgs());
        }
        dbgs() << ")";
      }
      dbgs() << "\n";
    });

    switch (MI->getOpcode()) {
    default:
      break;
    case LX32::PseudoRET: {
      LLVM_DEBUG(dbgs() << "lx32-asmprinter: PseudoRET → JALR x0, ra, 0\n");
      MCInst Ret;
      Ret.setOpcode(LX32::JALR);
      Ret.addOperand(MCOperand::createReg(LX32::X0));
      Ret.addOperand(MCOperand::createReg(LX32::X1));
      Ret.addOperand(MCOperand::createImm(0));
      EmitToStreamer(*OutStreamer, Ret);
      return;
    }
    case LX32::PseudoNOP: {
      LLVM_DEBUG(dbgs() << "lx32-asmprinter: PseudoNOP → ADDI x0, x0, 0\n");
      MCInst Nop;
      Nop.setOpcode(LX32::ADDI);
      Nop.addOperand(MCOperand::createReg(LX32::X0));
      Nop.addOperand(MCOperand::createReg(LX32::X0));
      Nop.addOperand(MCOperand::createImm(0));
      EmitToStreamer(*OutStreamer, Nop);
      return;
    }
    case LX32::PseudoCALL: {
      // Support both call forms used by the backend:
      //  1) register-held target  -> jalr ra, rs1, 0
      //  2) direct symbol target  -> jal  ra, symbol
      Register Base = 0;
      MCOperand TargetSym;
      bool HasTargetSym = false;
      for (const MachineOperand &MO : MI->operands()) {
        if (MO.isReg() && MO.getReg() != 0 && !MO.isImplicit()) {
          Base = MO.getReg();
          break;
        }
        if (!HasTargetSym &&
            (MO.isGlobal() || MO.isSymbol() || MO.isMBB() ||
             MO.isBlockAddress() || MO.isCPI() || MO.isJTI())) {
          HasTargetSym = MCILower.lowerOperand(MO, TargetSym);
        }
      }

      if (Base) {
        MCInst Call;
        Call.setOpcode(LX32::JALR);
        Call.addOperand(MCOperand::createReg(LX32::X1));
        Call.addOperand(MCOperand::createReg(Base));
        Call.addOperand(MCOperand::createImm(0));
        EmitToStreamer(*OutStreamer, Call);
        return;
      }

      if (HasTargetSym) {
        MCInst Call;
        Call.setOpcode(LX32::JAL);
        Call.addOperand(MCOperand::createReg(LX32::X1));
        Call.addOperand(TargetSym);
        EmitToStreamer(*OutStreamer, Call);
        return;
      }

      std::string Dump;
      raw_string_ostream OS(Dump);
      MI->print(OS);
      report_fatal_error(Twine("lx32: malformed PseudoCALL (missing callable target operand): ") +
                         OS.str());
    }
    case LX32::PseudoBEQ:
    case LX32::PseudoBNE:
    case LX32::PseudoBLT:
    case LX32::PseudoBGE:
    case LX32::PseudoBLTU:
    case LX32::PseudoBGEU: {
      // Map each pseudo conditional branch to its real B-type instruction.
      // Operand layout (PseudoCondBr): 0=rs1, 1=rs2, 2=target (MBB).
      static const unsigned RealOpc[] = {
          LX32::BEQ, LX32::BNE, LX32::BLT,
          LX32::BGE, LX32::BLTU, LX32::BGEU,
      };
      static const unsigned PseudoOpc[] = {
          LX32::PseudoBEQ, LX32::PseudoBNE, LX32::PseudoBLT,
          LX32::PseudoBGE, LX32::PseudoBLTU, LX32::PseudoBGEU,
      };
      unsigned RealOpcode = LX32::BEQ;
      for (unsigned i = 0; i < 6; ++i) {
        if (MI->getOpcode() == PseudoOpc[i]) {
          RealOpcode = RealOpc[i];
          break;
        }
      }
      MCOperand RS1, RS2, Target;
      MCILower.lowerOperand(MI->getOperand(0), RS1);
      MCILower.lowerOperand(MI->getOperand(1), RS2);
      MCILower.lowerOperand(MI->getOperand(2), Target);
      MCInst Branch;
      Branch.setOpcode(RealOpcode);
      Branch.addOperand(RS1);
      Branch.addOperand(RS2);
      Branch.addOperand(Target);
      EmitToStreamer(*OutStreamer, Branch);
      return;
    }
    case LX32::PseudoLA: {
      // Materialise a 32-bit absolute symbol address using two instructions:
      //
      //   AUIPC rd, %pcrel_hi(sym)    — rd  = PC + upper(sym - PC)
      //   ADDI  rd, rd, %pcrel_lo(.) — rd += lower(sym - PC)
      //
      // Both instructions reference the same symbol expression.  The ELF
      // relocations R_RISCV_PCREL_HI20 (on AUIPC) and R_RISCV_PCREL_LO12_I
      // (on ADDI) instruct the linker to patch each immediate with the
      // appropriate portion of the PC-relative offset.
      //
      // NOTE: for the LX32 baremetal target the runtime load address is fixed
      // by the linker script, so PC-relative and absolute addressing produce
      // identical final values.  A future PIC variant would use the same
      // AUIPC+ADDI sequence with dynamic-linking relocations.
      //
      // TODO: introduce LX32MCExpr with VK_PCREL_HI / VK_PCREL_LO variants
      // so that the object-file emitter applies the correct ELF relocation
      // types rather than emitting the raw symbol reference.  The current
      // implementation is correct for the assembly-text (.s) pipeline because
      // the integrated assembler resolves the symbols; it is NOT correct for
      // direct object-code emission when PseudoLA is used for globals.
      MCOperand RD, SymOp;
      if (!MCILower.lowerOperand(MI->getOperand(0), RD) ||
          !MCILower.lowerOperand(MI->getOperand(1), SymOp))
        report_fatal_error("lx32: failed to lower PseudoLA operands");

      MCInst Auipc;
      Auipc.setOpcode(LX32::AUIPC);
      Auipc.addOperand(RD);
      Auipc.addOperand(SymOp); // %pcrel_hi — linker resolves to upper 20 bits
      EmitToStreamer(*OutStreamer, Auipc);

      MCInst Addi;
      Addi.setOpcode(LX32::ADDI);
      Addi.addOperand(RD);
      Addi.addOperand(RD);
      Addi.addOperand(SymOp); // %pcrel_lo — linker resolves to lower 12 bits
      EmitToStreamer(*OutStreamer, Addi);
      return;
    }
    }

    MCInst TmpInst;
    MCILower.lower(MI, TmpInst);
    EmitToStreamer(*OutStreamer, TmpInst);
  }
};

} // end anonymous namespace

extern "C" LLVM_ABI LLVM_EXTERNAL_VISIBILITY void LLVMInitializeLX32AsmPrinter() {
  RegisterAsmPrinter<LX32AsmPrinter> X(getTheLX32TargetInfo());
}





