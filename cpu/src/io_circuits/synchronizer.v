module synchronizer #(parameter WIDTH = 1) (
    input [WIDTH-1:0] async_signal,
    input clk,
    output [WIDTH-1:0] sync_signal
);
    reg [WIDTH-1:0] ff1, ff2;

    always @(posedge clk) begin
	ff1 <= async_signal;
	ff2 <= ff1;
    end
    assign sync_signal = ff2;

endmodule
