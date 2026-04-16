# LX32 Documentation Orchestration & Deep Reference

## Overview
This README provides a comprehensive guide to the LX32 project documentation. It orchestrates all files in the `docs/` directory, explains their relationships, and offers deep technical reference for the golden model, RTL, tools, and test suites.

---

## Structure
- [Golden Model](golden_model/)
  - [Architecture Packages](golden_model/arch/)
  - [Core Modules](golden_model/core/)
  - [Source Modules](golden_model/source/)
  - [Test Modules](golden_model/tests/)
- [RTL Reference](rtl/)
- [Tools](tools/)
- [LX32K A3 Custom Coverage](lx32k/a3_custom_coverage.md)
- [LX32K A4 Backend Custom ISA Validation](lx32k/a4_backend_custom_isa_validation.md)
- [LX32K A5 MMIO Decode Coverage](lx32k/a5_mmio_decode_coverage.md)

---

## Repository structure

```
.
├── Makefile
├── README.md
├── docs
│   ├── README.md
│   ├── golden_model
│   │   ├── arch
│   │   │   ├── generic
│   │   │   │   └── generic_template_arch.md
│   │   │   ├── lx32_alu_pkg.md
│   │   │   ├── lx32_arch_pkg.md
│   │   │   ├── lx32_branch_pkg.md
│   │   │   ├── lx32_decode_pkg.md
│   │   │   ├── lx32_isa_pkg.md
│   │   │   └── mod.md
│   │   ├── core
│   │   │   ├── alu.md
│   │   │   ├── branch_unit.md
│   │   │   ├── control_unit.md
│   │   │   ├── generic
│   │   │   │   └── generic_template_core.md
│   │   │   ├── imm_gen.md
│   │   │   ├── lsu.md
│   │   │   ├── lx32_system.md
│   │   │   ├── memory_sim.md
│   │   │   ├── mod.md
│   │   │   ├── reg_generic.md
│   │   │   └── register_file.md
│   │   ├── source
│   │   │   ├── bridge.md
│   │   │   ├── cli.md
│   │   │   ├── generic
│   │   │   │   └── generic_template_src.md
│   │   │   ├── lib.md
│   │   │   ├── main.md
│   │   │   ├── program_generator.md
│   │   │   ├── shrinking.md
│   │   │   └── test_runner.md
│   │   └── tests
│   │       ├── common
│   │       │   └── mod.md
│   │       ├── generic
│   │       │   └── generic_template_tests.md
│   │       ├── test_alu.md
│   │       ├── test_branch_unit.md
│   │       ├── test_control_unit.md
│   │       ├── test_imm_gen.md
│   │       ├── test_long_programs.md
│   │       ├── test_lsu.md
│   │       ├── test_lx32_system.md
│   │       ├── test_memory_sim.md
│   │       ├── test_reg_generic.md
│   │       └── test_register_file.md
│   ├── rtl
│   │   ├── arch
│   │   │   ├── generic
│   │   │   │   └── generic_template_arch.md
│   │   │   ├── lx32_alu_pkg.md
│   │   │   ├── lx32_arch_pkg.md
│   │   │   ├── lx32_branch_pkg.md
│   │   │   ├── lx32_decode_pkg.md
│   │   │   └── lx32_isa_pkg.md
│   │   └── core
│   │       ├── alu.md
│   │       ├── branch_unit.md
│   │       ├── control_unit.md
│   │       ├── generic
│   │       │   └── generic_template_core.md
│   │       ├── imm_gen.md
│   │       ├── lsu.md
│   │       ├── lx32_system.md
│   │       ├── memory_sim.md
│   │       ├── reg_generic.md
│   │       └── register_file.md
│   └── tools
│       ├── build.md
│       ├── demo.md
│       ├── setup.md
│       └── validator_make_usage.md
├── rtl
│   ├── arch
│   │   ├── lx32_alu_pkg.sv
│   │   ├── lx32_arch_pkg.sv
│   │   ├── lx32_branch_pkg.sv
│   │   ├── lx32_decode_pkg.sv
│   │   └── lx32_isa_pkg.sv
│   └── core
│       ├── alu.sv
│       ├── branch_unit.sv
│       ├── control_unit.sv
│       ├── imm_gen.sv
│       ├── lsu.sv
│       ├── lx32_system.sv
│       ├── memory_sim.sv
│       ├── reg_generic.sv
│       └── register_file.sv
├── tb
│   ├── arch
│   │   ├── branches_pkg_tb.sv
│   │   ├── lx32_arch_pkg_tb.sv
│   │   └── lx32_pkg_tb.sv
│   └── core
│       ├── alu_tb.sv
│       ├── branch_unit_tb.sv
│       ├── control_unit_tb.sv
│       ├── imm_gen_tb.sv
│       ├── lsu_tb.sv
│       ├── lx32_system_tb.sv
│       ├── lx32_mmio_decode_tb.sv
│       ├── memory_sim_tb.sv
│       ├── reg_generic_tb.sv
│       └── register_file_tb.sv
└── tools
    ├── lx32_formal
    │   ├── README.md
    │   ├── LX32_ALU.v
    │   ├── LX32_Arch.v
    │   ├── LX32_Branch.v
    │   ├── LX32_Control.v
    │   ├── LX32_Decode.v
    │   ├── LX32_RegisterFile.v
    │   ├── LX32_Safety.v
    │   ├── LX32_Step.v
    │   ├── lec
    │   │   ├── alu_eq.ys
    │   │   ├── alu_spec.sv
    │   │   ├── branch_eq.ys
    │   │   └── branch_unit_spec.sv
    │   └── sva
    │       ├── control_unit_sva.sby
    │       ├── control_unit_sva.sv
    │       ├── register_file_sva.sby
    │       └── register_file_sva.sv
    ├── lx32_validator
    │   ├── Cargo.lock
    │   ├── Cargo.toml
    │   ├── build.rs
    │   ├── demo.sh
    │   ├── src
    │   │   ├── bridge.cpp
    │   │   ├── cli.rs
    │   │   ├── lib.rs
    │   │   ├── main.rs
    │   │   ├── models
    │   │   │   ├── arch
    │   │   │   │   ├── lx32_alu_pkg.rs
    │   │   │   │   ├── lx32_arch_pkg.rs
    │   │   │   │   ├── lx32_branch_pkg.rs
    │   │   │   │   ├── lx32_decode_pkg.rs
    │   │   │   │   ├── lx32_isa_pkg.rs
    │   │   │   │   └── mod.rs
    │   │   │   ├── core
    │   │   │   │   ├── alu.rs
    │   │   │   │   ├── branch_unit.rs
    │   │   │   │   ├── control_unit.rs
    │   │   │   │   ├── imm_gen.rs
    │   │   │   │   ├── lsu.rs
    │   │   │   │   ├── lx32_system.rs
    │   │   │   │   ├── memory_sim.rs
    │   │   │   │   ├── mod.rs
    │   │   │   │   ├── reg_generic.rs
    │   │   │   │   └── register_file.rs
    │   │   │   └── mod.rs
    │   │   ├── program_generator.rs
    │   │   ├── shrinking.rs
    │   │   └── test_runner.rs
    │   └── tests
    │       ├── common
    │       │   └── mod.rs
    │       ├── test_alu.rs
    │       ├── test_branch_unit.rs
    │       ├── test_control_unit.rs
    │       ├── test_imm_gen.rs
    │       ├── test_long_programs.rs
    │       ├── test_lsu.rs
    │       ├── test_lx32_system.rs
    │       ├── test_memory_sim.rs
    │       ├── test_reg_generic.rs
    │       └── test_register_file.rs
    └── setup.sh
```
---

