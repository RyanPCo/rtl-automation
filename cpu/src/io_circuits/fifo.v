module fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 32,
    parameter POINTER_WIDTH = $clog2(DEPTH)
) (
    input clk, rst,

    // Write side
    input wr_en,
    input [WIDTH-1:0] din,
    output full,

    // Read side
    input rd_en,
    output [WIDTH-1:0] dout,
    output empty
);


    reg [WIDTH-1:0] memory [DEPTH-1:0];
    reg [POINTER_WIDTH:0] left_ptr;
    reg [POINTER_WIDTH:0] right_ptr;
    reg [WIDTH-1:0] dout_reg;
    assign dout = dout_reg;

    always @(posedge clk) begin 
	    if (rst) begin
		    left_ptr <= 0;
		    right_ptr <= 0;
		    dout_reg <= 0;
	    end else begin 
		    if (!full && wr_en) begin 
			    memory[left_ptr[POINTER_WIDTH-1:0]] <= din;
			    left_ptr <= left_ptr + 1;
		    end 
		    if (!empty && rd_en) begin 
			    dout_reg <= memory[right_ptr[POINTER_WIDTH-1:0]];
			    right_ptr <= right_ptr + 1;
		    end
	    end
    end
    assign full = (left_ptr[POINTER_WIDTH] != right_ptr[POINTER_WIDTH]) && (left_ptr[POINTER_WIDTH-1:0] == right_ptr[POINTER_WIDTH-1:0]);
    assign empty = (left_ptr == right_ptr);
    /*
    proprety1: assert property( @(posedge clk) disable iff(rst) wr_en && full |-> left_ptr == $past(left_ptr, 1));
    property2: assert property( @(posedge clk) disable iff(rst) rd_en && empty |-> right_ptr == $past(right_ptr, 1));
    property3: assert property( @(posedge clk) rst |-> ##1 ~right_ptr && ~left_ptr && ~full);
    */
endmodule
