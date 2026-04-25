// Floating Point Unit - Top Level
// IEEE 754 Single Precision
// Supports: ADD, SUB, MUL

`include "fpu_pkg.v"

module fpu_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [1:0]  operation,   // 00=add, 01=sub, 10=mul, 11=div(not implemented)
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    output wire        valid_out,
    output wire [31:0] result,
    output wire        overflow,
    output wire        underflow,
    output wire        invalid,     // Invalid operation (e.g., 0/0)
    output wire        ready        // Ready to accept new operation
);

    // Internal signals
    wire        add_valid_out, mul_valid_out;
    wire [31:0] add_result, mul_result;
    wire        add_overflow, mul_overflow;
    wire        add_underflow, mul_underflow;

    reg         valid_out_r;
    reg  [31:0] result_r;
    reg         overflow_r;
    reg         underflow_r;
    reg         invalid_r;

    // BUG: ready signal doesn't account for pipeline depth
    assign ready = 1'b1;

    // Instantiate adder
    fpu_add u_fpu_add (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_in && (operation == `FPU_OP_ADD || operation == `FPU_OP_SUB)),
        .op_sub     (operation[0]),
        .operand_a  (operand_a),
        .operand_b  (operand_b),
        .valid_out  (add_valid_out),
        .result     (add_result),
        .overflow   (add_overflow),
        .underflow  (add_underflow)
    );

    // Instantiate multiplier
    fpu_mul u_fpu_mul (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_in && (operation == `FPU_OP_MUL)),
        .operand_a  (operand_a),
        .operand_b  (operand_b),
        .valid_out  (mul_valid_out),
        .result     (mul_result),
        .overflow   (mul_overflow),
        .underflow  (mul_underflow)
    );

    // Output muxing - BUG: Race condition, not properly registering operation
    reg [1:0] op_delayed;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_delayed <= 2'b0;
        end else begin
            op_delayed <= operation;  // BUG: Should match pipeline depth
        end
    end

    // BUG: Mixing registered and combinational signals
    always @(*) begin
        case (op_delayed)
            `FPU_OP_ADD, `FPU_OP_SUB: begin
                valid_out_r = add_valid_out;
                result_r = add_result;
                overflow_r = add_overflow;
                underflow_r = add_underflow;
                invalid_r = 1'b0;
            end
            `FPU_OP_MUL: begin
                valid_out_r = mul_valid_out;
                result_r = mul_result;
                overflow_r = mul_overflow;
                underflow_r = mul_underflow;
                invalid_r = 1'b0;
            end
            `FPU_OP_DIV: begin
                // Division not implemented
                valid_out_r = valid_in;  // BUG: wrong timing
                result_r = 32'h7FC00000;  // NaN
                overflow_r = 1'b0;
                underflow_r = 1'b0;
                invalid_r = 1'b1;
            end
            default: begin
                valid_out_r = 1'b0;
                result_r = 32'b0;
                overflow_r = 1'b0;
                underflow_r = 1'b0;
                invalid_r = 1'b0;
            end
        endcase
    end

    assign valid_out = valid_out_r;
    assign result = result_r;
    assign overflow = overflow_r;
    assign underflow = underflow_r;
    assign invalid = invalid_r;

endmodule
