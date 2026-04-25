`ifndef ALU_SELS
`define ALU_SELS

`define ALU_ADD 5'd0
`define ALU_SLL 5'd1
`define ALU_SLT 5'd2
`define ALU_SLTU 5'd3
`define ALU_XOR 5'd4
`define ALU_SRL 5'd5
`define ALU_OR 5'd6
`define ALU_AND 5'd7
`define ALU_MUL 5'd8
`define ALU_MULH 5'd9
`define ALU_MULHSU 5'd10
`define ALU_MULHU 5'd11
`define ALU_a_sel 5'd12
`define ALU_SUB 5'd13
`define ALU_SRA 5'd14
`define ALU_b_sel 5'd15

`define FPU_OUT_FS1 2'b10
`define FPU_OUT_FS2 2'b11
`define FPU_OUT_SGN 2'b01
`define FPU_OUT_ALU 2'b00

`define FPU_OP_NOOP 2'b00
`define FPU_OP_CAST 2'b01
`define FPU_OP_ADD 2'b10
`define FPU_OP_MADD 2'b11

`endif