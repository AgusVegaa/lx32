# lx32

**lx32** is the first phase of a long-term project to build a complete computer from scratch — processor, compiler, operating system, and hardware — with no compromises on correctness, documentation, or verification.

This repository contains a 32-bit single-cycle CPU core: a custom ISA implemented in SystemVerilog, verified against a Rust golden model with over 1.1 billion random instructions executed without a single failure.

---

## What this is

lx32 is Phase 0 of a larger architecture called **lx-Ω** — a full-stack computing platform designed from first principles. The roadmap ahead:

- **lx32** — 32-bit single-cycle core ✅ complete
- **LLVM backend** — compiler support for the lx32 ISA (in progress, check branch `feat/llvm-backend`)
- **lx-Ω OS** — a capability-based microkernel written in Rust
- **lx-Ω hardware** — custom PCB and FPGA implementation
- **lx-Ω laptop** — a complete laptop built from the ground up

Every design decision is documented. Every module has a specification, a Rust reference model, and a test suite. Nothing is left implicit.

---

## Architecture

lx32 implements a custom 32-bit ISA structurally similar to RV32I. The core is single-cycle, fully documented, and verified.

| Property | Value |
|---|---|
| Datapath width | 32 bits |
| Register file | 32 × 32-bit general-purpose registers (x0 hardwired to zero) |
| Instruction width | Fixed 32 bits |
| Instruction formats | R, I, S, B, U, J |
| Endianness | Little-endian |
| Pipeline | Single-cycle |

**Implemented instruction classes:**

| Class | Opcodes | Description |
|---|---|---|
| R-type ALU | OP_OP | Register-register: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU |
| I-type ALU | OP_OP_IMM | Immediate: ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI |
| Load | OP_LOAD | Memory read |
| Store | OP_STORE | Memory write |
| Branch | OP_BRANCH | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Jump | OP_JAL, OP_JALR | Unconditional jump with link |
| Upper immediate | OP_LUI, OP_AUIPC | Load upper immediate, Add upper immediate to PC |

---

## Verification

The LX32 architecture is verified through a dual-layer strategy.

**Layer 1 — SystemVerilog testbenches** (`tb/`): fast sanity checks per module, used during development to catch regressions immediately.

**Layer 2 — Rust golden model + fuzzer** (`tools/lx32_validator/`): the definitive verification layer. A Rust model mirrors every hardware module. A fuzzer generates random instruction sequences and compares RTL output against the reference model on every cycle. A shrinker reduces any failing case to its minimal reproducible form.

| Module | Random Vectors | Status |
|---|---|---|
| ALU | 100,000,000 | ✅ PASSED |
| Branch Unit | 100,000,000 | ✅ PASSED |
| Control Unit | 100,000,000 | ✅ PASSED |
| Register File | 100,000,000 | ✅ PASSED |
| Full System | 100,000,000 | ✅ PASSED |
| **Total** | **1,100,000,000+** | **✅ ZERO FAILURES** |

1.1 billion instructions validated in under 75 seconds.

For full details on the verification infrastructure see [`docs/tools/validator_make_usage.md`](docs/tools/validator_make_usage.md).

---

## Quick start

```bash
git clone https://github.com/Axel84727/lx32.git
cd lx32
make setup
```

Requires: `verilator`, Rust toolchain (`cargo`).

`make setup` handles everything: generates the Verilator bridge, compiles the validator, and runs the full test suite.

---

## Validation commands

```bash
make validate                                        # Full test suite
make validate-verbose                                # With detailed output
make validate-long                                   # Long program tests only
make validate-seed SEED=42                           # Reproducible run
make validate-long-custom NUM=50 LEN=2000 SEED=123  # Custom configuration
make validate-help                                   # All available options
```

For simulation of individual testbenches:

```bash
make sim TB=lx32_system_tb
make sim TB=alu_tb
```

See [`docs/tools/validator_make_usage.md`](docs/tools/validator_make_usage.md) for the complete reference.

---

## Documentation

All documentation lives in [`docs/`](docs/). The structure mirrors the source tree:

- [`docs/rtl/`](docs/rtl/) — hardware module specifications
- [`docs/golden_model/`](docs/golden_model/) — Rust reference model specifications
- [`docs/tools/`](docs/tools/) — tooling and workflow guides

Start with [`docs/README.md`](docs/README.md) for the full index and navigation guide.

---

## Contributing

lx32 has a contributor framework built in. Every module has a generic template in the `generic/` directories inside `docs/` that defines the expected structure for RTL, golden model, and tests.

Contributions that extend the ISA, add functional units, or improve verification tooling are welcome. All contributions must maintain the isomorphic documentation standard — every hardware module has a corresponding Rust model and a corresponding specification document.

---

## License

MIT
