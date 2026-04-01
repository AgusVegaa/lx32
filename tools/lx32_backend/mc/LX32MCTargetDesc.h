//
//===----------------------------------------------------------------------===//
//
// This file provides LX32 specific target descriptions.
//
//===----------------------------------------------------------------------===//
#ifndef LLVM_LIB_TARGET_LX32_MCTARGETDESC_LX32MCTARGETDESC_H
#define LLVM_LIB_TARGET_LX32_MCTARGETDESC_LX32MCTARGETDESC_H

#include "llvm/MC/MCTargetOptions.h"
#include "llvm/Support/DataTypes.h"
#include <memory>
namespace llvm {

    class MCAsmBackend;
    class MCCodeEmitter;
    class MCContext;
    class MCInstrInfo;
    class MCObjectTargetWriter;
    class MCRegisterInfo;
    class MCRelocationInfo;
    class MCSubtargetInfo;
    class Target;
}

#endif