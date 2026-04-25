# File list for FPU simulation
# Use with: iverilog -f file_list.f -o fpu_sim

# Include paths
-I../src

# Source files
../src/fpu_pkg.v
../src/fpu_normalize.v
../src/fpu_add.v
../src/fpu_mul.v
../src/fpu_top.v

# Testbench
tb_fpu_top.v
