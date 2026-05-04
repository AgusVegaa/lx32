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

# Stage0 cargo (supports -Z unstable flags, derived from custom rustc path)
if [ -z "${RUST_LX32_STAGE0_CARGO:-}" ]; then
    # RUST_LX32_RUSTC = .../build/<host>/stage1/bin/rustc
    STAGE1_BIN="$(dirname "$RUST_LX32_RUSTC")"
    HOST_BUILD_DIR="$(dirname "$(dirname "$STAGE1_BIN")")"
    RUST_LX32_STAGE0_CARGO="$HOST_BUILD_DIR/stage0/bin/cargo"
fi
if [ ! -x "$RUST_LX32_STAGE0_CARGO" ]; then
    echo "ERROR: stage0 cargo not found: $RUST_LX32_STAGE0_CARGO"
    echo "  Run: make build-rust-compiler"
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
RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C jump-tables=no" \
RUSTC="$RUST_LX32_RUSTC" RUSTC_BOOTSTRAP=1 \
    "$RUST_LX32_STAGE0_CARGO" build --release \
    -Z build-std=core,compiler_builtins \
    -Z build-std-features=compiler-builtins-mem 2>&1
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
    "09_custom_intrinsics  0   LX32K custom instructions (inline asm)"
    "10_mul_softcall      42   Integer multiply via __mulsi3"
    "11_global_array      50   Global static array via PseudoLA"
    "12_bitops_shift      12   Shift + AND + OR patterns"
    "13_nested_loop       10   Nested while loops"
    "14_classify_fn        3   Multi-branch if/else chain"
    "15_multi_args        31   Five-argument register passing"
    "16_indirect_call     31   Conditional branch selecting call target"
    "17_volatile_mmio     42   Volatile memory load/store ordering"
    "18_sign_extend       27   i8 sign extension and mixed-width arithmetic"
    "19_reg_pressure     102   High register pressure arithmetic mix"
    "20_shift_mix         34   Combined left/right shifts with masking"
    "21_div_mod_softcall  12   Unsigned div/mod compiler_builtins libcalls"
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

    # Binary size in bytes (flat binary = exact instruction + data bytes).
    bin_size=$(wc -c < "$bin_file" 2>/dev/null || echo "?")

    if [ "$HAS_RUNNER" -eq 0 ]; then
        printf "  %-36s  COMPILED  %4d B  (%s)\n" "$bin" "$bin_size" "$desc"
        SKIP=$((SKIP+1))
        continue
    fi

    # Run on RTL simulation and check exit code + key register invariants.
    actual_code=-1
    x0_val=-1
    x10_val=-1
    "$BENCH_RUNNER" --binary "$bin_file" --json > /tmp/lx32_rust_result.json 2>/dev/null || true
    read -r actual_code x0_val x10_val <<EOF
$(python3 -c "
import json, sys
try:
    with open('/tmp/lx32_rust_result.json') as f:
        data = json.load(f)
    code = data.get('exit_code', -1)
    regs = data.get('registers', [])
    x0 = int(regs[0]) if isinstance(regs, list) and len(regs) > 0 else -1
    x10 = int(regs[10]) if isinstance(regs, list) and len(regs) > 10 else -1
    code_i = int(code) if code is not None else -1
    print(f\"{code_i} {x0} {x10}\")
except Exception:
    print(\"-1 -1 -1\")
" 2>/dev/null || echo "-1 -1 -1")
EOF

    if [ "$actual_code" -eq "$expected" ] && [ "$x0_val" -eq 0 ] && [ "$x10_val" -eq "$expected" ]; then
        printf "  %-36s  PASS  %4d B  (exit=%d x0=%d x10=%d  %s)\n" \
               "$bin" "$bin_size" "$actual_code" "$x0_val" "$x10_val" "$desc"
        PASS=$((PASS+1))
    else
        printf "  %-36s  FAIL  %4d B  (expected_exit=%d actual_exit=%d x0=%d expected_x0=0 x10=%d expected_x10=%d  %s)\n" \
               "$bin" "$bin_size" "$expected" "$actual_code" "$x0_val" "$x10_val" "$expected" "$desc"
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
