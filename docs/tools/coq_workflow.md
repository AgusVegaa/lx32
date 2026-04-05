# Coq Workflow (Local)

## Purpose

This guide explains how to use the Coq model in `tools/lx32_formal/` as a formal contract for LX32.

If your environment also has a parent Coq workspace, `coq-only` and `coq-check` can still use it via `COQ_SPEC_DIR`.

---

## Prerequisites

- Coq toolchain (`coqc`) available in PATH
- Working `Makefile` in `lx32/`
- Optional parent Coq workspace (`../`) if you want external integration via `COQ_SPEC_DIR`

---

## Recommended Commands

From `lx32/`:

```bash
make coq-check
```

Runs a clean Coq build from `COQ_SPEC_DIR` when available; otherwise falls back to local formal specs.

```bash
make coq-only
```

Runs a regular Coq build from `COQ_SPEC_DIR` when available; otherwise falls back to local formal specs.

```bash
make coq-local
```

Builds local Coq files in `tools/lx32_formal/`.

```bash
make coq-clean
```

Removes generated Coq artifacts and keeps the repository tree clean.

```bash
make validate-seed SEED=42
```

Runs deterministic RTL-vs-golden validation.

```bash
make formal-validate SEED=42
```

Runs Coq check first, then deterministic validator run.
`SEED` is required for `formal-validate` to guarantee reproducibility.

---

## Typical Change Policy

When ISA behavior changes:

1. Update Coq spec (`tools/lx32_formal/LX32_*.v`).
2. Update RTL (`rtl/`).
3. Update Rust golden model (`tools/lx32_validator/src/models/`).
4. Run:
   - `make coq-check`
   - `make validate-seed SEED=<n>`

This keeps formal intent and executable behavior aligned.

---

## Refinement Closure Checklist

Use this command for a reproducible closure run:

```bash
make closure-proof SEED=42
```

Equivalent expanded sequence:

```bash
make coq-clean
make coq-local
make formal-all
make validate-seed SEED=42
```

Verification scope:

1. Coq compiles with the explicit step contract in `tools/lx32_formal/LX32_Safety.v`.
2. SVA + LEC hardware formal checks pass.
3. Lockstep executable validation (seeded) passes.

Key closure artifacts to review:

- `rtl_step_contract`
- `lockstep_cycle_obligation`
- `T7_closure_claim_end_to_end`

Primary formal reference:

- `docs/tools/isa_formal_equations.md`

---

## Fast Smoke Sequence

```bash
make sim TB=control_unit_tb
make sim TB=lx32_system_tb
make coq-only
make validate-long-custom NUM=5 LEN=500 SEED=42
```

