#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PROGRAM_DIR="$ROOT/programs"
COMPILE_SH="$ROOT/../compile_baremetal_c.sh"
MODE="${1:-smoke}"

if [[ "$MODE" != "smoke" && "$MODE" != "deep" ]]; then
  echo "usage: $0 [smoke|deep]" >&2
  exit 2
fi

if [[ ! -x "$COMPILE_SH" ]]; then
  chmod +x "$COMPILE_SH"
fi

if [[ ! -d "$PROGRAM_DIR" ]]; then
  echo "error: program directory not found: $PROGRAM_DIR" >&2
  exit 1
fi

if [[ ! -f "$COMPILE_SH" ]]; then
  echo "error: compile helper not found: $COMPILE_SH" >&2
  exit 1
fi

check_one() {
  local c_file="$1"
  local stem
  stem="$(basename "$c_file" .c)"
  local out_prefix="/tmp/lx32_${stem}"

  echo "==> $stem"
  "$COMPILE_SH" "$c_file" "$out_prefix"

  local asm_file="${out_prefix}.s"
  local ll_file="${out_prefix}.ll"

  if grep -Eq "__[a-z0-9_]+(si3|di3)|memcpy|memset|memmove" "$asm_file" "$ll_file"; then
    echo "FAIL $stem: runtime/libcall dependency detected" >&2
    return 1
  fi

  if ! grep -Eiq "ret|jalr" "$asm_file"; then
    echo "FAIL $stem: missing return instruction in asm" >&2
    return 1
  fi

  if [[ "$stem" == "03_call_chain" || "$stem" == "08_fibonacci_recursive" ]] && ! grep -Eiq "call|jalr|jal" "$asm_file"; then
    echo "FAIL $stem: missing call-like instruction sequence in asm" >&2
    return 1
  fi

  if [[ "$stem" == "04_branch_loop" || "$stem" == "05_compare_assign" ||
        "$stem" == "06_pointer_walk" || "$stem" == "07_fibonacci_iter" ||
        "$stem" == "08_fibonacci_recursive" ]] && ! grep -Eiq "beq|bne|blt|bge|jal" "$asm_file"; then
    echo "FAIL $stem: missing branch/loop-like instruction sequence in asm" >&2
    return 1
  fi

  if [[ "$stem" == "02_pointer_store" || "$stem" == "06_pointer_walk" ]] && ! grep -Eiq "lw|sw" "$asm_file"; then
    echo "FAIL $stem: missing pointer load/store sequence in asm" >&2
    return 1
  fi

  echo "PASS $stem"
}


check_one "$PROGRAM_DIR/01_return42.c"
check_one "$PROGRAM_DIR/02_pointer_store.c"
check_one "$PROGRAM_DIR/03_call_chain.c"
check_one "$PROGRAM_DIR/04_branch_loop.c"

if [[ "$MODE" == "deep" ]]; then
  echo "==> deep mode: extended control-flow and algorithm coverage"
  check_one "$PROGRAM_DIR/05_compare_assign.c"
  check_one "$PROGRAM_DIR/06_pointer_walk.c"
  check_one "$PROGRAM_DIR/07_fibonacci_iter.c"
  check_one "$PROGRAM_DIR/08_fibonacci_recursive.c"
fi

echo "bare-metal C $MODE tests passed"
