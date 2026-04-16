#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

C1="$REPO_ROOT/tools/lx32_backend/tests/09_custom_intrinsics.c"
C2="$REPO_ROOT/tools/lx32_backend/tests/baremetal/programs/10_matrix_scan.c"

if [[ ! -f "$C1" || ! -f "$C2" ]]; then
  echo "error: required custom ISA test sources are missing" >&2
  exit 1
fi

require_in_file() {
  local needle="$1"
  local file="$2"
  if ! grep -q "$needle" "$file"; then
    echo "error: expected '$needle' in $file" >&2
    exit 1
  fi
}

echo "== A4 backend custom ISA check =="
echo "Compiling bare-metal custom ISA test programs..."

bash "$SCRIPT_DIR/compile_baremetal_c.sh" "$C1"
bash "$SCRIPT_DIR/compile_baremetal_c.sh" "$C2"

S1="${C1%.*}.s"
S2="${C2%.*}.s"

for asm in "$S1" "$S2"; do
  if [[ ! -f "$asm" ]]; then
    echo "error: expected asm artifact missing: $asm" >&2
    exit 1
  fi
done

# Check that all custom builtins lower to the expected LX32 mnemonics.
require_in_file "lx.sensor" "$S1"
require_in_file "lx.matrix" "$S1"
require_in_file "lx.delta" "$S1"
require_in_file "lx.chord" "$S1"
require_in_file "lx.wait" "$S1"
require_in_file "lx.report" "$S1"

require_in_file "lx.matrix" "$S2"
require_in_file "lx.delta" "$S2"
require_in_file "lx.chord" "$S2"
require_in_file "lx.wait" "$S2"
require_in_file "lx.report" "$S2"

# Check opcode-class mapping at the instruction definition level.
INSTR_TD="$REPO_ROOT/tools/lx32_backend/TableGen/LX32InstrInfo.td"
require_in_file "def LX_SENSOR : LXInstI<0b000, OPC_CUSTOM_0" "$INSTR_TD"
require_in_file "def LX_MATRIX : LXInstI<0b001, OPC_CUSTOM_0" "$INSTR_TD"
require_in_file "def LX_DELTA  : LXInstI<0b010, OPC_CUSTOM_0" "$INSTR_TD"
require_in_file "def LX_CHORD  : LXInstRBase<0b011, OPC_CUSTOM_0" "$INSTR_TD"
require_in_file "def LX_WAIT   : LXInstI<0b000, OPC_CUSTOM_1" "$INSTR_TD"
require_in_file "def LX_REPORT : LXInstI<0b001, OPC_CUSTOM_1" "$INSTR_TD"

echo "PASS: custom builtin lowering emits expected mnemonics and opcode-class mappings."
echo "Artifacts:"
echo "  $S1"
echo "  $S2"

