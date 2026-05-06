# ============================================================
# LX32 Makefile :: SystemVerilog Simulation (Verilator portable)
# ============================================================

SHELL := /bin/sh
VERILATOR ?= verilator
VERILATOR_FLAGS ?= -Wall -Wno-fatal --binary --trace --trace-structs -O2 --timing
SIM_ARGS ?= +trace

OUTDIR := .sim
ROOT_DIR := $(CURDIR)
LIB_OUTDIR := $(abspath $(OUTDIR)/lx32_lib)

# Relative paths
RTL_CORE := rtl/core
RTL_ARCH := rtl/arch
TB_CORE  := tb/core

.PHONY: help sim clean setup librust validate validate-verbose validate-long validate-long-verbose validate-seed validate-long-custom validate-help coq-only coq-check coq-local coq-clean formal-validate closure-proof formal-help formal-clean formal-sva formal-sva-control formal-sva-rf formal-sva-pipeline formal-sva-dma formal-sva-rt formal-lec formal-lec-alu formal-lec-branch formal-all bench-firmware bench-firmware-run

# Verilator include path detection (Linux vs macOS)
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  # macOS (Homebrew)
  VERILATOR_ROOT := $(shell brew --prefix verilator)/share/verilator
else
  # Linux (apt or general)
  VERILATOR_ROOT := /usr/share/verilator
endif	
VERILATOR_INC := $(VERILATOR_ROOT)/include

VALIDATOR_DIR := tools/lx32_validator

