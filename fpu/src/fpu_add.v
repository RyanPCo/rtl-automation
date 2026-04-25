// Floating Point Adder/Subtractor
// IEEE 754 Single Precision

`include "fpu_pkg.v"

module fpu_add (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire        op_sub,      // 0 = add, 1 = subtract
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    output reg         valid_out,
    output reg  [31:0] result,
    output reg         overflow,
    output reg         underflow
);

    // Internal signals
    reg sign_a, sign_b, sign_r;
    reg [7:0] exp_a, exp_b, exp_r, exp_diff;
    reg [23:0] mant_a, mant_b;  // With implicit 1
    reg [24:0] mant_r;          // Extra bit for overflow
    reg [23:0] mant_aligned;

    wire a_is_zero, b_is_zero;
    wire a_is_inf, b_is_inf;

    // Decode inputs
    assign a_is_zero = (operand_a[30:23] == 8'b0);
    assign b_is_zero = (operand_b[30:23] == 8'b0);
    // BUG: Missing mantissa check for infinity vs NaN
    assign a_is_inf = (operand_a[30:23] == 8'hFF);
    assign b_is_inf = (operand_b[30:23] == 8'hFF);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            result <= 32'b0;
            overflow <= 1'b0;
            underflow <= 1'b0;
        end else if (valid_in) begin
            // Extract fields
            sign_a = operand_a[31];
            sign_b = operand_b[31] ^ op_sub;  // Flip sign for subtraction
            exp_a = operand_a[30:23];
            exp_b = operand_b[30:23];

            // BUG: Not adding implicit 1 for denormalized numbers correctly
            mant_a = {1'b1, operand_a[22:0]};
            mant_b = {1'b1, operand_b[22:0]};

            // Align mantissas - BUG: comparison is backwards
            if (exp_a < exp_b) begin
                exp_diff = exp_b - exp_a;
                // BUG: shifting wrong operand
                mant_aligned = mant_b >> exp_diff;
                exp_r = exp_a;  // BUG: should use larger exponent

                // Add or subtract based on signs
                if (sign_a == sign_b) begin
                    mant_r = mant_a + mant_aligned;
                    sign_r = sign_a;
                end else begin
                    // BUG: wrong subtraction order
                    mant_r = mant_a - mant_aligned;
                    sign_r = sign_a;
                end
            end else begin
                exp_diff = exp_a - exp_b;
                mant_aligned = mant_b >> exp_diff;
                exp_r = exp_a;

                if (sign_a == sign_b) begin
                    mant_r = mant_a + mant_aligned;
                    sign_r = sign_a;
                end else begin
                    if (mant_a >= mant_aligned) begin
                        mant_r = mant_a - mant_aligned;
                        sign_r = sign_a;
                    end else begin
                        mant_r = mant_aligned - mant_a;
                        // BUG: sign should flip
                        sign_r = sign_a;
                    end
                end
            end

            // Normalize result - BUG: incomplete normalization
            if (mant_r[24]) begin
                // Overflow, shift right
                mant_r = mant_r >> 1;
                exp_r = exp_r + 1;
            end
            // BUG: Missing left shift normalization for small results

            // Check for overflow
            if (exp_r == 8'hFF) begin
                overflow <= 1'b1;
                result <= {sign_r, 8'hFF, 23'b0};
            end else begin
                overflow <= 1'b0;
                // BUG: Not handling underflow
                underflow <= 1'b0;
                result <= {sign_r, exp_r, mant_r[22:0]};
            end

            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
