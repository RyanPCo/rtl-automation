// Wraps div_gen_3 + AXI stream handshake and quotient/remainder packing for RISC-V M-extension
// div/rem. Exposes ready/busy/valid for control_logic stalling and 32-bit writeback data when done.
module riscv_divider (
  input  wire        clk,
  input  wire        rst,
  input  wire        stall,
  input  wire        is_div_rem,
  input  wire        is_mult,
  input  wire        issue_m_ext,
  input  wire        div_signed,   // DIV/REM vs DIVU/REMU
  input  wire [2:0]  funct3,       // bit2: REM/REMU vs DIV/DIVU (latched on issue)
  input  wire [31:0] rs1_val,      // dividend
  input  wire [31:0] rs2_val,      // divisor

  output wire        s_axis_divisor_tready,
  output wire        s_axis_dividend_tready,
  output wire        m_ext_v,      // pulsed when result valid (same cycle as wb data)
  output wire        m_ext_issued, // handshake accepted (div or mul)
  output wire [31:0] m_ext_wb_data // result for WB; valid when m_ext_v
);

  // 34-bit operands in low 34 bits of 40-bit AXI lanes
  wire        issue_div_rem = issue_m_ext && is_div_rem;
  wire [39:0] div_divisor_data;
  wire [39:0] div_dividend_data;
  assign div_dividend_data = div_signed ? {{6{rs1_val[31]}}, rs1_val} : {6'd0, rs1_val};
  assign div_divisor_data  = div_signed ? {{6{rs2_val[31]}}, rs2_val} : {6'd0, rs2_val};

  wire s_axis_divisor_tvalid;
  wire s_axis_dividend_tvalid;
  assign s_axis_divisor_tvalid  = issue_div_rem;
  assign s_axis_dividend_tvalid = issue_div_rem;
  wire div_issued = s_axis_divisor_tvalid && s_axis_divisor_tready &&
                    s_axis_dividend_tvalid && s_axis_dividend_tready;

  wire        m_axis_dout_tvalid;
  wire [79:0] m_axis_dout_tdata;
  wire [0:0]  m_axis_dout_tuser;

  // aresetn is ACTIVE LOW: 0 = reset, 1 = run. CPU rst is active high → invert.
  `ifdef IVERILOG

  div_gen_sim #(
    .WIDTH(34),
    .DIV_LATENCY(30)
  ) div_gen_sim_inst (
    .aclk(clk),
    .aresetn(~rst),
    .s_axis_divisor_tvalid(s_axis_divisor_tvalid),
    .s_axis_divisor_tready(s_axis_divisor_tready),
    .s_axis_divisor_tdata(div_divisor_data),
    .s_axis_dividend_tvalid(s_axis_dividend_tvalid),
    .s_axis_dividend_tready(s_axis_dividend_tready),
    .s_axis_dividend_tdata(div_dividend_data),
    .m_axis_dout_tvalid(m_axis_dout_tvalid),
    .m_axis_dout_tdata(m_axis_dout_tdata),
    .m_axis_dout_tuser(m_axis_dout_tuser)
  );
  `else
    div_gen_3 div_gen_3_inst (
    .aclk(clk),
    .aresetn(~rst),
    .s_axis_divisor_tvalid(s_axis_divisor_tvalid),
    .s_axis_divisor_tready(s_axis_divisor_tready),
    .s_axis_divisor_tdata(div_divisor_data),
    .s_axis_dividend_tvalid(s_axis_dividend_tvalid),
    .s_axis_dividend_tready(s_axis_dividend_tready),
    .s_axis_dividend_tdata(div_dividend_data),
    .m_axis_dout_tvalid(m_axis_dout_tvalid),
    .m_axis_dout_tdata(m_axis_dout_tdata),
    .m_axis_dout_tuser(m_axis_dout_tuser)
  );
  `endif

  // Byte-aligned 40+40 lanes; low 34 bits per field (PG151 remainder mode)
  wire [33:0] div_quotient_raw  = m_axis_dout_tdata[73:40];
  wire [33:0] div_remainder_raw = m_axis_dout_tdata[33:0];

  reg is_rem, is_rem_q;
  reg [31:0] dividend_q;
  always @(posedge clk) begin
    if (div_issued) begin
      is_rem_q <= funct3[1];
      dividend_q <= div_dividend_data[31:0];
    end
  end

  wire [33:0] div_result_wide = is_rem_q ? div_remainder_raw : div_quotient_raw;
  wire [31:0] div_wb_next = m_axis_dout_tuser[0] ? is_rem_q ? dividend_q : 32'hffffffff : div_result_wide[31:0];
  wire        div_v       = m_axis_dout_tvalid;

  // --------------------------------
  // Multiplier path (shared MUL ops)
  // --------------------------------

  wire issue_mul = issue_m_ext && is_mult;

  // Prepare signed/unsigned extended operands
  wire signed [63:0] mul_A_signed_ext = { {32{rs1_val[31]}}, rs1_val };
  wire       [63:0] mul_A_unsigned    = { 32'd0, rs1_val };
  wire signed [63:0] mul_B_signed_ext = { {32{rs2_val[31]}}, rs2_val };
  wire       [63:0] mul_B_unsigned    = { 32'd0, rs2_val };

  // Latch MUL mode at issue time
  reg  [2:0] mul_funct3_q;
  reg        mul_active_q;
  always @(posedge clk) begin
    if (rst) begin
      mul_funct3_q <= 3'd0;
      mul_active_q <= 1'b0;
    end else begin
      if (!stall && issue_mul) begin
        mul_funct3_q <= funct3;
        mul_active_q <= 1'b1;
      end
      // cleared when any M-extension result is reported as valid
      if (m_ext_v)
        mul_active_q <= 1'b0;
    end
  end

  // Operand mux for multiplier
  reg signed [63:0] mul_A_sel;
  reg signed [63:0] mul_B_sel;
  always @(*) begin
    case (mul_funct3_q)
      // MUL, MULH: signed × signed
      `FNC_MUL,
      `FNC_MULH: begin
        mul_A_sel = mul_A_signed_ext;
        mul_B_sel = mul_B_signed_ext;
      end
      // MULHSU: signed × unsigned
      `FNC_MULHSU: begin
        mul_A_sel = mul_A_signed_ext;
        mul_B_sel = mul_B_unsigned;
      end
      // MULHU: unsigned × unsigned
      `FNC_MULHU: begin
        mul_A_sel = mul_A_unsigned;
        mul_B_sel = mul_B_unsigned;
      end
      default: begin
        mul_A_sel = 64'd0;
        mul_B_sel = 64'd0;
      end
    endcase
  end

  // Registered multiplier inputs/outputs (single shared 32x32→64)
  reg signed [63:0] mul_A_reg, mul_B_reg;
  reg        [63:0] mul_result_reg;
  reg               mul_v;

  always @(posedge clk) begin
    if (rst) begin
      mul_A_reg     <= 64'd0;
      mul_B_reg     <= 64'd0;
      mul_result_reg <= 64'd0;
      mul_v     <= 1'b0;
    end else begin
      mul_v <= 1'b0;
      if (!stall && issue_mul) begin
        mul_A_reg      <= mul_A_sel;
        mul_B_reg      <= mul_B_sel;
      end
      if (!stall && mul_active_q) begin
        mul_result_reg <= mul_A_reg * mul_B_reg;
        mul_v      <= 1'b1;
      end
    end
  end

  reg [31:0] mul_wb_next;
  always @(*) begin
    case (mul_funct3_q)
      `FNC_MUL:    mul_wb_next = mul_result_reg[31:0];
      `FNC_MULH,
      `FNC_MULHSU,
      `FNC_MULHU:  mul_wb_next = mul_result_reg[63:32];
      default:     mul_wb_next = 32'd0;
    endcase
  end

  // Unified M-extension interface
  assign m_ext_issued  = div_issued | issue_mul;
  assign m_ext_v       = div_v | mul_v;
  assign m_ext_wb_data = div_v ? div_wb_next : mul_wb_next;

endmodule
