`ifdef SYNTHESIS

module uart #(
    parameter CLOCK_FREQ = 125_000_000,
    parameter SYSTEM_CLOCK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115_200
) (
    input  wire        clk,
    input  wire        system_clk,
    input  wire        reset,

    input  wire  [7:0] data_in,
    input  wire        data_in_valid,
    output wire        data_in_ready,

    output wire  [7:0] data_out,
    output wire        data_out_valid,
    input  wire        data_out_ready,

    input  wire        serial_in,
    output wire        serial_out,
    output wire        uart_rx_overflow,
    output wire [399:0] ila_uart_rx_history
);
    reg serial_in_reg, serial_out_reg;
    wire serial_out_tx;
    assign serial_out = serial_out_reg;

    always @(posedge system_clk) begin
        if (reset) begin
            serial_out_reg <= 1'b1;
            serial_in_reg  <= 1'b1;
        end else begin
            serial_out_reg <= serial_out_tx;
            serial_in_reg  <= serial_in;
        end
    end

    wire tx_fifo_full, tx_fifo_empty, tx_fifo_rd_en, tx_wr_rst_busy, tx_rd_rst_busy;
    wire [7:0] tx_fifo_data_out;
    xpm_fifo_async #(
        .READ_DATA_WIDTH(8),
        .WRITE_DATA_WIDTH(8),
        .FIFO_WRITE_DEPTH(4096),
        .FIFO_READ_LATENCY(0),
        .READ_MODE("fwft")
    ) tx_fifo (
        .rst(reset),
        .wr_clk(clk),
        .wr_rst_busy(tx_wr_rst_busy),
        .wr_en(data_in_valid),
        .din(data_in),
        .full(tx_fifo_full),
        .rd_clk(system_clk),
        .rd_rst_busy(tx_rd_rst_busy),
        .rd_en(tx_fifo_rd_en),
        .dout(tx_fifo_data_out),
        .empty(tx_fifo_empty)
    );
    assign data_in_ready = !tx_fifo_full && !tx_wr_rst_busy;

    uart_transmitter #(
        .CLOCK_FREQ(SYSTEM_CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uatransmit (
        .clk(system_clk),
        .reset(reset),
        .data_in(tx_fifo_data_out),
        .data_in_valid(!tx_fifo_empty && !tx_rd_rst_busy),
        .data_in_ready(tx_fifo_rd_en),
        .serial_out(serial_out_tx)
    );

    wire rx_fifo_full, rx_fifo_empty, rx_fifo_wr_en, rx_wr_rst_busy, rx_rd_rst_busy;
    wire [7:0] rx_fifo_data_out;

    wire uart_rx_overflow_rx;

    uart_receiver #(
        .CLOCK_FREQ(SYSTEM_CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uareceive (
        .clk(system_clk),
        .reset(reset),
        .data_out(rx_fifo_data_out),
        .data_out_valid(rx_fifo_wr_en),
        .data_out_ready(!rx_fifo_full && !rx_wr_rst_busy),
        .uart_rx_overflow(uart_rx_overflow_rx),
        .serial_in(serial_in_reg)
    );

    // 50×8 shift: skip first 48 bytes accepted into RX FIFO, then capture; stop after 50 recorded; clear on reset.
    wire rx_fifo_accept = rx_fifo_wr_en && !rx_fifo_full && !rx_wr_rst_busy;
    reg [5:0] rx_skip;
    reg [5:0] rx_hist_count;
    reg [399:0] rx_hist_sr;
    always @(posedge system_clk) begin
        if (reset) begin
            rx_skip       <= 6'd48;
            rx_hist_count <= 6'd0;
            rx_hist_sr    <= 400'd0;
        end else if (rx_fifo_accept) begin
            if (rx_skip > 6'd0)
                rx_skip <= rx_skip - 6'd1;
            else if (rx_hist_count < 6'd50) begin
                rx_hist_sr    <= {rx_fifo_data_out, rx_hist_sr[399:8]};
                rx_hist_count <= rx_hist_count + 6'd1;
            end
        end
    end
    assign ila_uart_rx_history = rx_hist_sr;

    assign uart_rx_overflow = uart_rx_overflow_rx;

    xpm_fifo_async #(
        .READ_DATA_WIDTH(8),
        .WRITE_DATA_WIDTH(8),
        .FIFO_WRITE_DEPTH(4096),
        .FIFO_READ_LATENCY(0),
        .READ_MODE("fwft")
    ) rx_fifo (
        .rst(reset),
        .wr_clk(system_clk),
        .wr_rst_busy(rx_wr_rst_busy),
        .wr_en(rx_fifo_wr_en),
        .din(rx_fifo_data_out),
        .full(rx_fifo_full),
        .rd_clk(clk),
        .rd_rst_busy(rx_rd_rst_busy),
        .rd_en(data_out_ready),
        .dout(data_out),
        .empty(rx_fifo_empty)
    );
    assign data_out_valid = !rx_fifo_empty && !rx_rd_rst_busy;

endmodule

`else // SIMULATION

module uart #(
    parameter CLOCK_FREQ = 100_000_000,
    parameter BAUD_RATE  = 115_200
) (
    input  wire        clk,
    input  wire        system_clk,
    input  wire        reset,

    input  wire  [7:0] data_in,
    input  wire        data_in_valid,
    output wire        data_in_ready,

    output wire  [7:0] data_out,
    output wire        data_out_valid,
    input  wire        data_out_ready,

    input  wire        serial_in,
    output wire        serial_out,
    output wire        uart_rx_overflow,
    output wire [399:0] ila_uart_rx_history
);
    reg serial_in_reg, serial_out_reg;
    wire serial_out_tx;
    assign serial_out = serial_out_reg;

    always @(posedge clk) begin
        serial_out_reg <= reset ? 1'b1 : serial_out_tx;
        serial_in_reg  <= reset ? 1'b1 : serial_in;
    end

    uart_transmitter #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uatransmit (
        .clk(clk),
        .reset(reset),
        .data_in(data_in),
        .data_in_valid(data_in_valid),
        .data_in_ready(data_in_ready),
        .serial_out(serial_out_tx)
    );

    uart_receiver #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uareceive (
        .clk(clk),
        .reset(reset),
        .data_out(data_out),
        .data_out_valid(data_out_valid),
        .data_out_ready(data_out_ready),
        .uart_rx_overflow(uart_rx_overflow),
        .serial_in(serial_in_reg)
    );

    reg [5:0] rx_skip;
    reg [5:0] rx_hist_count;
    reg [399:0] rx_hist_sr;
    always @(posedge clk) begin
        if (reset) begin
            rx_skip       <= 6'd48;
            rx_hist_count <= 6'd0;
            rx_hist_sr    <= 400'd0;
        end else if (data_out_valid && data_out_ready) begin
            if (rx_skip > 6'd0)
                rx_skip <= rx_skip - 6'd1;
            else if (rx_hist_count < 6'd50) begin
                rx_hist_sr    <= {data_out, rx_hist_sr[399:8]};
                rx_hist_count <= rx_hist_count + 6'd1;
            end
        end
    end
    assign ila_uart_rx_history = rx_hist_sr;

endmodule

`endif
