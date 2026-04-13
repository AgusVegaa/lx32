//===-- LX32AsmParser.cpp - Parse LX32 assembly to MCInst instructions --===//
//
// Part of the LX32 Project
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

#include "../MCTargetDesc/LX32MCTargetDesc.h"
#include "../TargetInfo/LX32TargetInfo.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCParser/MCAsmParser.h"
#include "llvm/MC/MCParser/MCAsmParserExtension.h"
#include "llvm/MC/MCParser/MCParsedAsmOperand.h"
#include "llvm/MC/MCParser/MCTargetAsmParser.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCStreamer.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Casting.h"

// Put the enums here
#define GET_REGINFO_ENUM
#include "LX32GenRegisterInfo.inc"
#define GET_INSTRINFO_ENUM
#include "LX32GenInstrInfo.inc"

namespace {

class LX32Operand : public llvm::MCParsedAsmOperand {
  enum KindTy {
    Token,
    Register,
    Immediate,
  } Kind;

  llvm::StringRef Tok;
  unsigned RegNum;
  const llvm::MCExpr *ImmVal;
  llvm::SMLoc StartLoc, EndLoc;

public:
  LX32Operand(KindTy K) : llvm::MCParsedAsmOperand(), Kind(K) {}

  bool isToken() const override { return Kind == Token; }
  bool isReg() const override { return Kind == Register; }
  bool isImm() const override { return Kind == Immediate; }
  bool isMem() const override { return false; }

  static std::unique_ptr<LX32Operand> createToken(llvm::StringRef Str,
                                                  llvm::SMLoc S) {
    auto Op = std::make_unique<LX32Operand>(Token);
    Op->Tok = Str;
    Op->StartLoc = S;
    Op->EndLoc = S;
    return Op;
  }

  static std::unique_ptr<LX32Operand> createReg(unsigned RegNo, llvm::SMLoc S,
                                                llvm::SMLoc E) {
    auto Op = std::make_unique<LX32Operand>(Register);
    Op->RegNum = RegNo;
    Op->StartLoc = S;
    Op->EndLoc = E;
    return Op;
  }

  static std::unique_ptr<LX32Operand> createImm(const llvm::MCExpr *Val,
                                                llvm::SMLoc S, llvm::SMLoc E) {
    auto Op = std::make_unique<LX32Operand>(Immediate);
    Op->ImmVal = Val;
    Op->StartLoc = S;
    Op->EndLoc = E;
    return Op;
  }

  llvm::SMLoc getStartLoc() const override { return StartLoc; }
  llvm::SMLoc getEndLoc() const override { return EndLoc; }

  llvm::MCRegister getReg() const override {
    assert(Kind == Register && "Invalid access!");
    return RegNum;
  }

  const llvm::MCExpr *getImm() const {
    assert(Kind == Immediate && "Invalid access!");
    return ImmVal;
  }

  llvm::StringRef getToken() const {
    assert(Kind == Token && "Invalid access!");
    return Tok;
  }

  void print(llvm::raw_ostream &OS, const llvm::MCAsmInfo &MAI) const override {
    switch (Kind) {
    case Token:
      OS << "Token: " << Tok;
      break;
    case Register:
      OS << "Reg: " << RegNum;
      break;
    case Immediate:
      OS << "Imm";
      break;
    }
  }

  void addRegOperands(llvm::MCInst &Inst, unsigned N) const {
    assert(N == 1 && "Invalid number of operands!");
    Inst.addOperand(llvm::MCOperand::createReg(getReg()));
  }

  void addExpr(llvm::MCInst &Inst, const llvm::MCExpr *Expr) const {
    if (auto *CE = llvm::dyn_cast<llvm::MCConstantExpr>(Expr))
      Inst.addOperand(llvm::MCOperand::createImm(CE->getValue()));
    else
      Inst.addOperand(llvm::MCOperand::createExpr(Expr));
  }

  void addImmOperands(llvm::MCInst &Inst, unsigned N) const {
    assert(N == 1 && "Invalid number of operands!");
    addExpr(Inst, getImm());
  }

};
} // end anonymous namespace

