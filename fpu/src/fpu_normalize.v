// Floating Point Normalizer
// Takes an unnormalized mantissa and adjusts exponent accordingly

`include "fpu_pkg.v"

module fpu_normalize (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire        sign_in,
    input  wire [7:0]  exp_in,
    input  wire [47:0] mant_in,  // Extended mantissa from multiplication
    output reg         valid_out,
    output reg         sign_out,
    output reg  [7:0]  exp_out,
    output reg  [22:0] mant_out,
    output reg         overflow,
    output reg         underflow
);

    reg [5:0] leading_zeros;
    reg [47:0] shifted_mant;
    reg [8:0] adjusted_exp;  // Extra bit for overflow detection

    integer i;

    // Leading zero counter - BUG: counts from wrong end
    always @(*) begin
        leading_zeros = 0;
        for (i = 0; i < 48; i = i + 1) begin
            if (mant_in[i] == 1'b0)  // BUG: should check from MSB, not LSB
                leading_zeros = leading_zeros + 1;
            else
                i = 48;  // Break - BUG: this doesn't actually break in Verilog
        end
    end

    // Normalization logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            sign_out <= 1'b0;
            exp_out <= 8'b0;
            mant_out <= 23'b0;
            overflow <= 1'b0;
            underflow <= 1'b0;
        end else if (valid_in) begin
            valid_out <= 1'b1;
            sign_out <= sign_in;

            // BUG: Not handling the case where mant_in is all zeros
            shifted_mant = mant_in << leading_zeros;

            // BUG: Wrong adjustment direction for exponent
            adjusted_exp = exp_in + leading_zeros;  // Should subtract

            // Check for overflow/underflow - BUG: wrong comparison
            if (adjusted_exp > 254) begin
                overflow <= 1'b1;
                exp_out <= 8'hFF;
                mant_out <= 23'b0;  // BUG: should set to max or inf
            end else if (adjusted_exp[8]) begin  // Negative
                underflow <= 1'b1;
                exp_out <= 8'b0;
                mant_out <= 23'b0;
            end else begin
                overflow <= 1'b0;
                underflow <= 1'b0;
                exp_out <= adjusted_exp[7:0];
                // BUG: extracting wrong bits from shifted mantissa
                mant_out <= shifted_mant[46:24];  // Should be [46:24] or similar based on format
            end
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
