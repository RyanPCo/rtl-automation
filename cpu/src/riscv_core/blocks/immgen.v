`include "inst_type.vh"

module immgen (
    input[2:0] immsel,
    input[24:0] inst,
    output reg[31:0] imm
);
    always @* begin
        case (immsel)
            `I_TYPE:  imm = {{20{inst[24]}}, inst[24:13]};
            `Is_TYPE: imm = {27'd0, inst[17:13]};
            `S_TYPE: imm = {{20{inst[24]}}, inst[24:18], inst[4:0]};
            `B_TYPE: imm = {{19{inst[24]}}, inst[24], inst[0], inst[23:18], inst[4:1], 1'd0};
            `U_TYPE: imm = {inst[24:5], 12'd0};
            `J_TYPE: imm = {{11{inst[24]}}, inst[24], inst[12:5], inst[13], inst[23:14], 1'd0};
            default: imm = {27'd0, inst[12:8]}; // C_TYPE
        endcase
    end
endmodule
