//
// Created by Axel on 1/4/26.
//

#ifndef LX32_LX32ISELLOWERING_H
#define LX32_LX32ISELLOWERING_H
class LX32TargetLowering : public TargetLowering {
public:
    LX32TargetLowering(const TargetMachine&, const LX32Subtarget&);
};
#endif //LX32_LX32ISELLOWERING_H
