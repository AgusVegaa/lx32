# A3 Custom ISA Verification Coverage

## Scope

This document tracks verification coverage for the first custom ISA block in RTL and the Rust golden model:

- `LX.SENSOR`
- `LX.MATRIX`
- `LX.DELTA`
- `LX.CHORD`
- `LX.WAIT`
- `LX.REPORT`

## RTL Testbenches

The following directed testbenches run against `rtl/core/lx32_system.sv`:

- `tb/core/lx32_sensor_tb.sv`
  - Covers `LX.SENSOR`, `LX.MATRIX`, `LX.DELTA` datapath results.
  - Verifies decoded `custom_0` path and write-back values.
- `tb/core/lx32_chord_tb.sv`
  - Covers `LX.CHORD` bitmask match/no-match behavior.
- `tb/core/lx32_wait_tb.sv`
  - Covers `LX.WAIT` issue hold and bounded resume behavior.
- `tb/core/lx32_report_tb.sv`
  - Covers `LX.REPORT` request pointer and DMA ack pulse.

## Golden Model Coverage

Rust test:

- `tools/lx32_validator/tests/test_custom_ops.rs`
  - Cross-checks RTL vs golden behavior for:
    - `SENSOR/DELTA/CHORD`
    - `WAIT` stall and release
    - `REPORT` non-write behavior and PC alignment

## Reproducible Run Commands

```bash
cd /Users/axel/Pulsar
make sim TB=lx32_sensor_tb
make sim TB=lx32_chord_tb
make sim TB=lx32_wait_tb
make sim TB=lx32_report_tb
```

```bash
cd /Users/axel/Pulsar
rm -rf .sim/lx32_lib
mkdir -p .sim/lx32_lib
verilator -Wall -Wno-fatal --cc --Mdir .sim/lx32_lib rtl/arch/*.sv rtl/core/*.sv --top-module lx32_system
cargo test --manifest-path tools/lx32_validator/Cargo.toml --test test_custom_ops -- --nocapture
```

## Current Limits

- `sensor_controller.sv` and `dma_controller.sv` are still stubs (A2 level), so timing/backpressure behavior is simplified.
- `LX.REPORT` busy-stall semantics are not stress-tested yet because DMA busy is hardwired in the stub.
- Full 10M-instruction divergence campaign remains pending for A3 completion gate.

