# LX32 Formal Verification

This directory contains formal verification assets for LX32:

- Coq executable specification and proofs
- SVA harnesses for bounded model checking (SymbiYosys)
- RTL/spec equivalence scripts (Yosys)

## Files

- `LX32_Arch.v` - Architectural state and core types
- `LX32_ALU.v` - ALU semantics and algebraic properties
- `LX32_Branch.v` - Branch semantics
- `LX32_Decode.v` - Decode and immediate extraction semantics
- `LX32_Control.v` - Control-unit decode semantics
- `LX32_RegisterFile.v` - Register-file invariants and lemmas
- `LX32_Step.v` - Single-step and trace execution semantics
- `LX32_Safety.v` - System-level safety theorems
- `sva/` - SVA harnesses and `.sby` jobs
- `lec/` - spec-side models and Yosys equivalence scripts

## Build

From repository root:

```bash
make coq-local
```

For integrated checks with the validator:

```bash
make formal-validate SEED=42
```

For hardware formal checks:

```bash
make formal-sva
make formal-lec
make formal-all
```


