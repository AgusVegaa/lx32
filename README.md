<div align="center">
  <strong>PULSAR</strong><br>
  <em>LX32K keyboard processor stack: custom 32-bit core, RTL, golden model, LLVM backend, firmware, and host tools.</em>

  Overview | Firmware | Backend | RTL | Tools
</div>

This is the main source code repository for PULSAR. It contains the processor RTL, validation models, toolchain backend, firmware flow, and host utilities.

## Why PULSAR?

- **Determinism:** Hardware and firmware are designed for predictable timing and stable input scanning.
- **Full-stack control:** Custom ISA extensions, compiler backend, and simulation are all in one place.
- **Validation-first:** RTL, golden model, and tests keep behavior aligned across the stack.

## Quick Start

Run `make setup-backend`, then `make librust`.

## Getting Oriented

Start with `docs/README.md`, then `docs/firmware_guide.md` and `docs/backend.md`.
