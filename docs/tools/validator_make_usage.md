# Using the Makefile for LX32 Validation and Simulation

## Overview

The LX32 Makefile provides convenient targets for compiling, simulating, and validating the CPU hardware and its test suite. This guide explains how to use the Makefile for both SystemVerilog simulation and Rust-based validation.

---

## Simulation Targets

### Compile and Run a Testbench

To compile and run a SystemVerilog testbench:

```bash
make sim TB=<testbench_name>
```

- Replace `<testbench_name>` with the name of your testbench module (e.g., `lx32_system_tb`).
- Example:

```bash
make sim TB=lx32_system_tb
```

This will compile the RTL and testbench, then run the simulation.

### A3 Custom ISA Directed Suite

Use this exact sequence to validate the first custom ISA block end-to-end in RTL:

```bash
make sim TB=lx32_sensor_tb
make sim TB=lx32_chord_tb
make sim TB=lx32_wait_tb
make sim TB=lx32_report_tb
```

For RTL-vs-golden parity on custom ops, run:

```bash
rm -rf .sim/lx32_lib
mkdir -p .sim/lx32_lib
verilator -Wall -Wno-fatal --cc --Mdir .sim/lx32_lib rtl/arch/*.sv rtl/core/*.sv --top-module lx32_system
cargo test --manifest-path tools/lx32_validator/Cargo.toml --test test_custom_ops -- --nocapture
```

Coverage details are tracked in `docs/lx32k/a3_custom_coverage.md`.

### A5 MMIO Decode Directed Test

Use this test to validate MMIO range decode and external memory write gating:

```bash
make sim TB=lx32_mmio_decode_tb
```

Coverage details are tracked in `docs/lx32k/a5_mmio_decode_coverage.md`.

### A4 Backend Custom ISA Lowering Check

Use this command to verify custom builtin lowering to LX32 custom mnemonics:

```bash
bash tools/lx32_backend/tests/check_custom_intrinsics.sh
```

If backend tools are not yet available (`llc not found`), run:

```bash
make build-backend
bash tools/lx32_backend/tests/check_custom_intrinsics.sh
```

Coverage details are tracked in `docs/lx32k/a4_backend_custom_isa_validation.md`.

To enable VCD generation in testbenches that support it:

```bash
make sim TB=lx32_system_tb SIM_ARGS="+trace +vcd"
```

### Clean Simulation Artifacts

```bash
make clean
```

Removes all simulation output directories.

---

## Validator Targets

The validator targets allow you to run the Rust-based hardware validation suite with flexible options.

### Standard Validation

```bash
make validate
```

Runs all unit and long program tests with default parameters.

### Verbose Validation (Logging Enabled)

```bash
make validate-verbose
```

Runs all tests with detailed logging output.

### Long Program Validation Only

```bash
make validate-long
```

Runs only the long program tests.

### Long Program Validation with Logging

```bash
make validate-long-verbose
```

Runs only the long program tests with detailed logging.

### Validation with Custom Seed

```bash
make validate-seed SEED=42
```

Runs all tests with a reproducible random seed.

### Custom Long Program Validation

```bash
make validate-long-custom NUM=100 LEN=1000 VERBOSE=1 SEED=42
```

- `NUM`: Number of programs to generate and test (default: 10)
- `LEN`: Instructions per program (default: 500)
- `VERBOSE`: Set to `1` to enable logging
- `SEED`: Random seed for reproducibility

Example:

```bash
make validate-long-custom NUM=50 LEN=2000 VERBOSE=1 SEED=12345
```

### Show Validator CLI Help

```bash
make validate-help
```

Displays all available command-line options for the validator.

### Coq Local Check

```bash
make coq-local
```

Builds local Coq specs (`LX32_*.v`) from `tools/lx32_formal/` if present.

### Coq Artifact Cleanup

```bash
make coq-clean
```

Removes generated Coq artifacts from `tools/lx32_formal/` and cleans accidental root-level Coq build files.

### Coq Parent Workspace Build

```bash
make coq-only
make coq-check
```

Builds Coq specs from `COQ_SPEC_DIR` (defaults to `..`) when that workspace is available.

### Formal + Deterministic Validation

```bash
make formal-validate SEED=42
```

Runs Coq checks and then a seeded validator run. `SEED` is mandatory for reproducibility.

### SVA Bounded Model Checking

```bash
make formal-sva
```

Runs hardware temporal/property checks using SymbiYosys.

### Logical Equivalence Checks (LEC-style)

```bash
make formal-lec
```

Runs Yosys equivalence proofs between selected RTL modules and spec models.

### Full Formal Hardware Suite

```bash
make formal-all
```

Runs both SVA checks and equivalence checks.

---

## Notes

- All validator targets use the release build for performance.
- You can combine variables for flexible validation scenarios.
- The Makefile is designed for both development and CI/CD workflows.

---

## Summary Table

| Target                   | Description                                 |
|------------------------- |---------------------------------------------|
| `make validate`          | Standard validation (all tests)             |
| `make validate-verbose`  | All tests with logging                      |
| `make validate-long`     | Only long program tests                     |
| `make validate-long-verbose` | Long program tests with logging         |
| `make validate-seed SEED=42` | All tests with seed 42                 |
| `make validate-long-custom NUM=100 LEN=1000 VERBOSE=1 SEED=42` | Custom long program validation |
| `make validate-help`     | Show validator CLI help                     |
| `make coq-local`         | Build local Coq specs in `tools/lx32_formal` |
| `make coq-clean`         | Remove Coq artifacts (local + root cleanup) |
| `make coq-only`          | Build Coq specs from `COQ_SPEC_DIR`         |
| `make coq-check`         | Clean + rebuild Coq specs                   |
| `make formal-validate SEED=42` | Coq check + deterministic validation |
| `make formal-sva`        | Run SymbiYosys bounded model checks         |
| `make formal-lec`        | Run Yosys equivalence checks                |
| `make formal-all`        | Run complete SVA + LEC suite                |
| `make formal-help`       | Show formal target list                     |

---

For more details, see the Makefile and the validator documentation.
