add_llvm_component_library(LLVMLX32Disassembler
  LX32Disassembler.cpp

  LINK_COMPONENTS
  MCDisassembler
  LX32Info
  LX32Desc
  Support

  ADD_TO_COMPONENT
  LX32
)
add_dependencies(LLVMLX32Disassembler LX32CommonTableGen)
