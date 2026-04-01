//
// Created by Axel on 1/4/26.
//

#ifndef LX32_LX32REGISTERINFO_H
#define LX32_LX32REGISTERINFO_H

class LX32RegisterInfo : public LX32GenRegisterInfo {
public:
    LX32RegisterInfo(unsigned HwMode);
    const MCPhysReg *getCalleeSavedRegs(const MachineFunction*) const override;
    BitVector getReservedRegs(const MachineFunction&) const override;
    bool eliminateFrameIndex(MachineBasicBlock::iterator, int,
                             unsigned, RegScavenger*) const override;
    Register getFrameRegister(const MachineFunction&) const override;
};

#endif //LX32_LX32REGISTERINFO_H
