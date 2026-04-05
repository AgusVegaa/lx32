#!/bin/bash

# ==============================================================================
# LX32 Environment Setup & Verification Script
# Target: macOS & Linux (Unix-compatible)
# ==============================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# ANSI Color Codes for a professional terminal output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==> [1/4] Checking System Dependencies...${NC}"

# Check required tools for simulation, formal verification, and closure runs
required_tools=(verilator cargo coqc sby yosys z3 g++)
missing_tools=()
for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        missing_tools+=("$tool")
    fi
done

if [ ${#missing_tools[@]} -gt 0 ]; then
    echo -e "${BLUE}Missing tools detected: ${missing_tools[*]}${NC}"
    echo -e "${BLUE}Attempting automatic install...${NC}"

    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y verilator g++ coq yosys z3 cargo python3 git make
        if ! command -v sby &> /dev/null; then
            tmp_sby_dir="$(mktemp -d)"
            git clone --depth=1 https://github.com/YosysHQ/sby.git "$tmp_sby_dir/sby"
            sudo make -C "$tmp_sby_dir/sby" install
            rm -rf "$tmp_sby_dir"
        fi
    elif command -v brew &> /dev/null; then
        brew install verilator rust coq yosys z3 sby
    else
        echo -e "${RED}Error: no supported package manager found (apt-get/brew).${NC}"
        exit 1
    fi
fi

for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo -e "${RED}Error: '$tool' is still missing after auto-install attempt.${NC}"
        exit 1
    fi
done

# Determine Project Root (works regardless of where the script is called from)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Navigate to project root to execute Make commands
cd "$PROJECT_ROOT"

echo -e "${BLUE}==> [2/4] Generating RTL-to-Rust Bridge...${NC}"
# Generates the C++ headers and shared objects via Verilator
make librust

echo -e "${BLUE}==> [3/4] Compiling Rust Validator (Release Mode)...${NC}"
# Compiling the validator. Warnings are managed via Cargo.toml [lints]
cargo build --release --manifest-path tools/lx32_validator/Cargo.toml

echo -e "${BLUE}==> [4/4] Running Initial Validation Suite...${NC}"
# Executes the default test suite to ensure everything is wired correctly
make validate

echo -e "${GREEN}✨ Success! The LX32 environment is fully compiled and verified.${NC}"
echo -e "To explore more testing options, run: ${BLUE}make validate-help${NC}"
