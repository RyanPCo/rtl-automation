module debouncer #(
    parameter WIDTH              = 1,
    parameter SAMPLE_CNT_MAX     = 62500,
    parameter PULSE_CNT_MAX      = 200,
    parameter WRAPPING_CNT_WIDTH = $clog2(SAMPLE_CNT_MAX),
    parameter SAT_CNT_WIDTH      = $clog2(PULSE_CNT_MAX) + 1
) (
    input clk,
    input [WIDTH-1:0] glitchy_signal,
    output [WIDTH-1:0] debounced_signal
);
    // TODO: Fill in the necessary logic to implement the wrapping counter and the saturating counters
    // Some initial code has been provided to you, but feel free to change it however you like
    // One global wrapping counter is required
    // One saturating counter is needed for each bit of glitchy_signal
    // You need to think of the conditions for resetting, clock enable, etc.
    // Refer to the block diagram in the spec

    // Remove this line once you create your debouncer
    reg [WRAPPING_CNT_WIDTH-1:0] wrap_cnt;
    wire sample_pulse_out;
    reg [SAT_CNT_WIDTH-1:0] saturating_counter [WIDTH-1:0];
    initial begin 
	    wrap_cnt = 0;
    end
    assign sample_pulse_out = (wrap_cnt == SAMPLE_CNT_MAX);
    always @(posedge clk) begin
	if (wrap_cnt == SAMPLE_CNT_MAX) begin
		wrap_cnt <= 0;
	end else begin
		wrap_cnt <= wrap_cnt + 1;
	end
    end

    genvar i;
    for (i = 0; i < WIDTH; i = i + 1) begin 
	    always @ (posedge clk) begin 
		    if (sample_pulse_out) begin
			    if(glitchy_signal[i]) begin
				    saturating_counter[i] <= saturating_counter[i] + 1;
			    end else begin 
				    saturating_counter[i] <= 0;
			    end
		    end
	    end
	    assign debounced_signal[i] = (saturating_counter[i] >= PULSE_CNT_MAX);
    end
endmodule
