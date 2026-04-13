#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <input.c> [output_prefix]" >&2
  exit 1
fi

INPUT_C="$1"
if [[ ! -f "$INPUT_C" ]]; then
  echo "error: input C file not found: $INPUT_C" >&2
  exit 1
fi

OUT_PREFIX="${2:-${INPUT_C%.*}}"
OUT_LL="${OUT_PREFIX}.ll"
OUT_S="${OUT_PREFIX}.s"
OUT_O="${OUT_PREFIX}.o"

# Backend bring-up defaults to O0 to avoid introducing unsupported ops
# (e.g. MUL/div libcalls) via frontend optimizations.
LX32_C_OLEVEL="${LX32_C_OLEVEL:-0}"
LX32_BACKEND_DEBUG="${LX32_BACKEND_DEBUG:-0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

pick_llvm_bin() {
  local name="$1"
  local override_var="$2"
  local explicit="${!override_var:-}"

  if [[ -n "$explicit" && -x "$explicit" ]]; then
    echo "$explicit"
    return
  fi

  if [[ -n "${LX32_LLVM_BIN:-}" && -x "${LX32_LLVM_BIN}/$name" ]]; then
    echo "${LX32_LLVM_BIN}/$name"
    return
  fi

  if [[ -n "${LLVM_DIR:-}" && -x "${LLVM_DIR}/build/bin/$name" ]]; then
    echo "${LLVM_DIR}/build/bin/$name"
    return
  fi

  if [[ -x "$REPO_ROOT/.llvm/build/bin/$name" ]]; then
    echo "$REPO_ROOT/.llvm/build/bin/$name"
    return
  fi

  if [[ -x "/usr/local/bin/$name" ]]; then
    echo "/usr/local/bin/$name"
    return
  fi

  command -v "$name"
}

sed_in_place() {
  local file="$1"
  shift
  # macOS/BSD sed requires a backup suffix argument for -i.
  if [[ "$(uname -s)" == "Darwin" ]]; then
    sed -E -i '' "$@" "$file"
  else
    sed -E -i "$@" "$file"
  fi
}

CLANG="$(pick_llvm_bin clang LX32_CLANG || true)"
LLC="$(pick_llvm_bin llc LX32_LLC || true)"

if [[ -z "$CLANG" || ! -x "$CLANG" ]]; then
  echo "error: clang not found" >&2
  echo "hint : set LX32_LLVM_BIN or LX32_CLANG to your LLVM bin directory" >&2
  exit 1
fi
if [[ -z "$LLC" || ! -x "$LLC" ]]; then
  echo "error: llc not found" >&2
  echo "hint : set LX32_LLVM_BIN or LX32_LLC to your LLVM bin directory" >&2
  exit 1
fi

if ! "$LLC" --version 2>/dev/null | grep -qi "lx32"; then
  echo "error: selected llc does not report an lx32 target: $LLC" >&2
  echo "hint : point LX32_LLVM_BIN to the LLVM build that includes the LX32 backend" >&2
  exit 1
fi

COMMON_CFLAGS=(
  -ffreestanding
  -fno-builtin
  -nostdlib
  -fno-stack-protector
  "-O${LX32_C_OLEVEL}"
  -S
  -emit-llvm
)

LLC_COMMON=(
  -march=lx32
  -mcpu=generic
  -mtriple=lx32-unknown-elf
  -O0
)

if [[ "$LX32_BACKEND_DEBUG" == "1" ]]; then
  echo "debug: clang=$CLANG"
  echo "debug: llc=$LLC"
  echo "debug: C opt level -O${LX32_C_OLEVEL}"
  echo "debug: outputs ll=$OUT_LL s=$OUT_S o=$OUT_O"
  LLC_COMMON+=( -verify-machineinstrs )
fi

run_llc_or_die() {
  local filetype="$1"
  local out_file="$2"
  local in_file="$3"

  if ! "$LLC" "${LLC_COMMON[@]}" -filetype="$filetype" -o "$out_file" "$in_file"; then
    echo "error: llc failed for -filetype=$filetype" >&2
    echo "  input : $in_file" >&2
    echo "  output: $out_file" >&2
    echo "  repro : $LLC ${LLC_COMMON[*]} -filetype=$filetype -o $out_file $in_file" >&2
    if [[ "$LX32_BACKEND_DEBUG" != "1" ]]; then
      echo "hint : re-run with LX32_BACKEND_DEBUG=1 for extra backend checks" >&2
    fi
    exit 1
  fi
}

# Prefer direct lx32 target; if clang frontend does not know lx32 yet,
# fallback to generic 32-bit just to produce freestanding IR for llc.
if "$CLANG" "${COMMON_CFLAGS[@]}" -target lx32-unknown-elf "$INPUT_C" -o "$OUT_LL" 2>/dev/null; then
  C_TARGET="lx32-unknown-elf"
else
  "$CLANG" "${COMMON_CFLAGS[@]}" -target i386-unknown-elf "$INPUT_C" -o "$OUT_LL" 2>/dev/null
  C_TARGET="generic 32-bit (fallback IR target)"

  # Normalise target attributes so llc -march=lx32 does not inherit an incorrect CPU.
  sed_in_place "$OUT_LL" \
    -e 's/"target-cpu"="[^"]*"/"target-cpu"="generic"/g' \
    -e 's/"target-features"="[^"]*"/"target-features"=""/g'
fi

run_llc_or_die asm "$OUT_S" "$OUT_LL"

# Object emission is optional at this stage; asm generation is the hard requirement.
if "$LLC" "${LLC_COMMON[@]}" -filetype=obj -o "$OUT_O" "$OUT_LL"; then
  OBJ_STATUS="ok"
else
  OBJ_STATUS="not available in this backend slice"
  rm -f "$OUT_O"
fi

if grep -Eq "__[a-z0-9_]+(si3|di3)|memcpy|memset|memmove" "$OUT_LL" "$OUT_S"; then
  echo "warning: libcall/runtime symbol detected in generated output" >&2
fi

echo "ok: compiled bare-metal C"
echo "  input : $INPUT_C"
echo "  c_target_for_ir : $C_TARGET"
echo "  ir    : $OUT_LL"
echo "  asm   : $OUT_S"
echo "  obj   : $OUT_O ($OBJ_STATUS)"


