module reg_file (
    input clk,
    input we,
    input [4:0] ra1, ra2, wa,
    input [31:0] wd,
    output [31:0] rd1, rd2
);
    parameter DEPTH = 32;
    reg [31:0] mem [0:31];
    always @(posedge clk) begin 
	    if (wa != 0 && we) begin 
		    mem[wa] <= wd;
	    end
    end
    /*
    property x_zero
    	@(posedge clk)
		0 == 0 |-> mem[0] == 32'b0;
    assert(x_zero) else $error("value in x0 is not 0");
    */
    assign rd1 = ra1 == 0 ? 0 : we && ra1 == wa ? wd : mem[ra1];
    assign rd2 = ra2 == 0 ? 0 : we && ra2 == wa ? wd : mem[ra2];
endmodule
