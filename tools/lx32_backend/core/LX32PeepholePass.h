//===-- LX32PeepholePass.h - LX32 Peephole Optimization Pass -----*- C++ -*-===//
//
// Part of the LX32 Project
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//
//
// Target-specific MachineFunctionPass that folds:
//
//   LX_DELTA  %Rd,  %Rs1
//   SLTI      %Rd2, %Rd, Imm      ← Rd used only here
//   BEQ/BNE   %Rd2, %zero, Target ← Rd2 used only here
//
// into:
//
//   LX_DELTA  %Rd, %Rs1
//   ADDI      %Rt, zero, Imm+1    ← threshold register (CSE / LICM can hoist)
//   BLT/BGE   %Rd, %Rt, Target    ← direct compare-and-branch
//
// Motivation: in the 64-key firmware scan loop every `lx.delta` result is
// used only in a single signed comparison against a compile-time threshold.
// Eliminating the SLTI frees a register and removes one instruction per key
// — 64 instructions per scan frame at 50 MHz ≈ 1.3 µs saved.
//
// The pass runs after instruction selection, before register allocation, so
// it works on virtual registers and does not need liveness analysis.
//
//===----------------------------------------------------------------------===//

#pragma once

#include "llvm/CodeGen/MachineFunctionPass.h"

namespace llvm {

MachineFunctionPass *createLX32PeepholePass();

} // namespace llvm
