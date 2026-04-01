/*
 * LX32TargetMachine.cpp
 * ---------------------
 *
 * Minimal TargetMachine implementation.
 *
 * The goal is only to make the backend compile as a skeleton. The real backend
 * will later provide:
 *  - Data layout
 *  - Subtarget selection and caching
 *  - Pass pipeline configuration
 *  - Instruction selector / lowering setup
 */

#include "LX32TargetMachine.h"

#include "llvm/MC/TargetRegistry.h"

namespace llvm {

LX32TargetMachine::LX32TargetMachine(
	const Target &T, const Triple &TT, StringRef CPU, StringRef FS,
	const TargetOptions &Options, std::optional<Reloc::Model> RM,
	std::optional<CodeModel::Model> CM, CodeGenOptLevel OL)
	: CodeGenTargetMachineImpl(
		  T,
		  /*DataLayoutString=*/"",
		  TT,
		  CPU,
		  FS,
		  Options,
		  RM.value_or(Reloc::Static),
		  CM.value_or(CodeModel::Small),
		  OL) {}

} // namespace llvm