## Golden Model Documentation
### Architecture Packages (`golden_model/arch/`)
- **lx32_alu_pkg.md**: Canonical ALU operation types, enums, and constants. Used for ALU, control, decode. Mirrors RTL.
- **lx32_arch_pkg.md**: Fundamental architectural types, constants, and parameters. Used for instruction formats, register mapping, memory layout. Mirrors RTL.
- **lx32_branch_pkg.md**: Branch operation types, enums, and constants. Used for branch unit, control, decode. Mirrors RTL.
- **lx32_decode_pkg.md**: Immediate extraction logic, decode parameters, and functions. Used for instruction decoding and immediate generation. Mirrors RTL.
- **lx32_isa_pkg.md**: Opcode enumerations and instruction class encodings. Used for instruction decoding and pipeline control. Mirrors RTL.
- **mod.md**: Central repository, re-exports all architecture packages for unified access.

### Core Modules (`golden_model/core/`)
- **alu.md**: Implements ALU for LX32 base operations. Reference for arithmetic, logical, shift, and comparison. Unit tests: `test_alu.rs`.
- **branch_unit.md**: Branch evaluation logic for LX32 base branch conditions. Unit tests: `test_branch_unit.rs`.
- **control_unit.md**: Instruction decode logic, main control, ALU operation refinement. Unit tests: `test_control_unit.rs`.
- **imm_gen.md**: Immediate generation logic for LX32 base instructions. Unit tests: `test_imm_gen.rs`.
- **lsu.md**: Load/Store Unit, single-cycle memory operations. Unit tests: `test_lsu.rs`.
- **lx32_system.md**: Integrates all core sub-modules, single-cycle execution. Unit tests: `test_lx32_system.rs`.
- **memory_sim.md**: Dual-port simulation memory, 4KB, word-aligned. Unit tests: `test_memory_sim.rs`.
- **reg_generic.md**: Parameterizable synchronous register, async reset, clock enable. Unit tests: `test_reg_generic.rs`.
- **register_file.md**: Register file, 32 registers, dual async read, sync write. Unit tests: `test_register_file.rs`.
- **mod.md**: Central module, re-exports all core modules for integration.

