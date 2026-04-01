/*
 * LX32Subtarget.cpp
 * -----------------
 *
 * Minimal, buildable subtarget implementation.
 *
 * In a fully featured backend this file would:
 *  - Own/initialize subtarget-specific helper objects (frame lowering, instr
 *    info, register info, lowering, sched model, etc.).
 *  - Parse feature strings and record which ISA extensions are enabled.
 *
 * For now we intentionally keep it small so the target can be configured and
 * compiled while other components are still stubs.
 */

#include "LX32Subtarget.h"

namespace llvm {

LX32Subtarget::LX32Subtarget(const Triple &TT, StringRef CPU, StringRef TuneCPU,
                             StringRef FS, const LX32TargetMachine &TM)
    : LX32GenSubtargetInfo(TT, CPU, TuneCPU, FS) {
  (void)TM;

  // The generated ParseSubtargetFeatures() currently does not toggle anything
  // for LX32, but we still call it so feature plumbing is in place.
  ParseSubtargetFeatures(CPU, TuneCPU, FS);
}

} // namespace llvm

