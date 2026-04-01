/*
 * LX32Subtarget.h
 * ----------------
 *
 * This project is an LLVM backend skeleton. The intent of this header is to be
 * a *minimal, buildable* subtarget definition that can be incrementally filled
 * in as codegen pieces are implemented.
 *
 * Notes for contributors:
 *  - Keep this header lightweight: prefer forward declarations when possible.
 *  - Avoid pulling in heavy CodeGen headers unless strictly required.
 *  - The generated TableGen subtarget base class is included via
 *    `LX32GenSubtargetInfo.inc` (GET_SUBTARGETINFO_HEADER section).
 */

#ifndef LLVM_LIB_TARGET_LX32_CORE_LX32SUBTARGET_H
#define LLVM_LIB_TARGET_LX32_CORE_LX32SUBTARGET_H

#include "llvm/ADT/StringRef.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCInst.h"
#include "llvm/Target/TargetMachine.h"

// This provides `LX32GenSubtargetInfo`, which we derive from.
#define GET_SUBTARGETINFO_HEADER
#include "../TableGen/LX32GenSubtargetInfo.inc"

namespace llvm {

class Triple;
class LX32TargetMachine;

// Forward declarations for stubs that will eventually live in separate files.
class LX32FrameLowering;
class LX32InstrInfo;
class LX32RegisterInfo;
class LX32TargetLowering;
class SelectionDAGTargetInfo;

class LX32Subtarget : public LX32GenSubtargetInfo {
public:
  LX32Subtarget(const Triple &TT, StringRef CPU, StringRef TuneCPU, StringRef FS,
               const LX32TargetMachine &TM);

  /// TableGen hook: feature parsing entry point.
  ///
  /// The body is generated in `LX32GenSubtargetInfo.inc` and currently does
  /// nothing besides emitting debug output when enabled.
  void ParseSubtargetFeatures(StringRef CPU, StringRef TuneCPU, StringRef FS);

  /*
   * Required TargetSubtargetInfo hooks.
   *
   * In a real backend this would return a target-specific TargetRegisterInfo
   * instance. This skeleton intentionally keeps register info as a stub, so we
   * return nullptr.
   */
  const TargetRegisterInfo *getRegisterInfo() const override { return nullptr; }
};

} // namespace llvm

#endif // LLVM_LIB_TARGET_LX32_CORE_LX32SUBTARGET_H
