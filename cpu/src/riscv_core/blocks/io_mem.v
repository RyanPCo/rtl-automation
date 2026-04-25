module io_mem #(
	parameter CPU_CLOCK_FREQ = 50_000_000,
	parameter SYSTEM_CLOCK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115200,
	parameter DWIDTH = 32
)(
	input clk,
	input system_clk,
	input rst,
	input[DWIDTH-1:0] addr,
	input [DWIDTH-1:0] d,
	input valid_inst,
	output [DWIDTH-1:0] q,
	input mem_we,
	input noop_exec,
	
	input serial_in,
    output serial_out,
	output machine_timer_interrupt,
	output uart_rx_overflow,
	output wire [399:0] ila_uart_rx_history
);
	// CLINT at 0x02000000, size 0x10000 (DTS). SiFive layout: mtimecmp@0x4000, mtime@0xBFF8
	localparam CLINT_BASE = 32'h0200_0000;
	localparam CLINT_MTIMECMP_LO = 32'h0200_4000;
	localparam CLINT_MTIMECMP_HI = 32'h0200_4004;
	localparam CLINT_MTIME_LO    = 32'h0200_BFF8;
	localparam CLINT_MTIME_HI    = 32'h0200_BFFC;

	wire clint_region = (addr[31:16] == 16'h0200);
	wire clint_mtimecmp_lo = clint_region & (addr == CLINT_MTIMECMP_LO);
	wire clint_mtimecmp_hi = clint_region & (addr == CLINT_MTIMECMP_HI);
	wire clint_mtime_lo    = clint_region & (addr == CLINT_MTIME_LO);
	wire clint_mtime_hi    = clint_region & (addr == CLINT_MTIME_HI);

	// mtime: 64-bit free-running counter at system_clk (100 MHz)
	wire [63:0] mtime_v;
	reg [63:0] mtime_n;
	REGISTER_R #(.N(64), .INIT(0)) mtime_reg(.d(mtime_n), .q(mtime_v), .clk(clk), .rst(rst));

	// mtimecmp: 64-bit compare register (writable); when mtime >= mtimecmp, timer interrupt
	wire [63:0] mtimecmp_v;
	reg [63:0] mtimecmp_n;
	REGISTER_R #(.N(64), .INIT(64'hFFFF_FFFF_FFFF_FFFF)) mtimecmp_reg(.d(mtimecmp_n), .q(mtimecmp_v), .clk(clk), .rst(rst));

	// Compare in clk domain using synchronized mtime (no cross-domain path)
	assign machine_timer_interrupt = (mtime_v >= mtimecmp_v);

	always @(*) begin
		mtime_n = mtime_v + 64'd1;
		mtimecmp_n = mtimecmp_v;
		if (clint_mtimecmp_lo & mem_we) mtimecmp_n[31:0]  = d;
		if (clint_mtimecmp_hi & mem_we) mtimecmp_n[63:32] = d;
	end

	// output designed to look like a register

	//// UART Receiver
    wire [7:0]             uart_rx_data_out;
    wire                   uart_rx_data_out_valid;
    reg                    uart_rx_data_out_ready;
    //// UART Transmitter
    reg [7:0]              uart_tx_data_in;
    reg                    uart_tx_data_in_valid;
    wire                   uart_tx_data_in_ready;
    uart #(.CLOCK_FREQ(CPU_CLOCK_FREQ),
           .SYSTEM_CLOCK_FREQ(SYSTEM_CLOCK_FREQ),
           .BAUD_RATE(BAUD_RATE))
    on_chip_uart (.clk(clk),
                  .reset(rst),
                  .system_clk(system_clk),
                  .serial_in(serial_in),
                  .data_out(uart_rx_data_out),
                  .data_out_valid(uart_rx_data_out_valid),
                  .data_out_ready(uart_rx_data_out_ready),
                  .serial_out(serial_out),
                  .uart_rx_overflow(uart_rx_overflow),
                  .ila_uart_rx_history(ila_uart_rx_history),
                  .data_in(uart_tx_data_in),
                  .data_in_valid(uart_tx_data_in_valid),
                  .data_in_ready(uart_tx_data_in_ready));

	wire [DWIDTH-1:0] cycle_counter_v;
	reg [DWIDTH-1:0] cycle_counter_n;
	REGISTER_R #(.N(DWIDTH), .INIT(0)) cycle_counter(.d(cycle_counter_n), .q(cycle_counter_v), .clk(clk), .rst(rst));

	wire [DWIDTH-1:0] inst_counter_v;
	reg [DWIDTH-1:0] inst_counter_n;
	REGISTER_R #(.N(DWIDTH), .INIT(1)) inst_counter(.d(inst_counter_n), .q(inst_counter_v), .clk(clk), .rst(rst));

	wire [DWIDTH-1:0] my_reg_out_v;
	reg [DWIDTH-1:0] my_reg_out_n;
	REGISTER_R #(.N(DWIDTH)) my_reg_out(.d(my_reg_out_n), .q(my_reg_out_v), .clk(clk), .rst(rst));

	wire out_sel_v; // choose between 0 - my reg value, or 1 - uart_rx_data_out
	reg out_sel_n; 
	REGISTER out_sel(.d(out_sel_n), .q(out_sel_v), .clk(clk));

	always @(*) begin
		my_reg_out_n = 32'd0;
		uart_tx_data_in = 8'd0;
		uart_rx_data_out_ready = 1'b0;
		uart_tx_data_in_valid = 1'b0;
		cycle_counter_n = cycle_counter_v + 1;
		inst_counter_n = valid_inst + inst_counter_v;
		out_sel_n = 1'b0;
		if (clint_region) begin
			// CLINT read: mtime and mtimecmp (64-bit, return low or high half)
			if (clint_mtimecmp_lo) my_reg_out_n = mtimecmp_v[31:0];
			else if (clint_mtimecmp_hi) my_reg_out_n = mtimecmp_v[63:32];
			else if (clint_mtime_lo) my_reg_out_n = mtime_v[31:0];
			else if (clint_mtime_hi) my_reg_out_n = mtime_v[63:32];
		end else if (addr[DWIDTH-1] == 1'b1) begin
			case (addr[5:2])
				4'b0000: begin
					// write is to holding register, read is from holding register
					if (mem_we) begin 
						uart_tx_data_in = d[7:0];
						uart_tx_data_in_valid = 1'b1;
					end
					else begin
						out_sel_n = 1'b1;
						uart_rx_data_out_ready = !noop_exec;
					end
				end
				4'b0101: begin
					my_reg_out_n = {26'd0, uart_tx_data_in_ready, 4'd0, uart_rx_data_out_valid};
				end
			endcase
		end
	end

	assign q = (out_sel_v) ? {{24{1'b0}}, uart_rx_data_out} : my_reg_out_v;
endmodule
