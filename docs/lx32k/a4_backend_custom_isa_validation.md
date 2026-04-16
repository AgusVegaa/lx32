# A4 Backend Custom ISA Validation

## Scope

This check validates custom builtin lowering in the LX32 LLVM backend for:

- `LX.SENSOR`, `LX.MATRIX`, `LX.DELTA`, `LX.CHORD` (`CUSTOM-0` class)
- `LX.WAIT`, `LX.REPORT` (`CUSTOM-1` class)

using:

- `tools/lx32_backend/tests/09_custom_intrinsics.c`
- `tools/lx32_backend/tests/baremetal/programs/10_matrix_scan.c`
- `tools/lx32_backend/tests/check_custom_intrinsics.sh`

## What Is Verified

- Bare-metal C sources compile through `clang -> llc -march=lx32`.
- Emitted assembly includes expected custom mnemonics:
  - `lx.sensor`, `lx.matrix`, `lx.delta`, `lx.chord`, `lx.wait`, `lx.report`
- TableGen opcode-class mapping is pinned in `LX32InstrInfo.td`:
  - sensor/matrix/delta/chord -> `OPC_CUSTOM_0`
  - wait/report -> `OPC_CUSTOM_1`

## Reproducible Run Commands

```bash
cd /Users/axel/Pulsar
bash tools/lx32_backend/tests/check_custom_intrinsics.sh
```

If `llc` is not available yet, build the backend first:

```bash
cd /Users/axel/Pulsar
make build-backend
bash tools/lx32_backend/tests/check_custom_intrinsics.sh
```

## Notes

- This is backend-lowering coverage (assembly/mapping level), not full ELF execution coverage.
- `check_custom_intrinsics.sh` relies on `compile_baremetal_c.sh` toolchain discovery (`LX32_LLVM_BIN`, `LX32_LLC`, `LX32_CLANG` if needed).

