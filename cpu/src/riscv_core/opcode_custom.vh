// List of RISC-V opcodes and funct codes.
// Use `include "opcode.vh" to use these in the decoder

`ifndef OPCODE_CUSTOM
`define OPCODE_CUSTOM


// ***** Opcodes *****
// CSR instructions
`define OPCC_CSR         5'b11100

// Fence instructions
`define OPCC_FENCE_I     5'b00111

// Special immediate instructions
`define OPCC_LUI         5'b01101
`define OPCC_AUIPC       5'b00101

// Jump instructions
`define OPCC_JAL         5'b11011
`define OPCC_JALR        5'b11001

// Branch instructions
`define OPCC_BRANCH      5'b11000

// Load and store instructions
`define OPCC_STORE       5'b01000
`define OPCC_LOAD        5'b00000

// Arithmetic instructions
`define OPCC_ARI_RTYPE   5'b01100
`define OPCC_ARI_ITYPE   5'b00100

`define OPCC_FPU_STORE 5'b01001
`define OPCC_FPU_LOAD 5'b00001

`define OPCC_FPU_FMADD 5'b10000
`define OPCC_FPU_REST 5'b10100

`define F7_FPU_FMVXW 7'b1110000

`endif //OPCODE
