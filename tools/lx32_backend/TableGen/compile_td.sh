#!/bin/bash
TBLGEN=~/llvm-project/build/bin/llvm-tblgen
INCLUDE=~/llvm-project/llvm/include

$TBLGEN -gen-dag-isel LX32.td -I $INCLUDE -I . -o LX32GenDAGISel.inc
$TBLGEN -gen-callingconv LX32.td -I $INCLUDE -I . -o LX32GenCallingConv.inc
$TBLGEN -gen-register-info LX32.td -I $INCLUDE -I . -o LX32GenRegisterInfo.inc
$TBLGEN -gen-instr-info LX32.td -I $INCLUDE -I . -o LX32GenInstrInfo.inc
$TBLGEN --gen-subtarget LX32.td -I $INCLUDE -I . -o LX32GenSubtargetInfo.inc

echo "✅ TableGen: All .inc files were generated."
