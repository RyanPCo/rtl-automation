# FPU Simulation Makefile for Icarus Verilog

# Directories
SRC_DIR = ../src
SIM_DIR = .

# Source files
SRC_FILES = $(SRC_DIR)/fpu_pkg.v \
            $(SRC_DIR)/fpu_normalize.v \
            $(SRC_DIR)/fpu_add.v \
            $(SRC_DIR)/fpu_mul.v \
            $(SRC_DIR)/fpu_top.v

# Compiler flags
IVERILOG = iverilog
VVP = vvp
IVFLAGS = -Wall -g2012

# Default target
.PHONY: all
all: test_top

# Run all tests
.PHONY: test
test: test_add test_mul test_top

# Top-level FPU test
.PHONY: test_top
test_top: fpu_top_sim
	$(VVP) fpu_top_sim

fpu_top_sim: $(SRC_FILES) tb_fpu_top.v
	$(IVERILOG) $(IVFLAGS) -I$(SRC_DIR) -o $@ $(SRC_FILES) tb_fpu_top.v

# Adder unit test
.PHONY: test_add
test_add: fpu_add_sim
	$(VVP) fpu_add_sim

fpu_add_sim: $(SRC_DIR)/fpu_pkg.v $(SRC_DIR)/fpu_add.v tb_fpu_add.v
	$(IVERILOG) $(IVFLAGS) -I$(SRC_DIR) -o $@ $(SRC_DIR)/fpu_pkg.v $(SRC_DIR)/fpu_add.v tb_fpu_add.v

# Multiplier unit test
.PHONY: test_mul
test_mul: fpu_mul_sim
	$(VVP) fpu_mul_sim

fpu_mul_sim: $(SRC_DIR)/fpu_pkg.v $(SRC_DIR)/fpu_mul.v tb_fpu_mul.v
	$(IVERILOG) $(IVFLAGS) -I$(SRC_DIR) -o $@ $(SRC_DIR)/fpu_pkg.v $(SRC_DIR)/fpu_mul.v tb_fpu_mul.v

# Compile only (no run)
.PHONY: compile
compile: fpu_top_sim fpu_add_sim fpu_mul_sim
	@echo "All modules compiled successfully"

# View waveforms (requires GTKWave)
.PHONY: wave
wave: test_top
	gtkwave fpu_sim.vcd &

.PHONY: wave_add
wave_add: test_add
	gtkwave fpu_add_sim.vcd &

.PHONY: wave_mul
wave_mul: test_mul
	gtkwave fpu_mul_sim.vcd &

# Lint check
.PHONY: lint
lint:
	$(IVERILOG) $(IVFLAGS) -I$(SRC_DIR) -o /dev/null $(SRC_FILES)
	@echo "Lint check passed"

# Clean
.PHONY: clean
clean:
	rm -f fpu_top_sim fpu_add_sim fpu_mul_sim
	rm -f *.vcd
	rm -f *.lxt *.lxt2
	rm -f *.fst

# Help
.PHONY: help
help:
	@echo "FPU Simulation Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all       - Build and run top-level test (default)"
	@echo "  test      - Run all tests"
	@echo "  test_top  - Run top-level FPU test"
	@echo "  test_add  - Run adder unit test"
	@echo "  test_mul  - Run multiplier unit test"
	@echo "  compile   - Compile all without running"
	@echo "  lint      - Check for syntax/lint errors"
	@echo "  wave      - Run test and open waveform viewer"
	@echo "  clean     - Remove generated files"
	@echo "  help      - Show this help"
