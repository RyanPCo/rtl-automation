// Unit Testbench for FPU Multiplier
`timescale 1ns/1ps

module tb_fpu_mul;

    reg clk;
    reg rst_n;
    reg valid_in;
    reg [31:0] operand_a;
    reg [31:0] operand_b;
    wire valid_out;
    wire [31:0] result;
    wire overflow;
    wire underflow;

    integer errors;

    // DUT
    fpu_mul dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_in),
        .operand_a  (operand_a),
        .operand_b  (operand_b),
        .valid_out  (valid_out),
        .result     (result),
        .overflow   (overflow),
        .underflow  (underflow)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    task show_float;
        input [31:0] val;
        input [63:0] name;
        reg sign;
        reg [7:0] exp;
        reg [22:0] mant;
        begin
            sign = val[31];
            exp = val[30:23];
            mant = val[22:0];
            $display("  %s: 0x%08h (sign=%b, exp=%d, mant=0x%06h)",
                     name, val, sign, exp, mant);
        end
    endtask

    initial begin
        $dumpfile("fpu_mul_sim.vcd");
        $dumpvars(0, tb_fpu_mul);

        errors = 0;
        rst_n = 0;
        valid_in = 0;
        operand_a = 0;
        operand_b = 0;

        #25 rst_n = 1;
        #10;

        fork
            begin : test_sequence
                $display("\n=== FPU Multiplier Unit Test ===\n");

                // Test: 2.0 * 2.0
                $display("Test: 2.0 * 2.0 (expected: 4.0)");
                operand_a = 32'h40000000;  // 2.0
                operand_b = 32'h40000000;  // 2.0
                valid_in = 1;
                @(posedge clk);
                valid_in = 0;
                @(posedge clk);
                wait(valid_out);
                show_float(operand_a, "A");
                show_float(operand_b, "B");
                show_float(result, "Result");
                if (result !== 32'h40800000) begin
                    $display("  FAIL: Expected 0x40800000 (4.0)\n");
                    errors = errors + 1;
                end else begin
                    $display("  PASS\n");
                end
                #20;

                // Test: 3.0 * 4.0
                $display("Test: 3.0 * 4.0 (expected: 12.0)");
                operand_a = 32'h40400000;  // 3.0
                operand_b = 32'h40800000;  // 4.0
                valid_in = 1;
                @(posedge clk);
                valid_in = 0;
                @(posedge clk);
                wait(valid_out);
                show_float(operand_a, "A");
                show_float(operand_b, "B");
                show_float(result, "Result");
                if (result !== 32'h41400000) begin
                    $display("  FAIL: Expected 0x41400000 (12.0)\n");
                    errors = errors + 1;
                end else begin
                    $display("  PASS\n");
                end
                #20;

                // Test: 1.0 * 1.0
                $display("Test: 1.0 * 1.0 (expected: 1.0)");
                operand_a = 32'h3F800000;  // 1.0
                operand_b = 32'h3F800000;  // 1.0
                valid_in = 1;
                @(posedge clk);
                valid_in = 0;
                @(posedge clk);
                wait(valid_out);
                show_float(operand_a, "A");
                show_float(operand_b, "B");
                show_float(result, "Result");
                if (result !== 32'h3F800000) begin
                    $display("  FAIL: Expected 0x3F800000 (1.0)\n");
                    errors = errors + 1;
                end else begin
                    $display("  PASS\n");
                end
                #20;

                // Test: -2.0 * 3.0
                $display("Test: -2.0 * 3.0 (expected: -6.0)");
                operand_a = 32'hC0000000;  // -2.0
                operand_b = 32'h40400000;  // 3.0
                valid_in = 1;
                @(posedge clk);
                valid_in = 0;
                @(posedge clk);
                wait(valid_out);
                show_float(operand_a, "A");
                show_float(operand_b, "B");
                show_float(result, "Result");
                if (result !== 32'hC0C00000) begin
                    $display("  FAIL: Expected 0xC0C00000 (-6.0)\n");
                    errors = errors + 1;
                end else begin
                    $display("  PASS\n");
                end
                #20;

                // Test: 0.5 * 0.5
                $display("Test: 0.5 * 0.5 (expected: 0.25)");
                operand_a = 32'h3F000000;  // 0.5
                operand_b = 32'h3F000000;  // 0.5
                valid_in = 1;
                @(posedge clk);
                valid_in = 0;
                @(posedge clk);
                wait(valid_out);
                show_float(operand_a, "A");
                show_float(operand_b, "B");
                show_float(result, "Result");
                if (result !== 32'h3E800000) begin
                    $display("  FAIL: Expected 0x3E800000 (0.25)\n");
                    errors = errors + 1;
                end else begin
                    $display("  PASS\n");
                end

                #50;
                $display("=== Summary: %0d errors ===", errors);
            end

            begin : timeout_watchdog
                #50000;
                $display("\nERROR: Simulation timeout after 50us!");
                $display("=== Summary (TIMEOUT): %0d errors ===", errors);
            end
        join_any
        disable fork;
        $finish;
    end

endmodule
