# LX32 Backend Smoke Tests

This folder contains minimal backend smoke tests for early bring-up.

## Scope

These tests validate the first usable SelectionDAG slice:

- formal argument lowering for fixed-arg integer functions,
- return lowering,
- DAG selector wiring in `LX32TargetMachine`.

It also contains a bare-metal C smoke slice for firmware-focused bring-up.

## Run

```bash
bash /Users/axel/lx32/tools/lx32_backend/tests/run_smoke.sh /path/to/llc
```

If no argument is provided, the script tries:

- `/Users/axel/llvm-project/build/bin/llc`
- `llc` from `PATH`

## Notes

- These are bring-up checks, not full `lit` tests yet.
- They only require `-filetype=asm`.
- If your `llc` binary points at a different LX32 source checkout, failures may
  reflect checkout mismatch rather than this workspace.

## Bare-Metal C smoke

Run:

```bash
bash /Users/axel/lx32/tools/lx32_backend/tests/baremetal/run_baremetal_smoke.sh
```

This validates the freestanding C path (`clang -> llc -march=lx32`) for:

- plain integer arithmetic,
- pointer/MMIO loads and stores,
- direct calls and returns,
- no implicit libcalls.

Current expected status: four PASS smoke cases (`return42`, `pointer_store`,
`call_chain`, `branch_loop`).

The compile helper defaults to `-O0` for backend bring-up stability. Override
with `LX32_C_OLEVEL` when probing optimization-related gaps:

```bash
LX32_C_OLEVEL=1 make test-baremetal
```

Enable extra backend diagnostics (`llc -verify-machineinstrs`) via:

```bash
LX32_BACKEND_DEBUG=1 make test-baremetal
```

## Bare-Metal C deep coverage

Run:

```bash
make test-baremetal-deep
```

This extends smoke coverage with comparison-heavy control flow, pointer walking,
iterative Fibonacci, and recursive Fibonacci stress cases.

## What is still missing for executing C end-to-end

- MC/object emission for a full `-filetype=obj` pipeline is still limited in
  this workspace cut, so a full production link/run flow needs more hardening.


