add_llvm_component_group(LX32)

add_llvm_target(LX32CodeGen
  core/LX32TargetMachine.cpp
  core/LX32Subtarget.cpp

  core/LX32ISelLowering.h
  core/LX32RegisterInfo.h
  core/LX32InstrInfo.h
  core/LX32FrameLowering.h
  core/LX32Subtarget.h

  LINK_COMPONENTS
  MC
  Support
  Target

  ADD_TO_COMPONENT
  LX32
)

add_subdirectory(target)
add_subdirectory(mc)