librust:
	@rm -rf "$(LIB_OUTDIR)"
	@mkdir -p "$(LIB_OUTDIR)"
	@chmod -R u+rwX "$(OUTDIR)"
	@test -d "$(LIB_OUTDIR)"
	@test -w "$(LIB_OUTDIR)"
	# 1. Generate C++ files
	$(VERILATOR) -Wall \
		-Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
		--cc --assert \
		--Mdir $(LIB_OUTDIR) \
		rtl/arch/*.sv \
		rtl/core/*.sv \
		--top-module lx32_system

	# 2. Compile the bridge (portable include handling)
	g++ -c -fPIC $(VALIDATOR_DIR)/src/bridge.cpp \
		-I$(LIB_OUTDIR) \
		-I$(VERILATOR_INC) \
		-I$(VERILATOR_INC)/vltstd \
		-o $(ROOT_DIR)/.sim/bridge.o

sim: ## Run a specific testbench (usage: make sim TB=lx32_system)
	@if [ -z "$(TB)" ]; then echo "ERROR: Define TB=<name>"; exit 2; fi
	@mkdir -p "$(OUTDIR)/$(TB)"
	@echo "Compiling System: $(TB)..."

	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module $(TB) \
		--Mdir $(OUTDIR)/$(TB) \
		$(RTL_ARCH)/*.sv \
		$(RTL_CORE)/*.sv \
		$(TB_CORE)/$(TB).sv \
		-o $(TB)_sim

	@echo "Running simulation..."
	./$(OUTDIR)/$(TB)/$(TB)_sim $(SIM_ARGS)

clean: ## Remove simulation artifacts
	@rm -rf $(OUTDIR)
	@rm -rf $(FORMAL_OUT)

# ======================
# LX32 Validator Targets
# ======================

VALIDATOR_BIN := $(VALIDATOR_DIR)/target/release/lx32_validator
COQ_SPEC_DIR ?= ..
COQ_LOCAL_DIR := tools/lx32_formal
COQ_LOCAL_FILES := LX32_Arch.v LX32_ALU.v LX32_Branch.v LX32_Decode.v LX32_Control.v LX32_RegisterFile.v LX32_Step.v LX32_Safety.v
FORMAL_OUT := .formal
SVA_DIR := $(COQ_LOCAL_DIR)/sva
LEC_DIR := $(COQ_LOCAL_DIR)/lec
SBY ?= sby
YOSYS ?= yosys
SEED ?=
NUM ?=10
LEN ?=500

# --- Setup & Installation ---

setup: ## Configure the environment and run initial validation
	@chmod +x tools/setup.sh
	@./tools/setup.sh

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

validate: ## Run standard fuzzer
	cargo run --release --manifest-path $(VALIDATOR_DIR)/Cargo.toml --bin lx32_validator

validate-verbose: ## Run fuzzer with detailed output
	cargo run --release --manifest-path $(VALIDATOR_DIR)/Cargo.toml --bin lx32_validator -- --verbose

validate-long: ## Run only long-form program tests
	cargo run --release --manifest-path $(VALIDATOR_DIR)/Cargo.toml --bin lx32_validator -- --long-only

validate-long-verbose: ## Run long tests with details
	cargo run --release --manifest-path $(VALIDATOR_DIR)/Cargo.toml --bin lx32_validator -- --long-only --verbose

validate-seed: ## Run deterministic tests with required seed (usage: make validate-seed SEED=123)
	@if [ -z "$(SEED)" ]; then echo "ERROR: validate-seed requires SEED=<n>"; exit 2; fi
	cargo run --release --manifest-path $(VALIDATOR_DIR)/Cargo.toml --bin lx32_validator -- --seed $(SEED)

validate-long-custom: ## Custom long test (usage: make validate-long-custom NUM=10 LEN=1000)
	cargo run --release --manifest-path $(VALIDATOR_DIR)/Cargo.toml --bin lx32_validator -- --long-only --num-programs $(NUM) --program-length $(LEN) $(if $(SEED),--seed $(SEED)) $(if $(VERBOSE),--verbose)

validate-help: ## Show validator CLI options
	cargo run --release --manifest-path $(VALIDATOR_DIR)/Cargo.toml --bin lx32_validator -- --help

coq-local: ## Build local Coq specs (if present in this repo)
	@$(MAKE) --no-print-directory coq-clean
	@if [ ! -d "$(COQ_LOCAL_DIR)" ] || [ ! -f "$(COQ_LOCAL_DIR)/$(firstword $(COQ_LOCAL_FILES))" ]; then \
		echo "No local Coq specs found in $(COQ_LOCAL_DIR); skipping coq-local."; \
		exit 0; \
	fi
	@if ! command -v coqc >/dev/null 2>&1; then \
		echo "ERROR: coqc not found. Install Coq to run coq-local."; \
		exit 2; \
	fi
	cd "$(COQ_LOCAL_DIR)" && coqc LX32_Arch.v
	cd "$(COQ_LOCAL_DIR)" && coqc LX32_ALU.v
	cd "$(COQ_LOCAL_DIR)" && coqc LX32_Branch.v
	cd "$(COQ_LOCAL_DIR)" && coqc LX32_Decode.v
	cd "$(COQ_LOCAL_DIR)" && coqc LX32_Control.v
	cd "$(COQ_LOCAL_DIR)" && coqc LX32_RegisterFile.v
	cd "$(COQ_LOCAL_DIR)" && coqc LX32_Step.v
	cd "$(COQ_LOCAL_DIR)" && coqc LX32_Safety.v

coq-clean: ## Remove Coq build artifacts (local + accidental root artifacts)
	@rm -f "$(COQ_LOCAL_DIR)"/*.vo "$(COQ_LOCAL_DIR)"/*.vok "$(COQ_LOCAL_DIR)"/*.vos "$(COQ_LOCAL_DIR)"/*.glob
	@rm -f "$(COQ_LOCAL_DIR)"/.*.aux "$(COQ_LOCAL_DIR)"/.lia.cache
	@rm -f LX32_*.vo LX32_*.vok LX32_*.vos LX32_*.glob .LX32_*.aux .lia.cache

coq-only: ## Build Coq specification in parent workspace
	@if [ -f "$(COQ_SPEC_DIR)/Makefile" ] && [ "$(COQ_SPEC_DIR)" != "." ]; then \
		$(MAKE) -C $(COQ_SPEC_DIR); \
	else \
		$(MAKE) coq-local; \
	fi

coq-check: ## Clean + rebuild Coq specification in parent workspace
	@if [ -f "$(COQ_SPEC_DIR)/Makefile" ] && [ "$(COQ_SPEC_DIR)" != "." ]; then \
		$(MAKE) -C $(COQ_SPEC_DIR) clean; \
		$(MAKE) -C $(COQ_SPEC_DIR); \
	else \
		$(MAKE) coq-local; \
	fi

formal-validate: ## Run Coq check + deterministic validator run (usage: make formal-validate SEED=42)
	@if [ -z "$(SEED)" ]; then echo "ERROR: formal-validate requires SEED=<n>"; exit 2; fi
	$(MAKE) coq-check
	$(MAKE) validate-seed SEED=$(SEED)

closure-proof: ## Full closure gate: Coq + formal HW + bridge + deterministic validator (usage: make closure-proof SEED=42)
	@if [ -z "$(SEED)" ]; then echo "ERROR: closure-proof requires SEED=<n>"; exit 2; fi
	$(MAKE) coq-local
	$(MAKE) formal-clean
	$(MAKE) formal-all
	$(MAKE) librust
	$(MAKE) validate-seed SEED=$(SEED)

formal-help: ## Show hardware formal targets (SVA+BMC and LEC)
	@echo "formal-sva           - Run all SVA bounded model checks"
	@echo "formal-sva-control   - Run control unit SVA checks"
	@echo "formal-sva-rf        - Run register file SVA checks"
	@echo "formal-sva-pipeline  - Run pipeline hazard SVA checks"
	@echo "formal-sva-dma       - Run DMA controller FSM SVA checks"
	@echo "formal-sva-rt        - Run rapid-trigger hysteresis SVA checks"
	@echo "formal-lec           - Run all Yosys equivalence checks"
	@echo "formal-lec-alu       - Run ALU equivalence check"
	@echo "formal-lec-branch    - Run Branch Unit equivalence check"
	@echo "formal-all           - Run both SVA and LEC suites"
	@echo "formal-clean         - Remove formal run artifacts"
	@echo "closure-proof        - Coq + formal HW + deterministic validator"

formal-clean: ## Remove formal verification artifacts
	@rm -rf $(FORMAL_OUT)

formal-sva: formal-sva-control formal-sva-rf formal-sva-pipeline formal-sva-dma formal-sva-rt ## Run all SVA bounded model checks

formal-sva-control: ## Run control unit SVA checks (SymbiYosys)
	@if ! command -v $(SBY) >/dev/null 2>&1; then echo "ERROR: $(SBY) not found"; exit 2; fi
	@mkdir -p $(FORMAL_OUT)
	$(SBY) -f -d $(FORMAL_OUT)/control_unit_sva $(SVA_DIR)/control_unit_sva.sby

formal-sva-rf: ## Run register file temporal SVA checks (SymbiYosys)
	@if ! command -v $(SBY) >/dev/null 2>&1; then echo "ERROR: $(SBY) not found"; exit 2; fi
	@mkdir -p $(FORMAL_OUT)
	$(SBY) -f -d $(FORMAL_OUT)/register_file_sva $(SVA_DIR)/register_file_sva.sby

formal-sva-pipeline: ## Run 2-stage pipeline hazard SVA checks (SymbiYosys)
	@if ! command -v $(SBY) >/dev/null 2>&1; then echo "ERROR: $(SBY) not found"; exit 2; fi
	@mkdir -p $(FORMAL_OUT)
	$(SBY) -f -d $(FORMAL_OUT)/pipeline_hazard_sva $(SVA_DIR)/pipeline_hazard_sva.sby

formal-sva-dma: ## Run DMA controller FSM SVA checks (SymbiYosys)
	@if ! command -v $(SBY) >/dev/null 2>&1; then echo "ERROR: $(SBY) not found"; exit 2; fi
	@mkdir -p $(FORMAL_OUT)
	$(SBY) -f -d $(FORMAL_OUT)/dma_controller_sva $(SVA_DIR)/dma_controller_sva.sby

formal-sva-rt: ## Run rapid-trigger hysteresis SVA checks (SymbiYosys)
	@if ! command -v $(SBY) >/dev/null 2>&1; then echo "ERROR: $(SBY) not found"; exit 2; fi
	@mkdir -p $(FORMAL_OUT)
	$(SBY) -f -d $(FORMAL_OUT)/rapid_trigger_sva $(SVA_DIR)/rapid_trigger_sva.sby

formal-lec: formal-lec-alu formal-lec-branch ## Run all Yosys equivalence checks

formal-lec-alu: ## Run ALU logical equivalence check
	@if ! command -v $(YOSYS) >/dev/null 2>&1; then echo "ERROR: $(YOSYS) not found"; exit 2; fi
	@mkdir -p $(FORMAL_OUT)
	$(YOSYS) -s $(LEC_DIR)/alu_eq.ys

formal-lec-branch: ## Run Branch Unit logical equivalence check
	@if ! command -v $(YOSYS) >/dev/null 2>&1; then echo "ERROR: $(YOSYS) not found"; exit 2; fi
	@mkdir -p $(FORMAL_OUT)
	$(YOSYS) -s $(LEC_DIR)/branch_eq.ys

formal-all: formal-sva formal-lec ## Run full formal hardware suite (SVA + LEC)

# ======================
# LX32 Backend Targets
# ======================
LLVM_DIR     ?= $(CURDIR)/.llvm
LX32_LLVM_BIN ?= $(if $(wildcard $(LLVM_DIR)/build/bin/llc),$(LLVM_DIR)/build/bin,/usr/local/bin)
BACKEND_SRC  := $(CURDIR)/tools/lx32_backend
LLVM_REPO    := https://github.com/Axel84727/llvm-project-lx32.git
NPROC        := $(shell nproc 2>/dev/null || sysctl -n hw.logicalcpu)
LLD_EXISTS   := $(shell which lld 2>/dev/null)
LLVM_BRANCH ?= main

# ── Rust toolchain variables ────────────────────────────────────────────────
RUST_LX32_REPO := https://github.com/Axel84727/rust-lx32.git
RUST_LX32_DIR  := $(CURDIR)/.rust/rust-lx32
RUST_HOST      := $(shell rustc -vV 2>/dev/null | sed -n 's/^host: //p')
ifeq ($(RUST_HOST),)
RUST_HOST      := aarch64-apple-darwin
endif
RUST_LX32_RUSTC       := $(RUST_LX32_DIR)/build/$(RUST_HOST)/stage1/bin/rustc
RUST_LX32_STAGE0_CARGO := $(RUST_LX32_DIR)/build/$(RUST_HOST)/stage0/bin/cargo
RUST_LX32_SYSROOT     := $(RUST_LX32_DIR)/build/$(RUST_HOST)/stage1
PAC_DIR        := $(CURDIR)/tools/pulsar_pac
RUST_PROGS_DIR := $(CURDIR)/tools/lx32_backend/tests/baremetal/rust_programs

.PHONY: check-llvm install-backend build-backend setup-backend rebuild-llvm rebuild-rust-compiler rebuild-backend test-baremetal test-baremetal-deep compile-c run-binary bench-all bench-compile-tests bench-build-runner bench-run bench-summary check-rust build-rust-compiler build-rust-sysroot setup-rust build-firmware check-pac build-rust-firmware-tests test-rust-firmware dev-rust

check-llvm: ## Check LLVM, clone if missing
	@if [ -d "$(LLVM_DIR)/.git" ]; then \
		echo "✓ LLVM found at $(LLVM_DIR)"; \
	else \
		echo "→ Cloning LLVM..."; \
		git clone --depth=1 --branch $(LLVM_BRANCH) $(LLVM_REPO) $(LLVM_DIR); \
		echo "✓ LLVM cloned"; \
	fi

install-backend: check-llvm ## Symlink LX32 backend into LLVM tree
	@echo "→ Linking LX32 backend..."
	@rm -rf $(LLVM_DIR)/llvm/lib/Target/LX32
	@ln -s $(BACKEND_SRC) $(LLVM_DIR)/llvm/lib/Target/LX32
	@echo "✓ Backend linked (edits reflect instantly)"

build-backend: install-backend ## Build LLVM with LX32 + native backend
	@echo "→ Configuring LLVM..."
	@cmake -S $(LLVM_DIR)/llvm -B $(LLVM_DIR)/build -G Ninja \
		-DLLVM_TARGETS_TO_BUILD="LX32;AArch64" \
		-DLLVM_ENABLE_PROJECTS="clang;lld" \
		-DCMAKE_BUILD_TYPE=Release \
		-DLLVM_PARALLEL_LINK_JOBS=2 \
		$(if $(LLD_EXISTS),-DLLVM_USE_LINKER=lld)
	@echo "→ Bootstrapping llvm-tblgen..."
	@ninja -C $(LLVM_DIR)/build llvm-tblgen
	@echo "→ Generating LX32 TableGen .inc files..."
	@cd $(BACKEND_SRC)/TableGen && \
		LLVM_TBLGEN=$(LLVM_DIR)/build/bin/llvm-tblgen \
		LLVM_INCLUDE_DIR=$(LLVM_DIR)/llvm/include \
		bash ./compile_td.sh
	@echo "→ Building ($(NPROC) cores)..."
	@ninja -C $(LLVM_DIR)/build -j$(NPROC)
	@echo "✓ Backend built"

setup-backend: build-backend check-rust ## Full setup: clone LLVM + build backend; also ensure Rust fork is cloned
	@echo "✓ LX32 backend ready"
	@echo "  Run 'make setup-rust' to build the LX32 Rust compiler (~20–40 min)"

rebuild-llvm: ## Incremental LLVM rebuild after backend source changes (fast — ninja only recompiles changed files)
	@echo "→ Regenerating LX32 TableGen .inc files..."
	@cd $(BACKEND_SRC)/TableGen && \
		LLVM_TBLGEN=$(LLVM_DIR)/build/bin/llvm-tblgen \
		LLVM_INCLUDE_DIR=$(LLVM_DIR)/llvm/include \
		bash ./compile_td.sh
	@echo "→ Incremental LLVM build ($(NPROC) cores)..."
	@ninja -C $(LLVM_DIR)/build -j$(NPROC)
	@echo "✓ LLVM rebuilt"

rebuild-rust-compiler: ## Force-rebuild stage1 rustc after LLVM changes (relinks against the new LLVM)
	@if [ ! -d "$(RUST_LX32_DIR)/.git" ]; then \
		echo "ERROR: rust-lx32 not found. Run: make check-rust"; exit 1; \
	fi
	@if [ ! -f "$(LLVM_DIR)/build/bin/llvm-config" ]; then \
		echo "ERROR: LLVM not built. Run: make rebuild-llvm"; exit 1; \
	fi
	@echo "→ Rebuilding stage1 rustc against updated LLVM..."
	@echo "   (LIBRARY_PATH=/opt/homebrew/lib for Homebrew zstd)"
	@echo "   This takes a few minutes (incremental relink, not full rebuild)"
	@touch "$(RUST_LX32_DIR)/compiler/rustc_llvm/build.rs"
	@cd "$(RUST_LX32_DIR)" && \
		LIBRARY_PATH=/opt/homebrew/lib \
		python3 x.py build compiler --stage 1
	@echo "✓ Custom rustc rebuilt: $(RUST_LX32_RUSTC)"

rebuild-backend: rebuild-llvm rebuild-rust-compiler ## Full incremental rebuild: LLVM + Rust stage1 (use after editing backend .cpp/.td files)
	@echo ""
	@echo "✓ Backend + rustc rebuild complete"
	@echo "  Run 'make test-rust-firmware' to validate with the new compiler"

# ======================
# Rust Firmware Development
# ======================

check-rust: ## Check if rust-lx32 fork is cloned; clone if missing
	@if [ -d "$(RUST_LX32_DIR)/.git" ]; then \
		echo "✓ rust-lx32 found at $(RUST_LX32_DIR)"; \
		if [ "$$(git -C "$(RUST_LX32_DIR)" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then \
			echo "→ Expanding shallow rust-lx32 history for x.py..."; \
			git -C "$(RUST_LX32_DIR)" fetch --unshallow --tags || { echo "ERROR: failed to unshallow rust-lx32"; exit 1; }; \
			echo "✓ rust-lx32 history expanded"; \
		fi; \
	else \
		echo "→ Cloning rust-lx32 fork..."; \
		git clone $(RUST_LX32_REPO) $(RUST_LX32_DIR); \
		echo "✓ rust-lx32 cloned"; \
	fi

build-rust-compiler: check-rust ## Build the custom stage1 rustc for LX32 (~20-40 min first time)
	@if [ -f "$(RUST_LX32_RUSTC)" ]; then \
		echo "✓ Custom rustc already built: $(RUST_LX32_RUSTC)"; \
	else \
		echo "→ Building stage1 rustc — this takes 20–40 minutes..."; \
		cd "$(RUST_LX32_DIR)" && python3 x.py build compiler --stage 1 || exit 1; \
		if [ -f "$(RUST_LX32_RUSTC)" ]; then \
			echo "✓ Custom rustc built"; \
		else \
			echo "ERROR: stage1 rustc missing after x.py build: $(RUST_LX32_RUSTC)"; exit 1; \
		fi; \
	fi

build-rust-sysroot: build-rust-compiler ## Prepare stage1 sysroot for -Z build-std (source + host std for build scripts)
	@STAGE1_RUSTLIB="$(RUST_LX32_SYSROOT)/lib/rustlib"; \
	LIBSRC="$$STAGE1_RUSTLIB/src/rust/library"; \
	HOST_STDLIB_DIR="$$STAGE1_RUSTLIB/$(RUST_HOST)/lib"; \
	if [ -e "$$LIBSRC" ]; then \
		echo "✓ Rust stdlib source already linked at $$LIBSRC"; \
	else \
		echo "→ Linking Rust stdlib source for -Z build-std..."; \
		mkdir -p "$$STAGE1_RUSTLIB/src/rust"; \
		ln -sfn "$(RUST_LX32_DIR)/library" "$$LIBSRC"; \
		echo "✓ Rust stdlib source linked"; \
	fi; \
	if ls "$$HOST_STDLIB_DIR"/libstd-*.rlib >/dev/null 2>&1; then \
		echo "✓ Stage1 host stdlib already present for $(RUST_HOST)"; \
	else \
		echo "→ Building stage1 host stdlib for $(RUST_HOST) (required for build.rs)..."; \
		cd "$(RUST_LX32_DIR)" && \
			LIBRARY_PATH=/opt/homebrew/lib \
			python3 x.py build library/std --stage 1 || exit 1; \
		if ls "$$HOST_STDLIB_DIR"/libstd-*.rlib >/dev/null 2>&1; then \
			echo "✓ Stage1 host stdlib built"; \
		else \
			echo "ERROR: stage1 host stdlib missing after x.py build: $$HOST_STDLIB_DIR"; exit 1; \
		fi; \
	fi

setup-rust: build-rust-sysroot ## Full Rust toolchain setup: clone, build rustc, build libcore for LX32

build-firmware: build-rust-sysroot ## Build keyboard firmware using -Z build-std (avoids cc-rs / no pre-built sysroot needed)
	@if [ ! -f "$(RUST_LX32_RUSTC)" ]; then \
		echo "ERROR: Custom rustc not found. Run: make setup-rust"; exit 1; \
	fi
	@if [ ! -f "$(RUST_LX32_STAGE0_CARGO)" ]; then \
		echo "ERROR: Stage0 cargo not found at $(RUST_LX32_STAGE0_CARGO). Run: make build-rust-compiler"; exit 1; \
	fi
	@echo "→ Building Rust keyboard firmware (lx32-unknown-none-elf)..."
	@echo "→ Assembling crt0.S..."
	@$(LX32_LLVM_BIN)/llvm-mc -arch=lx32 -filetype=obj \
		$(BACKEND_SRC)/tests/baremetal/crt0.S \
		-o $(BACKEND_SRC)/tests/baremetal/crt0.o
	@cd "$(PAC_DIR)" && \
		RUSTC="$(RUST_LX32_RUSTC)" \
		RUSTC_BOOTSTRAP=1 \
		RUSTFLAGS="-C jump-tables=no -C link-arg=-T$(BACKEND_SRC)/tests/baremetal/link.ld -C link-arg=$(BACKEND_SRC)/tests/baremetal/crt0.o" \
		"$(RUST_LX32_STAGE0_CARGO)" build --release \
			--target lx32-unknown-none-elf \
			-Z build-std=core,compiler_builtins \
			-Z build-std-features=compiler-builtins-mem \
			--example keyboard
	@echo "✓ Firmware built:"
	@echo "  ELF: $(PAC_DIR)/target/lx32-unknown-none-elf/release/examples/keyboard"
	@$(LX32_LLVM_BIN)/llvm-objcopy -O binary \
		"$(PAC_DIR)/target/lx32-unknown-none-elf/release/examples/keyboard" \
		"$(PAC_DIR)/target/lx32-unknown-none-elf/release/examples/keyboard.bin" && \
		echo "  BIN: $(PAC_DIR)/target/lx32-unknown-none-elf/release/examples/keyboard.bin" || true

check-pac: ## Type-check pulsar_pac on the host (no LX32 toolchain needed)
	@echo "→ Type-checking pulsar_pac on host..."
	@cd "$(PAC_DIR)" && cargo check
	@echo "✓ PAC check passed"

build-rust-firmware-tests: build-rust-sysroot ## Compile Rust firmware test programs with -Z build-std (no simulation)
	@if [ ! -f "$(RUST_LX32_RUSTC)" ]; then \
		echo "ERROR: Custom rustc not found. Run: make setup-rust"; exit 1; \
	fi
	@if [ ! -f "$(RUST_LX32_STAGE0_CARGO)" ]; then \
		echo "ERROR: Stage0 cargo not found at $(RUST_LX32_STAGE0_CARGO)"; exit 1; \
	fi
	@echo "→ Assembling crt0.S..."
	@$(LX32_LLVM_BIN)/llvm-mc -arch=lx32 -filetype=obj \
		$(BACKEND_SRC)/tests/baremetal/crt0.S \
		-o $(BACKEND_SRC)/tests/baremetal/crt0.o
	@echo "→ Compiling Rust firmware tests..."
	@cd "$(RUST_PROGS_DIR)" && \
		RUSTC="$(RUST_LX32_RUSTC)" \
		RUSTC_BOOTSTRAP=1 \
		RUSTFLAGS="-C jump-tables=no" \
		"$(RUST_LX32_STAGE0_CARGO)" build --release \
			-Z build-std=core,compiler_builtins \
			-Z build-std-features=compiler-builtins-mem
	@echo "✓ Rust firmware tests compiled"

test-rust-firmware: build-rust-sysroot ## Compile and run Rust firmware tests on the LX32 RTL simulator
	@if [ ! -f "$(RUST_LX32_RUSTC)" ]; then \
		echo "ERROR: Custom rustc not found. Run: make setup-rust"; exit 1; \
	fi
	@echo "→ Running Rust firmware tests..."
	@RUST_LX32_RUSTC="$(RUST_LX32_RUSTC)" \
		RUST_LX32_STAGE0_CARGO="$(RUST_LX32_STAGE0_CARGO)" \
		LX32_LLVM_BIN="$(LX32_LLVM_BIN)" \
		BENCH_RUNNER="$(BENCH_RUNNER)" \
		RUST_PROGS_DIR="$(RUST_PROGS_DIR)" \
		bash $(BACKEND_SRC)/tests/baremetal/run_rust_firmware.sh

dev-rust: check-pac build-rust-sysroot build-firmware test-rust-firmware ## Firmware dev workflow: PAC check + build keyboard firmware + compile/run Rust firmware tests
	@echo ""
	@echo "✓ dev-rust complete — all Rust firmware checks passed"

# ======================
# Baremetal C Development
# ======================

test-baremetal: ## Run baremetal C smoke tests using the LX32 backend
	@echo "→ Running baremetal tests..."
	@cd $(BACKEND_SRC)/tests/baremetal && LX32_LLVM_BIN="$(LX32_LLVM_BIN)" ./run_baremetal_smoke.sh

test-baremetal-deep: ## Run extended baremetal C tests (loops/comparisons/fibonacci)
	@echo "→ Running deep baremetal tests..."
	@cd $(BACKEND_SRC)/tests/baremetal && LX32_LLVM_BIN="$(LX32_LLVM_BIN)" ./run_baremetal_smoke.sh deep

compile-c: ## Compile, assemble, and link a custom C file (usage: make compile-c PROG=my_prog.c)
	@if [ -z "$(PROG)" ]; then echo "ERROR: compile-c requires PROG=<path_to_c_file>"; exit 2; fi
	@if [ ! -f "$(PROG)" ]; then echo "ERROR: File $(PROG) not found"; exit 2; fi
	@echo "→ Compiling $(PROG) to LX32 object..."
	@LX32_LLVM_BIN="$(LX32_LLVM_BIN)" bash $(BACKEND_SRC)/tests/compile_baremetal_c.sh "$(PROG)"
	@echo "→ Assembling crt0.S..."
	@$(LX32_LLVM_BIN)/llvm-mc -arch=lx32 -filetype=obj $(BACKEND_SRC)/tests/baremetal/crt0.S -o $(BACKEND_SRC)/tests/baremetal/crt0.o
	@echo "→ Linking into ELF and flat Binary..."
	@$(LX32_LLVM_BIN)/ld.lld -T $(BACKEND_SRC)/tests/baremetal/link.ld $(BACKEND_SRC)/tests/baremetal/crt0.o "$${PROG%.*}.o" -o "$${PROG%.*}.elf"
	@$(LX32_LLVM_BIN)/llvm-objcopy -O binary "$${PROG%.*}.elf" "$${PROG%.*}.bin"
	@echo "✓ Success! Generated $${PROG%.*}.elf and $${PROG%.*}.bin"

run-binary: librust ## Run a custom LX32 binary on the RTL simulation (usage: make run-binary BIN=my_program.bin)
	@if [ -z "$(BIN)" ]; then echo "ERROR: run-binary requires BIN=<path_to_bin_file>"; exit 2; fi
	@if [ ! -f "$(BIN)" ]; then echo "ERROR: File $(BIN) not found"; exit 2; fi
	@echo "→ Running $(BIN) on LX32 RTL Simulation..."
	@cd $(VALIDATOR_DIR) && cargo run --release --bin run_program -- --binary $(abspath $(BIN))

# =============================================================================
# Benchmark orchestration
#
# bench-all      Full pipeline: compile every C test → run on RTL → bench_results.json
# bench-compile-tests  Recompile all C programs in tests/baremetal/programs/
# bench-build-runner   Build the run_program binary in release mode
# bench-run      Run pre-compiled binaries, write bench_results.json
# bench-summary  Print a human-readable table from the last bench-all run
#
# Output file format: JSON array of objects, one per program.
# Each object contains: program name, binary size, static instruction count,
# exit status, exit code, total cycles, instructions committed, stall cycles,
# IPC, dynamic instruction mix, and final register values.
#
# Parser note: the JSON array is always well-formed even when only a subset of
# programs compiled/ran successfully (missing programs are simply absent from
# the array).
# =============================================================================

BENCH_PROGRAMS_DIR := $(BACKEND_SRC)/tests/baremetal/programs
BENCH_REPORT       := bench_results.json
BENCH_RUNNER       := $(abspath $(VALIDATOR_DIR)/target/release/run_program)

# Enumerate every .c file in the programs directory; derive .bin targets from them.
BENCH_SRCS := $(wildcard $(BENCH_PROGRAMS_DIR)/*.c)

.PHONY: bench-all bench-compile-tests bench-build-runner bench-run bench-summary

bench-build-runner: ## Build the run_program RTL runner in release mode
	@echo "→ Building run_program runner..."
	@cargo build --release --manifest-path $(VALIDATOR_DIR)/Cargo.toml --bin run_program
	@echo "✓ Runner built: $(BENCH_RUNNER)"

bench-compile-tests: ## Compile every C test program in tests/baremetal/programs/
	@echo "→ Compiling all baremetal C test programs..."
	@ok=0; fail=0; \
	for src in $(BENCH_SRCS); do \
		name=$$(basename $$src); \
		printf "  %-40s" "$$name"; \
		if $(MAKE) --no-print-directory compile-c PROG="$$src" > /dev/null 2>&1; then \
			printf " ✓\n"; ok=$$((ok+1)); \
		else \
			printf " ✗\n"; fail=$$((fail+1)); \
		fi; \
	done; \
	echo "→ Compiled: $$ok ok, $$fail failed"

bench-run: ## Run all compiled .bin files through the RTL runner and write $(BENCH_REPORT)
	@if [ ! -x "$(BENCH_RUNNER)" ]; then \
		echo "ERROR: runner not built — run: make bench-build-runner"; exit 1; \
	fi
	@echo "→ Running benchmarks..."
	@n=0; total=$$(ls $(BENCH_PROGRAMS_DIR)/*.bin 2>/dev/null | wc -l | tr -d ' '); \
	printf '[\n' > $(BENCH_REPORT); \
	first=1; \
	for bin in $(BENCH_PROGRAMS_DIR)/*.bin; do \
		test -f "$$bin" || continue; \
		n=$$((n+1)); \
		name=$$(basename "$$bin"); \
		printf "  [%2d/%2d] %-44s" $$n $$total "$$name"; \
		if [ "$$first" = "0" ]; then printf ',\n' >> $(BENCH_REPORT); fi; \
		if "$(BENCH_RUNNER)" --binary "$$bin" --json >> $(BENCH_REPORT) 2>/dev/null; then \
			printf " ✓\n"; \
		else \
			printf " ✗ (runner error)\n"; \
		fi; \
		first=0; \
	done; \
	printf '\n]\n' >> $(BENCH_REPORT)
	@echo "✓ Results written to $(BENCH_REPORT)"

bench-all: librust bench-build-runner bench-compile-tests bench-run bench-firmware ## Full benchmark pipeline: C + Rust firmware, produces both report files
	@echo ""
	@echo "=== Benchmark complete ==="
	@echo "  C report      : $(BENCH_REPORT)"
	@echo "  Firmware report: $(FIRMWARE_BENCH_REPORT)"
	@echo "  Run: make bench-summary          (C programs)"
	@echo "       make bench-firmware-summary (Rust firmware)"

bench-summary: ## Print a human-readable summary table from the last bench-all run
	@python3 tools/bench_summary.py $(BENCH_REPORT)

bench-summary-50mhz: ## Print summary with 50 MHz latency column (default clock)
	@python3 tools/bench_summary.py $(BENCH_REPORT) --clock-mhz 50

# ── Rust firmware benchmarks ──────────────────────────────────────────────────
# bench-firmware     Build + run the Rust firmware examples and append to report
# bench-firmware-run Run pre-built Rust firmware .bin files through the runner
FIRMWARE_BENCH_BINS := \
	$(PAC_DIR)/target/lx32-unknown-none-elf/release/examples/keyboard.bin \
	$(PAC_DIR)/target/lx32-unknown-none-elf/release/examples/latency.bin \
	$(PAC_DIR)/target/lx32-unknown-none-elf/release/examples/frame_budget.bin

FIRMWARE_BENCH_REPORT := bench_firmware_results.json

bench-firmware: librust bench-build-runner build-rust-sysroot ## Build + run Rust firmware examples through RTL bench
	@if [ ! -f "$(RUST_LX32_RUSTC)" ]; then \
		echo "ERROR: Custom rustc not found. Run: make setup-rust"; exit 1; \
	fi
	@echo "→ Building Rust firmware examples for benchmarking..."
	@$(LX32_LLVM_BIN)/llvm-mc -arch=lx32 -filetype=obj \
		$(BACKEND_SRC)/tests/baremetal/crt0.S \
		-o $(BACKEND_SRC)/tests/baremetal/crt0.o
	@for ex in keyboard latency frame_budget; do \
		echo "  → Building example: $$ex"; \
		cd "$(PAC_DIR)" && \
			RUSTC="$(RUST_LX32_RUSTC)" \
			RUSTC_BOOTSTRAP=1 \
			RUSTFLAGS="-C jump-tables=no -C link-arg=-T$(BACKEND_SRC)/tests/baremetal/link.ld -C link-arg=$(BACKEND_SRC)/tests/baremetal/crt0.o" \
			"$(RUST_LX32_STAGE0_CARGO)" build --release \
				--target lx32-unknown-none-elf \
				-Z build-std=core,compiler_builtins \
				-Z build-std-features=compiler-builtins-mem \
				--example $$ex && \
		$(LX32_LLVM_BIN)/llvm-objcopy -O binary \
			"$(PAC_DIR)/target/lx32-unknown-none-elf/release/examples/$$ex" \
			"$(PAC_DIR)/target/lx32-unknown-none-elf/release/examples/$$ex.bin" || true; \
	done
	@$(MAKE) bench-firmware-run

bench-firmware-summary: ## Print a human-readable table from the last bench-firmware run
	@python3 tools/bench_summary.py $(FIRMWARE_BENCH_REPORT) --clock-mhz 50

bench-firmware-run: ## Run pre-built Rust firmware .bin files, write $(FIRMWARE_BENCH_REPORT)
	@if [ ! -x "$(BENCH_RUNNER)" ]; then \
		echo "ERROR: runner not built — run: make bench-build-runner"; exit 1; \
	fi
	@echo "→ Running Rust firmware benchmarks..."
	@printf '[\n' > $(FIRMWARE_BENCH_REPORT); \
	first=1; \
	for bin in $(FIRMWARE_BENCH_BINS); do \
		test -f "$$bin" || { echo "  SKIP (not built): $$bin"; continue; }; \
		name=$$(basename "$$bin"); \
		printf "  %-44s" "$$name"; \
		if [ "$$first" = "0" ]; then printf ',\n' >> $(FIRMWARE_BENCH_REPORT); fi; \
		if "$(BENCH_RUNNER)" --binary "$$bin" --json >> $(FIRMWARE_BENCH_REPORT) 2>/dev/null; then \
			printf " ✓\n"; \
		else \
			printf " ✗ (runner error)\n"; \
		fi; \
		first=0; \
	done; \
	printf '\n]\n' >> $(FIRMWARE_BENCH_REPORT)
	@echo "✓ Firmware results written to $(FIRMWARE_BENCH_REPORT)"
	@python3 tools/bench_summary.py $(FIRMWARE_BENCH_REPORT) --clock-mhz 50