namespace llvm {

class LX32AsmParser : public llvm::MCTargetAsmParser {
  const llvm::MCRegisterInfo *MRI;

  bool matchAndEmitInstruction(llvm::SMLoc IDLoc, unsigned &Opcode,
                               OperandVector &Operands, llvm::MCStreamer &Out,
                               uint64_t &ErrorInfo,
                               bool MatchingInlineAsm) override;

  bool parseRegister(llvm::MCRegister &Reg, llvm::SMLoc &StartLoc,
                     llvm::SMLoc &EndLoc) override;

  llvm::ParseStatus tryParseRegister(llvm::MCRegister &Reg,
                                     llvm::SMLoc &StartLoc,
                                     llvm::SMLoc &EndLoc) override;

  bool parseInstruction(llvm::ParseInstructionInfo &Info, llvm::StringRef Name,
                        llvm::SMLoc NameLoc, OperandVector &Operands) override;

  llvm::ParseStatus parseDirective(llvm::AsmToken DirectiveID) override;

  bool parseOperand(OperandVector &Operands, llvm::StringRef Name);

public:
  LX32AsmParser(const llvm::MCSubtargetInfo &STI, llvm::MCAsmParser &Parser,
                const llvm::MCInstrInfo &MII,
                const llvm::MCTargetOptions &Options)
      : llvm::MCTargetAsmParser(Options, STI, MII),
        MRI(Parser.getContext().getRegisterInfo()) {
    setAvailableFeatures(ComputeAvailableFeatures(STI.getFeatureBits()));
  }

#define GET_ASSEMBLER_HEADER
#include "../TableGen/LX32GenAsmMatcher.inc"
};

#define GET_REGISTER_MATCHER
#define GET_MATCHER_IMPLEMENTATION
#include "../TableGen/LX32GenAsmMatcher.inc"

} // end namespace llvm

bool llvm::LX32AsmParser::matchAndEmitInstruction(llvm::SMLoc IDLoc,
                                            unsigned &Opcode,
                                            OperandVector &Operands,
                                            llvm::MCStreamer &Out,
                                            uint64_t &ErrorInfo,
                                            bool MatchingInlineAsm) {
  llvm::MCInst Inst;
  unsigned MatchResult =
      MatchInstructionImpl(Operands, Inst, ErrorInfo, MatchingInlineAsm);
  switch (MatchResult) {
  case Match_Success:
    Inst.setLoc(IDLoc);
    Out.emitInstruction(Inst, getSTI());
    return false;
  case Match_MissingFeature:
    return Error(IDLoc,
                 "instruction requires a CPU feature not currently enabled");
  case Match_InvalidOperand:
    return Error(IDLoc, "invalid operand for instruction");
  case Match_MnemonicFail:
    return Error(IDLoc, "invalid instruction mnemonic");
  default:
    return Error(IDLoc, "unknown error matching instruction");
  }
}

bool llvm::LX32AsmParser::parseRegister(llvm::MCRegister &Reg,
                                        llvm::SMLoc &StartLoc,
                                        llvm::SMLoc &EndLoc) {
  return tryParseRegister(Reg, StartLoc, EndLoc).isSuccess() ? false : true;
}

llvm::ParseStatus llvm::LX32AsmParser::tryParseRegister(
    llvm::MCRegister &Reg, llvm::SMLoc &StartLoc, llvm::SMLoc &EndLoc) {
  const llvm::AsmToken &Tok = getParser().getTok();
  StartLoc = Tok.getLoc();
  EndLoc = Tok.getEndLoc();
  if (Tok.isNot(llvm::AsmToken::Identifier))
    return llvm::ParseStatus::NoMatch;

  llvm::StringRef Name = Tok.getString();
  unsigned RegNum = MatchRegisterName(Name.lower());
  if (RegNum == 0)
    return llvm::ParseStatus::NoMatch;

  Reg = RegNum;
  getParser().Lex(); // consume the identifier
  return llvm::ParseStatus::Success;
}

