#!/bin/bash
# FPU Simulation Runner Script

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

SRC_DIR="../src"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "FPU Simulation Runner"
echo "========================================"

# Check for Icarus Verilog
if ! command -v iverilog &> /dev/null; then
    echo -e "${RED}Error: iverilog not found. Please install Icarus Verilog.${NC}"
    echo "  macOS:  brew install icarus-verilog"
    echo "  Ubuntu: sudo apt install iverilog"
    exit 1
fi

# Parse arguments
TEST_NAME="${1:-all}"

run_test() {
    local name=$1
    local tb_file=$2
    local src_files=$3
    local out_file="${name}_sim"

    echo ""
    echo -e "${YELLOW}Running: $name${NC}"
    echo "----------------------------------------"

    # Compile
    echo "Compiling..."
    iverilog -Wall -g2012 -I${SRC_DIR} -o "$out_file" $src_files $tb_file

    if [ $? -ne 0 ]; then
        echo -e "${RED}Compilation failed!${NC}"
        return 1
    fi

    # Run
    echo "Simulating..."
    vvp "$out_file"

    if [ $? -ne 0 ]; then
        echo -e "${RED}Simulation failed!${NC}"
        return 1
    fi

    echo -e "${GREEN}Done: $name${NC}"
}

case "$TEST_NAME" in
    "add")
        run_test "fpu_add" "tb_fpu_add.v" "${SRC_DIR}/fpu_pkg.v ${SRC_DIR}/fpu_add.v"
        ;;
    "mul")
        run_test "fpu_mul" "tb_fpu_mul.v" "${SRC_DIR}/fpu_pkg.v ${SRC_DIR}/fpu_mul.v"
        ;;
    "top")
        run_test "fpu_top" "tb_fpu_top.v" "${SRC_DIR}/fpu_pkg.v ${SRC_DIR}/fpu_normalize.v ${SRC_DIR}/fpu_add.v ${SRC_DIR}/fpu_mul.v ${SRC_DIR}/fpu_top.v"
        ;;
    "all")
        run_test "fpu_add" "tb_fpu_add.v" "${SRC_DIR}/fpu_pkg.v ${SRC_DIR}/fpu_add.v"
        run_test "fpu_mul" "tb_fpu_mul.v" "${SRC_DIR}/fpu_pkg.v ${SRC_DIR}/fpu_mul.v"
        run_test "fpu_top" "tb_fpu_top.v" "${SRC_DIR}/fpu_pkg.v ${SRC_DIR}/fpu_normalize.v ${SRC_DIR}/fpu_add.v ${SRC_DIR}/fpu_mul.v ${SRC_DIR}/fpu_top.v"
        ;;
    *)
        echo "Usage: $0 [add|mul|top|all]"
        echo ""
        echo "Tests:"
        echo "  add  - Run FPU adder unit test"
        echo "  mul  - Run FPU multiplier unit test"
        echo "  top  - Run top-level FPU test"
        echo "  all  - Run all tests (default)"
        exit 1
        ;;
esac

echo ""
echo "========================================"
echo "Simulation complete"
echo "========================================"
