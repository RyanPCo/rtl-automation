`include "alu.vh"
`include "opcode.vh"

module alu (
  input [31:0] A, B,
  input [1:0] ALUSel,
  input [2:0] funct3,
  input funct2,
  input is_I_Type,
  input [31:0] ApB,
  output reg [31:0] result
);

always @(*) begin
  case (ALUSel)
  //ALUSel will have 4 choices, 
    2'd0: result = B;
    2'd1: result = A;
    2'd2: result = ApB;
    2'd3: begin
        casez ({funct3, funct2, is_I_Type})
            {`FNC_ADD_SUB , `FNC2_ADD, 1'b0}: begin
              result = ApB;
            end
            {`FNC_ADD_SUB ,1'b?, 1'b1}: begin
              result = ApB;
            end
            {`FNC_ADD_SUB, `FNC2_SUB, 1'b0}: begin
              result = A - B;
            end
            {`FNC_SLL, 1'b?, 1'b?}: begin
              result = A << B[4:0];
            end
            {`FNC_SLT, 1'b?, 1'b?}: begin
              result = ($signed(A) < $signed(B)) ? 32'b1 : 32'b0;
            end                  
            {`FNC_SLTU, 1'b?, 1'b?}: begin
              result = (A < B) ? 32'b1 : 32'b0;
            end
            {`FNC_XOR, 1'b?, 1'b?}: begin
              result = A ^ B;
            end
            {`FNC_OR, 1'b?, 1'b?}: begin
              result = A | B;
            end
            {`FNC_AND, 1'b?, 1'b?}: begin
              result = A & B;
            end
            {`FNC_SRL_SRA, `FNC2_SRL, 1'b?}: begin
              result = A >> B[4:0];
            end
            {`FNC_SRL_SRA, `FNC2_SRA, 1'b?}: begin
              result = $signed(A) >>> B[4:0];
            end
            default: result = 32'd0;
        endcase
      end
  endcase
end 
endmodule
