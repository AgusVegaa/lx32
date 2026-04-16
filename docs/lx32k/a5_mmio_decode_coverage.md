# A5 MMIO Decode Coverage

## Scope

This check validates MMIO range decoding and external memory gating in `rtl/core/lx32_system.sv` using constants from `rtl/arch/lx32_mmio_pkg.sv`.

## Testbench

- `tb/core/lx32_mmio_decode_tb.sv`
  - Verifies sensor MMIO range detection.
  - Verifies DMA MMIO range detection.
  - Verifies MMIO stores do not drive external `mem_we`.
  - Verifies non-MMIO stores still drive external `mem_we`.
  - Verifies sensor MMIO load path returns stub data (`1000` for sensor index 0) after synchronous response latency.

## Reproducible Run Command

```bash
cd /Users/axel/Pulsar
make sim TB=lx32_mmio_decode_tb
```

## Notes

- Current peripheral behavior is still stubbed (`sensor_controller.sv`, `dma_controller.sv`), so this coverage targets address decode and bus routing correctness, not final peripheral timing.

