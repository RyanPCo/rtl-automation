// Testbench for FPU Top Module
`timescale 1ns/1ps

module tb_fpu_top;

    // Clock and reset
    reg clk;
    reg rst_n;

    // DUT signals
    reg        valid_in;
    reg  [1:0] operation;
    reg [31:0] operand_a;
    reg [31:0] operand_b;
    wire       valid_out;
    wire[31:0] result;
    wire       overflow;
    wire       underflow;
    wire       invalid;
    wire       ready;

    // Test tracking
    integer test_count;
    integer pass_count;
    integer fail_count;

    // Expected values
    reg [31:0] expected_result;
    reg        expected_overflow;
    reg        expected_underflow;

    // Instantiate DUT
    fpu_top dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_in),
        .operation  (operation),
        .operand_a  (operand_a),
        .operand_b  (operand_b),
        .valid_out  (valid_out),
        .result     (result),
        .overflow   (overflow),
        .underflow  (underflow),
        .invalid    (invalid),
        .ready      (ready)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz clock
    end

    // Helper function to convert real to IEEE 754
    function [31:0] real_to_fp;
        input real value;
        reg [31:0] result;
        begin
            // This is a simplification - real conversion in Verilog
            result = $realtobits(value);
            real_to_fp = result[63:32];  // Take upper 32 bits (wrong for double)
        end
    endfunction

    // Helper function to display float value
    function real fp_to_real;
        input [31:0] fp_val;
        reg sign;
        reg [7:0] exp;
        reg [22:0] mant;
        real result;
        begin
            sign = fp_val[31];
            exp = fp_val[30:23];
            mant = fp_val[22:0];

            if (exp == 0 && mant == 0) begin
                result = 0.0;
            end else if (exp == 8'hFF) begin
                result = 1.0/0.0;  // Infinity (or NaN)
            end else begin
                result = (1.0 + (mant / (2.0**23))) * (2.0**(exp - 127));
                if (sign) result = -result;
            end
            fp_to_real = result;
        end
    endfunction

    // Test task
    task run_test;
        input [1:0] op;
        input [31:0] a;
        input [31:0] b;
        input [31:0] expected;
        input [127:0] test_name;
        begin
            test_count = test_count + 1;
            @(posedge clk);
            operation = op;
            operand_a = a;
            operand_b = b;
            valid_in = 1;
            @(posedge clk);
            valid_in = 0;

            // Wait for result
            @(posedge clk);
            while (!valid_out) @(posedge clk);

            // Check result
            if (result === expected) begin
                pass_count = pass_count + 1;
                $display("PASS: %s", test_name);
                $display("       A=%h (%f), B=%h (%f)", a, fp_to_real(a), b, fp_to_real(b));
                $display("       Result=%h (%f)", result, fp_to_real(result));
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %s", test_name);
                $display("       A=%h (%f), B=%h (%f)", a, fp_to_real(a), b, fp_to_real(b));
                $display("       Expected=%h (%f), Got=%h (%f)",
                         expected, fp_to_real(expected), result, fp_to_real(result));
            end
            $display("");
        end
    endtask

    // Main test sequence with parallel timeout
    initial begin
        // Setup waveform dump
        $dumpfile("fpu_sim.vcd");
        $dumpvars(0, tb_fpu_top);

        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        rst_n = 0;
        valid_in = 0;
        operation = 0;
        operand_a = 0;
        operand_b = 0;

        // Reset sequence
        #20;
        rst_n = 1;
        #20;

        fork
            begin : test_sequence
                $display("========================================");
                $display("FPU Testbench Starting");
                $display("========================================\n");

                // ============================================
                // Addition Tests
                // ============================================
                $display("--- Addition Tests ---\n");

                // Test 1: 1.0 + 1.0 = 2.0
                // 1.0 = 0x3F800000, 2.0 = 0x40000000
                run_test(2'b00, 32'h3F800000, 32'h3F800000, 32'h40000000, "1.0 + 1.0 = 2.0");

                // Test 2: 2.0 + 2.0 = 4.0
                // 2.0 = 0x40000000, 4.0 = 0x40800000
                run_test(2'b00, 32'h40000000, 32'h40000000, 32'h40800000, "2.0 + 2.0 = 4.0");

                // Test 3: 1.5 + 2.5 = 4.0
                // 1.5 = 0x3FC00000, 2.5 = 0x40200000, 4.0 = 0x40800000
                run_test(2'b00, 32'h3FC00000, 32'h40200000, 32'h40800000, "1.5 + 2.5 = 4.0");

                // Test 4: 100.0 + 0.01 (different magnitudes)
                // 100.0 = 0x42C80000, 0.01 = 0x3C23D70A, 100.01 = 0x42C80A3D
                run_test(2'b00, 32'h42C80000, 32'h3C23D70A, 32'h42C80A3D, "100.0 + 0.01 = 100.01");

                // Test 5: 0 + 5.0 = 5.0
                // 0 = 0x00000000, 5.0 = 0x40A00000
                run_test(2'b00, 32'h00000000, 32'h40A00000, 32'h40A00000, "0 + 5.0 = 5.0");

                // Test 6: -1.0 + 1.0 = 0
                // -1.0 = 0xBF800000, 1.0 = 0x3F800000
                run_test(2'b00, 32'hBF800000, 32'h3F800000, 32'h00000000, "-1.0 + 1.0 = 0");

                // ============================================
                // Subtraction Tests
                // ============================================
                $display("--- Subtraction Tests ---\n");

                // Test 7: 5.0 - 3.0 = 2.0
                // 5.0 = 0x40A00000, 3.0 = 0x40400000, 2.0 = 0x40000000
                run_test(2'b01, 32'h40A00000, 32'h40400000, 32'h40000000, "5.0 - 3.0 = 2.0");

                // Test 8: 3.0 - 5.0 = -2.0
                // 3.0 = 0x40400000, 5.0 = 0x40A00000, -2.0 = 0xC0000000
                run_test(2'b01, 32'h40400000, 32'h40A00000, 32'hC0000000, "3.0 - 5.0 = -2.0");

                // Test 9: 1.0 - 1.0 = 0
                run_test(2'b01, 32'h3F800000, 32'h3F800000, 32'h00000000, "1.0 - 1.0 = 0");

                // ============================================
                // Multiplication Tests
                // ============================================
                $display("--- Multiplication Tests ---\n");

                // Test 10: 2.0 * 3.0 = 6.0
                // 2.0 = 0x40000000, 3.0 = 0x40400000, 6.0 = 0x40C00000
                run_test(2'b10, 32'h40000000, 32'h40400000, 32'h40C00000, "2.0 * 3.0 = 6.0");

                // Test 11: 1.5 * 2.0 = 3.0
                // 1.5 = 0x3FC00000, 2.0 = 0x40000000, 3.0 = 0x40400000
                run_test(2'b10, 32'h3FC00000, 32'h40000000, 32'h40400000, "1.5 * 2.0 = 3.0");

                // Test 12: 0.5 * 0.5 = 0.25
                // 0.5 = 0x3F000000, 0.25 = 0x3E800000
                run_test(2'b10, 32'h3F000000, 32'h3F000000, 32'h3E800000, "0.5 * 0.5 = 0.25");

                // Test 13: -2.0 * 3.0 = -6.0
                // -2.0 = 0xC0000000, 3.0 = 0x40400000, -6.0 = 0xC0C00000
                run_test(2'b10, 32'hC0000000, 32'h40400000, 32'hC0C00000, "-2.0 * 3.0 = -6.0");

                // Test 14: 0 * 5.0 = 0
                run_test(2'b10, 32'h00000000, 32'h40A00000, 32'h00000000, "0 * 5.0 = 0");

                // Test 15: 1.0 * 1.0 = 1.0
                run_test(2'b10, 32'h3F800000, 32'h3F800000, 32'h3F800000, "1.0 * 1.0 = 1.0");

                // ============================================
                // Special Case Tests
                // ============================================
                $display("--- Special Case Tests ---\n");

                // Test 16: Infinity + 1.0 = Infinity
                run_test(2'b00, 32'h7F800000, 32'h3F800000, 32'h7F800000, "Inf + 1.0 = Inf");

                // Test 17: NaN + 1.0 = NaN
                run_test(2'b00, 32'h7FC00000, 32'h3F800000, 32'h7FC00000, "NaN + 1.0 = NaN");

                // Test 18: 0 * Infinity = NaN
                run_test(2'b10, 32'h00000000, 32'h7F800000, 32'h7FC00000, "0 * Inf = NaN");

                // ============================================
                // Summary
                // ============================================
                #100;
                $display("========================================");
                $display("Test Summary");
                $display("========================================");
                $display("Total Tests: %d", test_count);
                $display("Passed:      %d", pass_count);
                $display("Failed:      %d", fail_count);
                $display("========================================");

                if (fail_count > 0) begin
                    $display("SIMULATION FAILED - %d tests did not pass", fail_count);
                end else begin
                    $display("SIMULATION PASSED - All tests passed");
                end
            end

            begin : timeout_watchdog
                #100000;
                $display("ERROR: Simulation timeout after 100us!");
                $display("========================================");
                $display("Test Summary (TIMEOUT)");
                $display("========================================");
                $display("Total Tests: %d", test_count);
                $display("Passed:      %d", pass_count);
                $display("Failed:      %d", fail_count);
                $display("========================================");
            end
        join_any
        disable fork;
        $finish;
    end

endmodule
