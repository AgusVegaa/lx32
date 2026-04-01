//
// Created by Axel on 1/4/26.
//

#ifndef LX32_LX32FRAMELOWERING_H
#define LX32_LX32FRAMELOWERING_H

class LX32FrameLowering : public TargetFrameLowering {
    public:
        explicit LX32FrameLowering(const llvm::LX32Subtarget &STI);

    void emitPrologue(MachineFunction&, MachineBasicBlock&) const override {}
    void emitEpilogue(MachineFunction&, MachineBasicBlock&) const override {}

    bool hasBP(const MachineFunction&) const override { return false; }
};


#endif //LX32_LX32FRAMELOWERING_H
