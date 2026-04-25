// Floating Point Multiplier
// IEEE 754 Single Precision

`include "fpu_pkg.v"

module fpu_mul (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    output reg         valid_out,
    output reg  [31:0] result,
    output reg         overflow,
    output reg         underflow
);

    // Internal signals
    reg sign_a, sign_b, sign_r;
    reg [7:0] exp_a, exp_b;
    reg [8:0] exp_sum;  // Extra bit for overflow
    reg [23:0] mant_a, mant_b;
    reg [47:0] mant_product;
    reg [7:0] exp_r;
    reg [22:0] mant_r;

    wire a_is_zero, b_is_zero;
    wire a_is_inf, b_is_inf;
    wire a_is_nan, b_is_nan;

    // Special case detection - BUG: NaN detection wrong
    assign a_is_zero = (operand_a[30:0] == 31'b0);
    assign b_is_zero = (operand_b[30:0] == 31'b0);
    assign a_is_inf = (operand_a[30:23] == 8'hFF) && (operand_a[22:0] == 23'b0);
    assign b_is_inf = (operand_b[30:23] == 8'hFF) && (operand_b[22:0] == 23'b0);
    // BUG: NaN check uses wrong condition
    assign a_is_nan = (operand_a[30:23] == 8'hFF) && (operand_a[22:0] != 23'b0);
    assign b_is_nan = (operand_b[30:23] == 8'hFF);  // BUG: incomplete

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            result <= 32'b0;
            overflow <= 1'b0;
            underflow <= 1'b0;
        end else if (valid_in) begin
            // Extract fields
            sign_a = operand_a[31];
            sign_b = operand_b[31];
            exp_a = operand_a[30:23];
            exp_b = operand_b[30:23];
            mant_a = {1'b1, operand_a[22:0]};
            mant_b = {1'b1, operand_b[22:0]};

            // Result sign - XOR of input signs
            sign_r = sign_a ^ sign_b;

            // Handle special cases
            if (a_is_nan || b_is_nan) begin
                // Return NaN - BUG: should be quiet NaN
                result <= 32'h7FC00000;
                valid_out <= 1'b1;
                overflow <= 1'b0;
                underflow <= 1'b0;
            end
            // BUG: Missing 0 * inf = NaN case
            else if (a_is_inf || b_is_inf) begin
                result <= {sign_r, 8'hFF, 23'b0};
                valid_out <= 1'b1;
                overflow <= 1'b1;  // BUG: inf is not really overflow
                underflow <= 1'b0;
            end
            else if (a_is_zero || b_is_zero) begin
                result <= {sign_r, 31'b0};
                valid_out <= 1'b1;
                overflow <= 1'b0;
                underflow <= 1'b0;
            end
            else begin
                // Normal multiplication
                // Add exponents - BUG: using wrong bias
                exp_sum = exp_a + exp_b - `EXP_BIAS;

                // Multiply mantissas
                mant_product = mant_a * mant_b;

                // Normalize - check if product overflowed into bit 47
                if (mant_product[47]) begin
                    // Shift right by 1, increment exponent
                    mant_r = mant_product[46:24];  // BUG: losing precision, no rounding
                    exp_r = exp_sum[7:0] + 1;
                end else begin
                    mant_r = mant_product[45:23];
                    exp_r = exp_sum[7:0];
                end

                // BUG: Not checking for overflow properly after adjustment
                if (exp_sum[8] && !exp_sum[7]) begin  // Positive overflow
                    overflow <= 1'b1;
                    underflow <= 1'b0;
                    result <= {sign_r, 8'hFF, 23'b0};
                end
                // BUG: Underflow check is wrong
                else if (exp_sum[8]) begin
                    overflow <= 1'b0;
                    underflow <= 1'b1;
                    result <= {sign_r, 31'b0};
                end
                else begin
                    overflow <= 1'b0;
                    underflow <= 1'b0;
                    result <= {sign_r, exp_r, mant_r};
                end

                valid_out <= 1'b1;
            end
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
