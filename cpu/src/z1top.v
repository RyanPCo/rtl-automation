module z1top #(
    parameter BAUD_RATE = 115_200,
    // Warning: CPU_CLOCK_FREQ must match the PLL parameters!
    parameter CPU_CLOCK_FREQ = 250_000_000,
    // PLL Parameters: sets the CPU clock = 100Mhz * 36 / 4 / 9 = 100 MHz
    parameter CPU_CLK_CLKFBOUT_MULT = 10,
    parameter CPU_CLK_DIVCLK_DIVIDE = 1,
    parameter CPU_CLK_CLKOUT_DIVIDE  = 4,
    
    /* verilator lint_off REALCVT */
    // Sample the button signal every 500us
    parameter integer B_SAMPLE_CNT_MAX = 0.0005 * CPU_CLOCK_FREQ,
    // The button is considered 'pressed' after 100ms of continuous pressing
    parameter integer B_PULSE_CNT_MAX = 0.100 / 0.0005,
    /* lint_on */
    // The PC the RISC-V CPU should start at after reset
    parameter RESET_PC = 32'h4000_0000
) (
    input CLK_100_P,
    input CLK_100_N,
    input [3:0] BUTTONS,
    input [7:0] SWITCHES,
    output [7:0] LEDS,
    input  FPGA_SERIAL_RX,
    output FPGA_SERIAL_TX
);

    wire CLK_100MHZ;
    `ifdef SYNTHESIS
    IBUFDS ibufds_clk (
        .I(CLK_100_P),
        .IB(CLK_100_N),
        .O(CLK_100MHZ)
    );
    `else
    assign CLK_100MHZ = CLK_100_P;
    `endif
    // Clocks and PLL lock status
    wire cpu_clk, cpu_clk_locked;

    // Buttons after the button_parser
    wire [3:0] buttons_pressed;

    // Switches after the synchronizer
    wire [7:0] switches_sync;

    // When buttons[0] goes high, hold reset for 64 cycles (on cpu_clk) so async FIFOs
    // and both clock domains see enough reset cycles.
    localparam RST_STRETCH = 64;
    reg [6:0] rst_count;
    always @(posedge cpu_clk) begin
        if (!cpu_clk_locked)
            rst_count <= RST_STRETCH;
        else if (buttons_pressed[0])
            rst_count <= RST_STRETCH;
        else if (rst_count != 0)
            rst_count <= rst_count - 1;
    end
    wire cpu_reset = (rst_count != 0) || !cpu_clk_locked;

    // Sync cpu_reset to CLK_100MHZ so IOB and UART (system_clk) see a clean reset
    reg cpu_reset_sync1, cpu_reset_sync;
    always @(posedge CLK_100MHZ) begin
        cpu_reset_sync1 <= cpu_reset;
        cpu_reset_sync   <= cpu_reset_sync1;
    end

    // Use IOBs; force serial lines to idle during reset so shell doesn't get stuck
    wire cpu_tx, cpu_rx;
    (* IOB = "true" *) reg fpga_serial_tx_iob;
    (* IOB = "true" *) reg fpga_serial_rx_iob;
    assign FPGA_SERIAL_TX = fpga_serial_tx_iob;
    assign cpu_rx = fpga_serial_rx_iob;
    always @(posedge CLK_100MHZ) begin
        if (cpu_reset_sync) begin
            fpga_serial_tx_iob <= 1'b1;
            fpga_serial_rx_iob <= 1'b1;
        end else begin
            fpga_serial_tx_iob <= cpu_tx;
            fpga_serial_rx_iob <= FPGA_SERIAL_RX;
        end
    end

    clocks #(
        .CPU_CLK_CLKFBOUT_MULT(CPU_CLK_CLKFBOUT_MULT),
        .CPU_CLK_DIVCLK_DIVIDE(CPU_CLK_DIVCLK_DIVIDE),
        .CPU_CLK_CLKOUT_DIVIDE(CPU_CLK_CLKOUT_DIVIDE)
    ) clk_gen (
        .clk_100mhz(CLK_100MHZ),
        .cpu_clk(cpu_clk),
        .cpu_clk_locked(cpu_clk_locked)
    );

    button_parser #(
        .WIDTH(4),
        .SAMPLE_CNT_MAX(B_SAMPLE_CNT_MAX),
        .PULSE_CNT_MAX(B_PULSE_CNT_MAX)
    ) bp (
        .clk(cpu_clk),
        .in(BUTTONS),
        .out(buttons_pressed)
    );

    synchronizer #(
        .WIDTH(8)
    ) switch_synchronizer (
        .clk(cpu_clk),
        .async_signal(SWITCHES),
        .sync_signal(switches_sync)
    );

    wire [2:0] cpu_error_vector;

    cpu #(
        .CPU_CLOCK_FREQ(CPU_CLOCK_FREQ),
        .SYSTEM_CLOCK_FREQ(100_000_000),
        .RESET_PC(RESET_PC),
        .BAUD_RATE(BAUD_RATE),
        .BIOS_MIF_HEX("../../software/bios/bios.hex")
    ) cpu (
        .clk(cpu_clk),
        .rst(cpu_reset),
        .system_clk(CLK_100MHZ),
        .bp_enable(switches_sync[0]),
        .serial_out(cpu_tx),
        .serial_in(cpu_rx),
        .error_vector(cpu_error_vector)
    );

    reg [2:0] error_vector;
    always @(posedge CLK_100MHZ) begin
        if (cpu_reset_sync)
            error_vector <= 1'b0;
        else
            error_vector <= error_vector | cpu_error_vector;
    end

    assign LEDS = {5'd0, error_vector[2:0]};
endmodule
