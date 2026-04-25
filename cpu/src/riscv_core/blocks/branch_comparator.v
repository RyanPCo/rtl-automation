module branch_comparator(
    input [31:0] reg1,  // First register value
    input [31:0] reg2,  // Second register value
    input BrUn,
    output BrEq,
	output BrLt
);

assign BrEq = (reg1 == reg2);
assign BrLt = BrUn ? (reg1 < reg2) : ($signed(reg1) < $signed(reg2));
endmodule

