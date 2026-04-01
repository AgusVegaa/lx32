/*
 * LX32TargetMachine.h
 * -------------------
 *
 * Minimal TargetMachine stub.
 *
 * LLVM uses TargetMachine/LLVMTargetMachine as the top-level object that ties
 * together the subtarget, instruction info, lowering, data layout, etc.
 *
 * This backend is currently a skeleton, so we provide a tiny class that is
 * sufficient for other stubs (like LX32Subtarget) to compile.
 */

#ifndef LLVM_LIB_TARGET_LX32_CORE_LX32TARGETMACHINE_H
#define LLVM_LIB_TARGET_LX32_CORE_LX32TARGETMACHINE_H

#include "llvm/CodeGen/CodeGenTargetMachineImpl.h"
#include "llvm/Target/TargetMachine.h"

namespace llvm {

class LX32TargetMachine final : public CodeGenTargetMachineImpl {
public:
  LX32TargetMachine(const Target &T, const Triple &TT, StringRef CPU,
					StringRef FS, const TargetOptions &Options,
					std::optional<Reloc::Model> RM,
					std::optional<CodeModel::Model> CM, CodeGenOptLevel OL);
};

} // namespace llvm

#endif // LLVM_LIB_TARGET_LX32_CORE_LX32TARGETMACHINE_H
