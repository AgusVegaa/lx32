add_llvm_component_group(LX32)

set(LLVM_TARGET_DEFINITIONS TableGen/LX32.td)

include_directories(${CMAKE_CURRENT_SOURCE_DIR}/TableGen)
tablegen(LLVM LX32GenInstrInfo.inc -gen-instr-info)
tablegen(LLVM LX32GenRegisterInfo.inc -gen-register-info)
tablegen(LLVM LX32GenMCCodeEmitter.inc -gen-emitter)
tablegen(LLVM LX32GenAsmMatcher.inc -gen-asm-matcher)
tablegen(LLVM LX32GenSubtargetInfo.inc -gen-subtarget)
tablegen(LLVM LX32GenCallingConv.inc -gen-callingconv)

add_public_tablegen_target(LX32CommonTableGen)

add_subdirectory(TargetInfo)
add_subdirectory(MCTargetDesc)
add_subdirectory(AsmParser)
add_subdirectory(core)
