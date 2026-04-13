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

.PHONY: help sim clean setup librust validate validate-verbose validate-long validate-long-verbose validate-seed validate-long-custom validate-help coq-only coq-check coq-local coq-clean formal-validate closure-proof formal-help formal-clean formal-sva formal-sva-control formal-sva-rf formal-lec formal-lec-alu formal-lec-branch formal-all

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
	$(VERILATOR) -Wall --cc \
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
	@echo "formal-lec           - Run all Yosys equivalence checks"
	@echo "formal-lec-alu       - Run ALU equivalence check"
	@echo "formal-lec-branch    - Run Branch Unit equivalence check"
	@echo "formal-all           - Run both SVA and LEC suites"
	@echo "formal-clean         - Remove formal run artifacts"
	@echo "closure-proof        - Coq + formal HW + deterministic validator"

formal-clean: ## Remove formal verification artifacts
	@rm -rf $(FORMAL_OUT)

formal-sva: formal-sva-control formal-sva-rf ## Run all SVA bounded model checks

formal-sva-control: ## Run control unit SVA checks (SymbiYosys)
	@if ! command -v $(SBY) >/dev/null 2>&1; then echo "ERROR: $(SBY) not found"; exit 2; fi
	@mkdir -p $(FORMAL_OUT)
	$(SBY) -f -d $(FORMAL_OUT)/control_unit_sva $(SVA_DIR)/control_unit_sva.sby

formal-sva-rf: ## Run register file temporal SVA checks (SymbiYosys)
	@if ! command -v $(SBY) >/dev/null 2>&1; then echo "ERROR: $(SBY) not found"; exit 2; fi
	@mkdir -p $(FORMAL_OUT)
	$(SBY) -f -d $(FORMAL_OUT)/register_file_sva $(SVA_DIR)/register_file_sva.sby

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

.PHONY: check-llvm install-backend build-backend setup-backend test-baremetal test-baremetal-deep compile-c

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

setup-backend: build-backend ## Full setup: clone, link, build
	@echo "✓ LX32 backend ready"

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




