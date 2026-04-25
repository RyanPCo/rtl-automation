module edge_detector #(
    parameter WIDTH = 1
)(
    input clk,
    input [WIDTH-1:0] signal_in,
    output [WIDTH-1:0] edge_detect_pulse
);
    reg [WIDTH-1:0] flag, prev;
    always @(posedge clk) begin 
	    prev <= signal_in;
	    flag <= ~prev & signal_in;
    end
    assign edge_detect_pulse = flag;
endmodule
