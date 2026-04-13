#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SMOKE_DIR="$ROOT/smoke"
LX32_CPU="${LX32_CPU:-generic}"

pick_llc() {
  if [[ $# -gt 0 && -n "${1:-}" ]]; then
    echo "$1"
    return
  fi
  if [[ -x "/usr/local/bin/llc" ]]; then
    echo "/usr/local/bin/llc"
    return
  fi
  command -v llc
}

LLC="$(pick_llc "${1:-}")"
if [[ ! -x "$LLC" ]]; then
  echo "error: llc not found or not executable: $LLC" >&2
  exit 1
fi

if ! "$LLC" --version 2>/dev/null | grep -qi "lx32"; then
  echo "error: selected llc does not report an lx32 target: $LLC" >&2
  echo "hint: pass an llc built from the same backend checkout as this workspace" >&2
  exit 1
fi

run_one() {
  local ll="$1"
  local name
  name="$(basename "$ll")"

  local out
  if ! out="$($LLC -march=lx32 -mcpu="$LX32_CPU" -mtriple=lx32-unknown-elf -filetype=asm -o - "$ll" 2>&1)"; then
    echo "FAIL $name"
    echo "$out"
    return 1
  fi

  if [[ "$out" != *"ret"* && "$out" != *"JALR"* ]]; then
    echo "FAIL $name: expected asm to contain a return sequence"
    echo "$out"
    return 1
  fi

  if [[ "$name" == "add.ll" && "$out" != *"ADD"* ]]; then
    echo "FAIL $name: expected asm to contain ADD"
    echo "$out"
    return 1
  fi

  if [[ "$name" == "call.ll" ]]; then
    if [[ "$out" != *"AUIPC"* && "$out" != *"call"* && "$out" != *"JALR"* ]]; then
      echo "FAIL $name: expected call-address materialization/call sequence"
      echo "$out"
      return 1
    fi
  fi

  if [[ "$name" == "branch.ll" ]]; then
    if [[ "$out" != *"BEQ"* && "$out" != *"BNE"* && "$out" != *"BLT"* &&
          "$out" != *"BGE"* && "$out" != *"BLTU"* && "$out" != *"BGEU"* ]]; then
      echo "FAIL $name: expected asm to contain a conditional branch"
      echo "$out"
      return 1
    fi
  fi

  echo "PASS $name"
}

run_one "$SMOKE_DIR/ret0.ll"
run_one "$SMOKE_DIR/add.ll"
run_one "$SMOKE_DIR/bigconst.ll"
run_one "$SMOKE_DIR/call.ll"
run_one "$SMOKE_DIR/branch.ll"

echo "smoke tests passed"
