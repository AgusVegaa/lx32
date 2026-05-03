#!/usr/bin/env bash
# run_rust_firmware.sh — Build and run Rust bare-metal firmware tests on the LX32 RTL.
#
# Usage:
#   bash run_rust_firmware.sh [deep]
#
# Environment variables (set by the Makefile; can be overridden manually):
#   RUST_LX32_RUSTC   — path to the custom stage1 rustc (required)
#   LX32_LLVM_BIN     — directory containing llvm-mc and llvm-objcopy
#   BENCH_RUNNER      — path to the run_program RTL simulation binary
#   RUST_PROGS_DIR    — path to the rust_programs cargo workspace (auto-detected)
#
# Exit codes:
#   0 — all tests passed
#   1 — one or more tests failed or the toolchain is missing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUST_PROGS_DIR="${RUST_PROGS_DIR:-$SCRIPT_DIR/rust_programs}"
PROGRAMS_OUT="$RUST_PROGS_DIR/target/lx32-unknown-none-elf/release"

# ── Toolchain detection ────────────────────────────────────────────────────────

if [ -z "${RUST_LX32_RUSTC:-}" ]; then
    # Try to find the custom rustc relative to this script's repo root.
    REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../" && pwd)"
    RUST_HOST="$(rustc -vV 2>/dev/null | sed -n 's/^host: //p')"
    CANDIDATE="$REPO_ROOT/.rust/rust-lx32/build/$RUST_HOST/stage1/bin/rustc"
    if [ -f "$CANDIDATE" ]; then
        RUST_LX32_RUSTC="$CANDIDATE"
    else
        echo "ERROR: RUST_LX32_RUSTC not set and custom rustc not found at:"
        echo "       $CANDIDATE"
        echo "  Run: make setup-rust"
        exit 1
    fi
fi

if [ ! -f "$RUST_LX32_RUSTC" ]; then
    echo "ERROR: custom rustc not found: $RUST_LX32_RUSTC"
    echo "  Run: make setup-rust"
    exit 1
fi

# LLVM tools (llvm-mc, llvm-objcopy)
if [ -z "${LX32_LLVM_BIN:-}" ]; then
    REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../" && pwd)"
    CANDIDATE="$REPO_ROOT/.llvm/build/bin"
    if [ -d "$CANDIDATE" ]; then
        LX32_LLVM_BIN="$CANDIDATE"
    elif command -v llvm-mc &>/dev/null; then
        LX32_LLVM_BIN="$(dirname "$(command -v llvm-mc)")"
    else
        echo "ERROR: LX32_LLVM_BIN not set and llvm-mc not found in PATH"
        echo "  Run: make setup-backend"
        exit 1
    fi
fi

LLVM_MC="$LX32_LLVM_BIN/llvm-mc"
LLVM_OBJCOPY="$LX32_LLVM_BIN/llvm-objcopy"

# RTL runner (run_program)
if [ -z "${BENCH_RUNNER:-}" ]; then
    REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../" && pwd)"
    BENCH_RUNNER="$REPO_ROOT/tools/lx32_validator/target/release/run_program"
fi

HAS_RUNNER=1
if [ ! -x "$BENCH_RUNNER" ]; then
    echo "  (run_program not built — compile-only mode, no simulation)"
    HAS_RUNNER=0
fi

# ── Assemble crt0.o ───────────────────────────────────────────────────────────

CRT0_S="$SCRIPT_DIR/crt0.S"
CRT0_O="$SCRIPT_DIR/crt0.o"

if [ ! -f "$CRT0_O" ] || [ "$CRT0_S" -nt "$CRT0_O" ]; then
    echo "→ Assembling crt0.S..."
    "$LLVM_MC" -arch=lx32 -filetype=obj "$CRT0_S" -o "$CRT0_O"
    echo "  ✓ crt0.o ready"
fi

# ── Build Rust firmware tests ─────────────────────────────────────────────────

echo ""
echo "→ Building Rust firmware tests (target: lx32-unknown-none-elf)..."
echo "  rustc: $RUST_LX32_RUSTC"
echo ""

cd "$RUST_PROGS_DIR"
RUSTC="$RUST_LX32_RUSTC" cargo build --release 2>&1
echo ""

# ── Expected results ──────────────────────────────────────────────────────────
# Each entry: "binary_name expected_exit_code description"
declare -a TESTS=(
    "01_return42          42   Minimal constant return"
    "02_pointer_store     30   Stack array LOAD/STORE"
    "03_call_chain         8   Multi-level function calls"
    "04_branch_loop       45   While-loop accumulator (0..9)"
    "05_compare_assign    10   Conditional subtraction"
    "06_pointer_walk      15   Iterator over stack array"
    "07_fibonacci_iter    55   Iterative fib(10)"
    "08_fibonacci_recursive 55 Recursive fib(10)"
    "09_custom_intrinsics  0   LX32K custom instructions"
)

# ── Run or just convert ───────────────────────────────────────────────────────

PASS=0
FAIL=0
SKIP=0

for entry in "${TESTS[@]}"; do
    bin=$(echo "$entry"  | awk '{print $1}')
    expected=$(echo "$entry" | awk '{print $2}')
    desc=$(echo "$entry" | awk '{$1=$2=""; sub(/^  */, ""); print}')

    elf="$PROGRAMS_OUT/$bin"
    bin_file="$PROGRAMS_OUT/${bin}.bin"

    if [ ! -f "$elf" ]; then
        printf "  %-36s  MISSING ELF\n" "$bin"
        FAIL=$((FAIL+1))
        continue
    fi

    # Convert ELF to flat binary.
    "$LLVM_OBJCOPY" -O binary "$elf" "$bin_file"

    if [ "$HAS_RUNNER" -eq 0 ]; then
        printf "  %-36s  COMPILED  (%s)\n" "$bin" "$desc"
        SKIP=$((SKIP+1))
        continue
    fi

    # Run on RTL simulation and check exit code.
    actual_code=0
    "$BENCH_RUNNER" --binary "$bin_file" --json > /tmp/lx32_rust_result.json 2>/dev/null || true
    actual_code=$(python3 -c "
import json, sys
try:
    with open('/tmp/lx32_rust_result.json') as f:
        data = json.load(f)
    print(data.get('exit_code', -1))
except Exception:
    print(-1)
" 2>/dev/null || echo -1)

    if [ "$actual_code" -eq "$expected" ]; then
        printf "  %-36s  PASS  (exit=%d  %s)\n" "$bin" "$actual_code" "$desc"
        PASS=$((PASS+1))
    else
        printf "  %-36s  FAIL  (expected=%d actual=%d  %s)\n" \
               "$bin" "$expected" "$actual_code" "$desc"
        FAIL=$((FAIL+1))
    fi
done

echo ""
echo "──────────────────────────────────────────────────────────────────────────"
if [ "$HAS_RUNNER" -eq 0 ]; then
    echo "  Compiled: $((PASS+SKIP)) programs  (simulation skipped — run_program not built)"
    echo "  Run 'make bench-build-runner' then rerun to enable RTL simulation."
else
    echo "  Results: $PASS passed, $FAIL failed"
fi
echo "──────────────────────────────────────────────────────────────────────────"
echo ""

[ "$FAIL" -eq 0 ]