### Source Modules (`golden_model/source/`)
- **bridge.md**: C++ hardware bridge, FFI interface between Rust and Verilated hardware model.
- **cli.md**: CLI argument parsing, unified configuration for test orchestration.
- **lib.md**: Core Rust library interface, exposes models, program generation, shrinking, FFI bindings.
- **main.md**: Main orchestrator, coordinates validation tests, manages seeds, long program generation, shrinking.
- **program_generator.md**: Generates long instruction sequences for comprehensive hardware testing.
- **shrinking.md**: Test case shrinker, reduces failing cases to minimal reproducible examples.
- **test_runner.md**: Coordinates execution of all validation test suites, delegates to individual test modules.

### Test Modules (`golden_model/tests/`)
- **test_alu.md**: Validates ALU, parameterized unit tests, state comparison, property-oriented fuzzing.
- **test_branch_unit.md**: Validates branch unit, parameterized unit tests, state comparison.
- **test_control_unit.md**: Validates control unit, parameterized unit tests, state comparison.
- **test_imm_gen.md**: Validates immediate generator, parameterized unit tests, state comparison.
- **test_lsu.md**: Validates LSU, parameterized unit tests, state comparison.
- **test_lx32_system.md**: Validates overall system, parameterized unit tests, state comparison.
- **test_memory_sim.md**: Validates memory simulation, parameterized unit tests, state comparison.
- **test_reg_generic.md**: Validates generic register, parameterized unit tests, state comparison.
- **test_register_file.md**: Validates register file, parameterized unit tests, state comparison.
- **test_long_programs.md**: Validates with long, randomly generated instruction sequences, integration tests, shrinking.

---

## RTL Reference Documentation (`rtl/`)
- Mirrors golden model structure for architecture and core modules.
- Provides SystemVerilog reference for hardware equivalence.
- See `rtl/arch/` and `rtl/core/` for package and module documentation.

---

## Tools Documentation (`tools/`)
- **build.md**: Explains `build.rs` script, integrates Verilator C++ code with Rust, static library compilation.
- **demo.md**: Demonstrates advanced validation features, reproducible seeds, CLI help, long program testing.
- **setup.md**: Environment setup, dependency checks, bridge generation, validator compilation, initial validation.
- **validator_make_usage.md**: Makefile guide for simulation and validation, target descriptions, CLI options, custom scenarios.
- **coq_workflow.md**: Practical Coq build and validation workflow.
- **isa_formal_equations.md**: Full ISA equation sheet and canonical closure theorem.
- **lx32_optimized_c.md**: Practical guide for minimalist, backend-friendly bare-metal C.

---

## Deep Technical Reference & Orchestration
### Integration & Workflow
- The LX32 validator is orchestrated via the CLI and Makefile, with modular Rust and C++ components.
- The golden model and RTL are cross-validated via test suites and property-oriented fuzzing.
- Shrinking engine reduces failing cases for triage.
- All modules are unit tested and regression tested for hardware/software equivalence.

### How to Use
- Start with [setup.md](tools/setup.md) for environment preparation.
- Use [validator_make_usage.md](tools/validator_make_usage.md) for Makefile targets and CLI options.
- Use [lx32_optimized_c.md](tools/lx32_optimized_c.md) for C coding patterns tuned to the current backend.
- Explore [demo.md](tools/demo.md) for advanced features and reproducible validation.
- Dive into [golden_model/core/](golden_model/core/) and [golden_model/arch/](golden_model/arch/) for module and package details.
- Reference [golden_model/tests/](golden_model/tests/) for test design and validation principles.
- Compare with [rtl/](rtl/) for hardware equivalence.

### License
All documentation and code are MIT licensed.

---

## Links & References
- [Golden Model Source](../tools/lx32_validator/src/)
- [RTL Source](../rtl/)
- [Makefile](../Makefile)
- [Setup Script](../tools/setup.sh)
- [Demo Script](../tools/lx32_validator/demo.sh)

---

## Contact & Contribution
- For questions, see [README.md](../README.md) in project root.
- Contributions welcome via pull requests.

---

## Revision
- Last updated: March 8, 2026


