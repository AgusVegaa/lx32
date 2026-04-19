# PULSAR Firmware Development Guide

Writing and running firmware for the LX32K keyboard processor in C.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Memory model](#2-memory-model)
3. [Custom ISA reference](#3-custom-isa-reference)
4. [C firmware](#4-c-firmware)
5. [Simulate and validate](#5-simulate-and-validate)
6. [Benchmark a program](#6-benchmark-a-program)
7. [Common patterns](#7-common-patterns)

---

## 1. Prerequisites

### Toolchain

| Tool | Purpose | How to get |
|------|---------|------------|
| LX32 LLVM fork | Compiler, assembler, linker for bare-metal C | `make setup-backend` |
| `ld.lld` | Linker (included in LX32 LLVM) | — |
| `verilator` | RTL simulation for `run-binary` | `brew install verilator` |

### One-time setup

```sh
# Clone + build the LX32 LLVM fork (~15 min on 8 cores).
make setup-backend

# Build the Verilator bridge and Rust validator.
make librust
```

After this, the LX32 toolchain binaries live under `tools/llvm/build/bin/`.
All Makefile targets reference them automatically via `LX32_LLVM_BIN`.

---

## 2. Memory model

The processor uses a flat von Neumann address space. Code and data share the
same 4 KB RAM in the baremetal target.

```
0x0000_0000  ┌─────────────────────────────┐
             │  _start  (5 instructions)   │  crt0.S
0x0000_0014  ├─────────────────────────────┤
             │  .text  (user code)         │
             │  .rodata / .data / .bss     │
             │  stack (grows down)         │
0x0000_0FFF  └─────────────────────────────┘  ← _stack_top (sp = 0x1000)

0x5000_0000  ┌─────────────────────────────┐
             │  Sensor snapshot buffer     │  lx.matrix returns ptr here
             │  (hardware double-buffer)   │
0x5000_007F  └─────────────────────────────┘  64 × u16 = 128 bytes

0xFFFF_F004  ← MMIO exit register (simulator halt)
```

**Key constraint:** 4 KB total (code + stack). A typical firmware binary sits
under 400 bytes; the stack rarely exceeds 128 bytes for scan loops.

---

## 3. Custom ISA reference

Six instructions extend RISC-V for keyboard-specific hardware. All are
1-cycle latency except `lx.wait`.

### CUSTOM-0 — sensor subsystem

| Instruction | Syntax | Operation |
|------------|--------|-----------|
| `lx.sensor` | `lx.sensor rd, rs1` | `rd = sign_extend16(sensor[rs1])` |
| `lx.matrix` | `lx.matrix rd, rs1` | `rd = ptr_to_snapshot_buffer` (rs1 ignored) |
| `lx.delta`  | `lx.delta rd, rs1`  | `rd = sensor[rs1] − prev_sensor[rs1]` (velocity) |
| `lx.chord`  | `lx.chord rd, rs1`  | `rd = (active_keys & rs1) == rs1 ? 1 : 0` |

All four are **pure reads** — they never stall, never write memory.

### CUSTOM-1 — pipeline control and DMA

| Instruction | Syntax | Operation |
|------------|--------|-----------|
| `lx.wait`   | `lx.wait rs1` | freeze PC for N+1 cycles (see note) |
| `lx.report` | `lx.report rs1` | hand `*rs1` (8-byte HID buffer) to DMA engine |

#### `lx.wait` timing — N+1 semantics

`lx.wait N` stalls the pipeline for **N+1 clock cycles**, not N.

| What you write | Effective stall |
|----------------|----------------|
| `lx.wait(0)` | 1 cycle (unavoidable decode stall) |
| `lx.wait(1)` | 2 cycles |
| `lx.wait(N)` | N+1 cycles |

**Why:** the RTL counter is loaded with N and counts down to 0; the cycle
where the counter expires is still a frozen cycle because the PC is read
before the clock edge that advances it.

**Practical rule for debounce:** to stall for exactly D cycles, pass `N = D - 1`.

```c
// Wait 50 µs at 50 MHz → 2500 cycles.
// Pass 2499 so effective stall = 2499 + 1 = 2500 cycles.
lx_wait(2499);
```

At debounce timescales the 1-cycle error is 20 ns — irrelevant in practice.
For precise timing in tests, use the formula above.

---

## 4. C firmware

### Project layout

```
my_firmware/
├── main.c
└── (link.ld and crt0.S come from the project baremetal kit)
```

### Intrinsics header

Include `tools/lx32_backend/include/lx32k_intrinsics.h` to access all six
instructions through a typed C API:

```c
#include <stdint.h>
#include "lx32k_intrinsics.h"

// Sensor subsystem
int32_t  lx_sensor(uint32_t idx);          // read sensor idx
uint16_t *lx_matrix(uint32_t col);         // ptr to 64-key snapshot (col=0)
int32_t  lx_delta(uint32_t idx);           // frame-to-frame velocity
uint32_t lx_chord(uint32_t bitmask);       // chord detection

// Pipeline and DMA
void     lx_wait(uint32_t cycles);         // pipeline stall (N+1 semantics)
void     lx_report(const void *report);    // kick DMA → USB endpoint
```

Every wrapper is `__attribute__((always_inline))`, so each call site compiles
to exactly **one machine instruction** regardless of optimization level.

### Minimal program skeleton

```c
#include <stdint.h>
#include "lx32k_intrinsics.h"

int main(void) {
    // The scan loop.  crt0 sets up sp and calls main(); never returns.
    for (;;) {
        uint16_t *snap = lx_matrix(0);     // one cycle

        int32_t best_delta = 0;
        uint32_t best_key  = 64;           // sentinel

        for (uint32_t i = 0; i < 64; i++) {
            int32_t d = lx_delta(i);       // one cycle
            if (d > best_delta) { best_delta = d; best_key = i; }
        }

        if (best_key == 64) continue;      // no key pressed

        lx_wait(2499);                     // 2500-cycle debounce (50 µs @ 50 MHz)

        if (lx_delta(best_key) <= 0) continue; // bounced off

        uint8_t report[8] = {
            0x01, 0x00, 0x00,
            0x04 + (best_key % 26),        // HID usage A=0x04 … Z=0x1D
            0x00, 0x00, 0x00, 0x00
        };
        lx_report(report);                 // one cycle, async DMA
    }
    return 0; // unreachable; silences -Wreturn-type
}
```

### Compile a single file

```sh
make compile-c PROG=my_firmware/main.c
```

This produces `main.elf` and `main.bin` next to the source file.

**What happens internally:**
1. `clang --target=lx32 -O1 -ffreestanding -nostdlib` → `main.bc` → `main.o`
2. `llvm-mc -arch=lx32` assembles `crt0.S` → `crt0.o`
3. `ld.lld -T link.ld crt0.o main.o` → `main.elf`
4. `llvm-objcopy -O binary` → `main.bin`

### Optimization levels

| Level | Use when |
|-------|----------|
| `-O0` | Debugging codegen failures; every call maps to an explicit frame |
| `-O1` | Default for firmware — inlines intrinsics, eliminates dead code |
| `-Os` | Size-critical: same as `-O1` but prefers smaller sequences |

Set via `LX32_C_OLEVEL=1 make compile-c PROG=...`.

---

## 5. Simulate and validate

C firmware produces a flat `.bin` file that can be loaded into the RTL
simulator directly.

### Run a binary

```sh
make run-binary BIN=path/to/my_firmware.bin
```

Or the runner directly (more options):

```sh
tools/lx32_validator/target/release/run_program \
  --binary path/to/my_firmware.bin
```

The simulator:
1. Loads the binary at address `0x0000_0000` in 64 KB of flat RAM.
2. Resets the LX32 core (5 clock cycles with `rst=1`).
3. Runs until it detects a store to `0xFFFF_F004` (the MMIO exit port written
   by `crt0.S` after `main` returns) or hits `--max-cycles`.

### Verbose trace (cycle-by-cycle)

```sh
tools/lx32_validator/target/release/run_program \
  --binary my_firmware.bin --verbose 2>/dev/null
```

Output per cycle:
```
Cycle 00037: PC=0x00000094  instr=0x00F007AB
Cycle 00038: PC=0x00000094  instr=0x00F007AB [STALL]
Cycle 00039: PC=0x00000098  instr=0x00072783
```

`[STALL]` marks cycles where the PC did not advance (always `lx.wait`).

### JSON output (machine-readable)

```sh
tools/lx32_validator/target/release/run_program \
  --binary my_firmware.bin --json
```

Outputs a single JSON object with all metrics:

```json
{
  "program": "my_firmware",
  "binary_bytes": 276,
  "static_instructions": 69,
  "status": "exited_mmio",
  "exit_code": 0,
  "cycles_total": 64,
  "instructions_committed": 53,
  "stall_cycles": 11,
  "ipc": 0.828,
  "instruction_mix": {
    "alu": 19, "load": 11, "store": 11,
    "custom": 6, "jump": 4, "upper_imm": 2,
    "branch": 0, "other": 0
  }
}
```

### Differential validation (RTL vs golden model)

```sh
make validate          # run the full test suite
make validate-verbose  # with per-test detail
make validate-long     # extended programs (fibonacci, matrix scan)
```

This runs the Rust golden model and the Verilator RTL in lockstep, comparing
PC and register state after every instruction.

---

## 6. Benchmark a program

The benchmark pipeline compiles every C program in
`tools/lx32_backend/tests/baremetal/programs/`, runs each on the simulator,
and collects results in `bench_results.json`.

```sh
make bench-all          # compile + run + collect
make bench-summary      # print the human-readable table
```

To add your own program to the benchmark:

1. Drop `my_test.c` into `tools/lx32_backend/tests/baremetal/programs/`.
2. Run `make bench-all` — it picks up every `*.c` in that directory.

The summary table looks like:

```
Program                    Status         Bytes  S.Instr  Cycles  D.Instr  Stalls     IPC  Exit
─────────────────────────────────────────────────────────────────────────────────────────────────
01_return42                exited_mmio       28        7       5        5       0  1.0000    42
11_run_custom_intrinsics   exited_mmio      276       69      64       53      11  0.8281     0
```

**Reading the columns:**

| Column | Meaning |
|--------|---------|
| S.Instr | Static instruction count (`binary_bytes / 4`) |
| D.Instr | Dynamic instructions committed (PC advanced) |
| Stalls | Cycles where PC was frozen (`lx.wait`) |
| IPC | `D.Instr / Cycles` — target is 1.0 for stall-free code |
| Exit | Value written to `0xFFFF_F004` by `main`'s return code |

IPC < 1.0 means the program contains `lx.wait` calls. Everything else should
run at exactly IPC = 1.0 on this single-cycle processor.

---

## 7. Common patterns

### Debounce window

```c
// 50 µs at 50 MHz
lx_wait(2499);  // effective = 2500 cycles
```

### Read and act on a single key

```c
int32_t v = lx_delta(key_index);
if (v > THRESHOLD) { /* pressed */ }
```

### Read the full snapshot at once

```c
// one instruction, pointer into hardware double-buffer
uint16_t *snap = lx_matrix(0);
uint16_t raw = snap[42];         // key 42
```

### Chord detection

```c
// keys 0, 2, 5 all pressed simultaneously?
if (lx_chord(0b00100101)) { /* chord active */ }
```

### Send a HID keyboard report

```c
// one cycle, DMA handles the USB transfer in the background
uint8_t report[8] = {0x01, 0x00, 0x00, hid_usage, 0x00, 0x00, 0x00, 0x00};
lx_report(report);
```

`lx.report` returns in 1 cycle if the DMA engine is idle.
If a previous transfer is still in flight the pipeline stalls until the
engine is ready — no explicit polling required.

### Timing-critical section

```c
// Exact 100-cycle critical section.
// Pass 99 so the effective stall is 99+1 = 100 cycles.
lx_wait(99);
```

---

## Quick-reference card

```
COMPILE C         make compile-c PROG=path/to/main.c
RUN BINARY        make run-binary BIN=path/to/main.bin
BENCHMARK         make bench-all && make bench-summary
VALIDATE RTL      make validate
CYCLE TRACE       run_program --binary bin --verbose
JSON METRICS      run_program --binary bin --json
```
