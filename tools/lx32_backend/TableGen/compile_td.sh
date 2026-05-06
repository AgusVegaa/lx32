#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Allow overrides from environment, but pick a sane default automatically.
DEFAULT_TBLGEN="$HOME/llvm-project/build-lx32/bin/llvm-tblgen"
if [[ ! -x "$DEFAULT_TBLGEN" ]]; then
  DEFAULT_TBLGEN="$HOME/llvm-project/build/bin/llvm-tblgen"
fi

TBLGEN="${LLVM_TBLGEN:-$DEFAULT_TBLGEN}"
INCLUDE="${LLVM_INCLUDE_DIR:-$HOME/llvm-project/llvm/include}"

if [[ ! -x "$TBLGEN" ]]; then
  echo "error: llvm-tblgen not found or not executable: $TBLGEN" >&2
  echo "hint: build it with: ninja -C $HOME/llvm-project/build-lx32 llvm-tblgen" >&2
  exit 1
fi

if [[ ! -f "$INCLUDE/llvm/IR/Module.h" ]]; then
  echo "error: invalid LLVM include directory: $INCLUDE" >&2
  exit 1
fi

"$TBLGEN" -gen-dag-isel LX32.td -I "$INCLUDE" -I . -o LX32GenDAGISel.inc
"$TBLGEN" -gen-callingconv LX32.td -I "$INCLUDE" -I . -o LX32GenCallingConv.inc
"$TBLGEN" -gen-register-info LX32.td -I "$INCLUDE" -I . -o LX32GenRegisterInfo.inc
"$TBLGEN" -gen-instr-info LX32.td -I "$INCLUDE" -I . -o LX32GenInstrInfo.inc
"$TBLGEN" --gen-subtarget LX32.td -I "$INCLUDE" -I . -o LX32GenSubtargetInfo.inc
"$TBLGEN" -gen-emitter LX32.td -I "$INCLUDE" -I . -o LX32GenMCCodeEmitter.inc
"$TBLGEN" -gen-asm-matcher LX32.td -I "$INCLUDE" -I . -o LX32GenAsmMatcher.inc
"$TBLGEN" -gen-asm-writer LX32.td -I "$INCLUDE" -I . -o LX32GenAsmWriter.inc
"$TBLGEN" -gen-disassembler LX32.td -I "$INCLUDE" -I . -o LX32GenDisassemblerTables.inc

echo "TableGen: all .inc files generated successfully."
