// FPU Package - Common definitions
// IEEE 754 Single Precision Format

// BUG: Using wrong bias value (should be 127, not 128)
`define EXP_BIAS 128

// Format widths
`define FP_WIDTH 32
`define EXP_WIDTH 8
`define MANT_WIDTH 23

// Special values (some are wrong)
`define EXP_INF 8'hFF
`define EXP_ZERO 8'h00
// BUG: NaN check is incomplete - doesn't check mantissa
`define MANT_ZERO 23'h000000

// Operation codes
`define FPU_OP_ADD 2'b00
`define FPU_OP_SUB 2'b01
`define FPU_OP_MUL 2'b10
`define FPU_OP_DIV 2'b11
