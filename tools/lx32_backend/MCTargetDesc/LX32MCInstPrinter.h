//===-- LX32MCInstPrinter.h - Register name helper ------------------------===//
//
// Part of the LX32 Project
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

#ifndef LX32_LX32MCINSTPRINTER_H
#define LX32_LX32MCINSTPRINTER_H

#include "llvm/MC/MCRegister.h"

namespace llvm {

// Returns the ISA assembly register name (e.g. "ra", "sp", "a0") for a
// physical register number.  Wraps the TableGen-generated getRegisterName
// from LX32InstPrinter, which lives in the anonymous namespace of
// LX32MCTargetDesc.cpp and cannot be called directly from other TUs.
const char *LX32GetAsmRegName(MCRegister Reg);

} // namespace llvm

#endif // LX32_LX32MCINSTPRINTER_H