bool llvm::LX32AsmParser::parseOperand(OperandVector &Operands,
                                       llvm::StringRef Mnemonic) {
  llvm::SMLoc S = getTok().getLoc();
  if (getLexer().is(llvm::AsmToken::LParen) ||
      getLexer().is(llvm::AsmToken::RParen)) {
    Operands.push_back(LX32Operand::createToken(getTok().getString(), S));
    getLexer().Lex();
    return false;
  }

  llvm::MCRegister Reg;
  if (tryParseRegister(Reg, S, S).isSuccess()) {
    Operands.push_back(LX32Operand::createReg(Reg, S, getTok().getLoc()));
    return false;
  }

  // Handle immediate
  if (getLexer().is(llvm::AsmToken::Integer) ||
      getLexer().is(llvm::AsmToken::Minus) ||
      getLexer().is(llvm::AsmToken::Identifier)) {
    const llvm::MCExpr *IdVal;
    if (getParser().parseExpression(IdVal))
      return true;

    // Special handling for memory %lo / %hi wrappers could be here if LX32 uses
    // them. For MVP, just accept basic expressions.
    Operands.push_back(LX32Operand::createImm(IdVal, S, getTok().getLoc()));
    return false;
  }

  // Not an operand we know how to parse.
  return true;
}

bool llvm::LX32AsmParser::parseInstruction(llvm::ParseInstructionInfo &Info,
                                           llvm::StringRef Name,
                                           llvm::SMLoc NameLoc,
                                           OperandVector &Operands) {
  // First operand is token for instruction
  Operands.push_back(LX32Operand::createToken(Name, NameLoc));

  if (getLexer().is(llvm::AsmToken::EndOfStatement))
    return false;

  // Parse operands
  while (true) {
    if (parseOperand(Operands, Name)) {
      return Error(getTok().getLoc(), "unexpected token in operand");
    }

    if (getLexer().is(llvm::AsmToken::EndOfStatement))
      break;

    if (getLexer().is(llvm::AsmToken::Comma)) {
      getLexer().Lex(); // Consume comma
    } else if (getLexer().is(llvm::AsmToken::LParen) ||
               getLexer().is(llvm::AsmToken::RParen)) {
      // Handled in next loop iteration
    } else if (Operands.size() > 1 &&
               static_cast<LX32Operand *>(Operands.back().get())->isToken() &&
               (static_cast<LX32Operand *>(Operands.back().get())->getToken() ==
                    "(" ||
                static_cast<LX32Operand *>(Operands.back().get())->getToken() ==
                    ")")) {
      // Previous token was a parenthesis, no comma required before next operand
    } else if (Operands.size() > 2 &&
               static_cast<LX32Operand *>(Operands[Operands.size() - 2].get())
                   ->isToken() &&
               static_cast<LX32Operand *>(Operands[Operands.size() - 2].get())
                       ->getToken() == "(" &&
               static_cast<LX32Operand *>(Operands.back().get())->isReg()) {
      // Inside parenthesis, parsed a register, RParen comes next
    } else {
      return Error(getTok().getLoc(), "unexpected token in operand list");
    }
  }

  return false;
}

llvm::ParseStatus llvm::LX32AsmParser::parseDirective(
    llvm::AsmToken DirectiveID) {
  return llvm::ParseStatus::NoMatch; // Use default parser for directives
}

extern "C" LLVM_ABI LLVM_EXTERNAL_VISIBILITY void
LLVMInitializeLX32AsmParser() {
  llvm::TargetRegistry::RegisterMCAsmParser(
      llvm::getTheLX32TargetInfo(),
      [](const llvm::MCSubtargetInfo &STI, llvm::MCAsmParser &Parser,
         const llvm::MCInstrInfo &MII,
         const llvm::MCTargetOptions &Options) -> llvm::MCTargetAsmParser * {
        return new llvm::LX32AsmParser(STI, Parser, MII, Options);
      });
}
