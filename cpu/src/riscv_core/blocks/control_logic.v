`include "opcode_custom.vh"
`include "opcode.vh"
`include "inst_type.vh"
`include "alu.vh"

module control_logic #(
  parameter DWIDTH = 32
) (
  input clk,
  input rst,
  input interrupt_pending,
  input [DWIDTH-1:0] inst,
  input br_eq,
  input br_lt,
  input [DWIDTH-1:0] pc,
  output funct2_1,
  output [2:0] funct3_1,
  output is_mult,
  output is_div_rem,
  output reg issue_m_ext,
  output div_signed,  // DIV/REM signed; DIVU/REMU unsigned
  output load_un,
  output reg pc_sel,
  output reg [2:0] imm_sel,
  output reg_we,
  output a_sel,
  output b_sel,
  output [1:0] alu_sel,
  output [1:0] wb_sel,
  output reg is_I_Type,
  output csr_en,
  output reg csr_set1, csr_clear1, csr_write1, csr_set2, csr_clear2, csr_write2,
  output reg [11:0] csr_addr2,
  output br_un,
  output [1:0] bhw_1, //0 is byte, 1 is hw, and 2 is w
  output [1:0] bhw_2, //0 is byte, 1 is hw, and 2 is w
  output mem_we,

  input [DWIDTH-1:0] alu_exec,
  input [DWIDTH-1:0] wb,
  output reg afwd_sel,
  output reg [DWIDTH-1:0] afwd_dout,
  output reg bfwd_sel,
  output reg [DWIDTH-1:0] bfwd_dout,
  output noop1,
  output is_load,

  output inst2_valid, 
  output reg stall,
  output reg skip_stall_wb,
  output reg add_bubble,

  // divider (M extension div/rem) — tready from IP, unused for now beyond wiring
  input div_divisor_tready,
  input div_dividend_tready,
  input m_ext_v,
  input m_ext_issued,           // pulse when M-extension unit accepts operands
  output reg [4:0] m_ext_inst_rd,
  output use_m_ext_inst_rd,

  output is_mret,
  output is_ecall,
  output reg noop1_n
);



wire [4:0] opcode;
assign opcode = inst[6:2];
wire is_I_Type0;
assign is_I_Type0 = (opcode == `OPCC_ARI_ITYPE);
wire [2:0] funct3;
wire funct2;
assign funct3 = inst[14:12];
assign funct2 = inst[30];
wire is_mult0;
assign is_mult0 = (opcode == `OPCC_ARI_RTYPE) && (inst[31:25] == `FNC7_MUL) && (funct3[2] == 1'b0); // mul*, not div/rem
// DIV/DIVU/REM/REMU: same opcode/funct7 as MUL, funct3 = 100..111
wire is_div_rem0;
assign is_div_rem0 = (opcode == `OPCC_ARI_RTYPE) && (inst[31:25] == `FNC7_MUL) && (funct3[2] == 1'b1);
wire div_signed0; // DIV, REM signed; DIVU, REMU unsigned
assign div_signed0 = !funct3[0]; // 100,110 signed; 101,111 unsigned

// INST TYPES
wire is_branch0, is_exec_res0, is_load0, is_jump0, uses_rs10, uses_rs20, is_store0, is_csr0, load_un0;
wire [1:0] bhw_0;
assign is_branch0 = opcode == `OPCC_BRANCH;
assign is_exec_res0 = opcode == `OPCC_ARI_ITYPE || opcode == `OPCC_ARI_RTYPE || opcode == `OPCC_LUI || opcode == `OPCC_AUIPC;
assign is_load0 = opcode == `OPCC_LOAD;
assign is_jump0 = opcode == `OPCC_JAL || opcode == `OPCC_JALR;
assign is_store0 = opcode == `OPCC_STORE;
assign uses_rs10 = (opcode != `OPCC_LUI && opcode != `OPCC_AUIPC && opcode != `OPCC_JAL);
assign uses_rs20 = opcode == `OPCC_ARI_RTYPE || opcode == `OPCC_BRANCH || opcode == `OPCC_STORE;
assign is_csr0 = opcode[4:2] == 3'b111;
// mret: opcode=SYSTEM(11100), funct3=000, funct7=0011000
wire is_mret0 = (opcode == `OPCC_CSR) && (funct3 == 3'b000) && (inst[31:25] == 7'b0011000);
wire is_ecall0 = (opcode == `OPCC_CSR) && (funct3 == 3'b000) && (inst[31:25] == 7'b0000000);
assign bhw_0 = funct3[1:0];
assign load_un0 = funct3[2]; // x for non load inst

wire is_branch1, is_exec_res1, is_load1, is_jump1, is_store1, is_csr1, load_un1;
REGISTER_R_CE is_branch_reg(.d(is_branch0), .q(is_branch1), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE is_exec_res_reg(.d(is_exec_res0), .q(is_exec_res1), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE is_load_reg(.d(is_load0), .q(is_load1), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE is_jump_reg(.d(is_jump0), .q(is_jump1), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE is_store_reg(.d(is_store0), .q(is_store1), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE is_csr_reg(.d(is_csr0), .q(is_csr1), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE #(.N(2)) bhw_1_reg(.d(bhw_0), .q(bhw_1), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE load_un_reg(.d(load_un0), .q(load_un1), .clk(clk), .rst(rst), .ce(!stall));

wire is_exec_res2, is_jump2, is_load2, is_csr2;
REGISTER_R_CE is_exec_res1_reg(.d(is_exec_res1), .q(is_exec_res2), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE is_load1_reg(.d(is_load1), .q(is_load2), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE is_jump1_reg(.d(is_jump1), .q(is_jump2), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE is_csr1_reg(.d(is_csr1), .q(is_csr2), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE load_un1_reg(.d(load_un1), .q(load_un), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE #(.N(2)) bhw_2_reg(.d(bhw_1), .q(bhw_2), .clk(clk), .rst(rst), .ce(!stall));

// OUTPUT CL EARLIER STAGES
reg [1:0] alu_sel0;
reg is_div_rem2;
REGISTER_R_CE #(.N(2)) alu_sel_reg(.d(alu_sel0), .q(alu_sel), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE #(.N(3)) funct3_reg(.d(funct3), .q(funct3_1), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE funct2_reg(.d(funct2), .q(funct2_1), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE is_mult_reg(.d(is_mult0), .q(is_mult), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE is_div_rem_reg(.d(is_div_rem0), .q(is_div_rem), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE is_div_rem2_reg(.d(is_div_rem), .q(is_div_rem2), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE div_signed_reg(.d(div_signed0), .q(div_signed), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE is_I_Type_reg(.d(is_I_Type0), .q(is_I_Type), .clk(clk), .rst(rst), .ce(!stall));

reg a_sel0, b_sel0;
REGISTER_R_CE a_sel_reg(.d(a_sel0), .q(a_sel), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE b_sel_reg(.d(b_sel0), .q(b_sel), .clk(clk), .rst(rst), .ce(!stall));
reg [1:0] wb_sel0, wb_sel1;
REGISTER_R_CE #(.N(2)) wb_sel_reg0(.d(wb_sel0), .q(wb_sel1), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE #(.N(2)) wb_sel_reg1(.d(skip_stall_wb ? 2'd1 : wb_sel1), .q(wb_sel), .clk(clk), .rst(rst), .ce(!stall || skip_stall_wb));
reg [2:0] branch_rel0, branch_rel1;
REGISTER_R_CE #(.N(3)) branch_rel_reg(.d(branch_rel0), .q(branch_rel1), .clk(clk), .rst(rst), .ce(!stall));

// NOOP STUFF

wire noop2;
reg noop2_n;
REGISTER_R_CE noop1_reg(.d(noop1_n), .q(noop1), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE noop2_reg(.d(noop2_n), .q(noop2), .clk(clk), .rst(rst), .ce(!stall));

wire [4:0] rd_1, rd_2;
reg [4:0] m_ext_inst_rd_1, m_ext_inst_rd_active;
REGISTER_R_CE #(.N(5)) rd1_reg(.d((is_branch0 || is_store0 || is_mret0 || is_ecall0) ? 5'd0 : inst[11:7]), .q(rd_1), .clk(clk), .rst(rst), .ce(!stall));
REGISTER_R_CE #(.N(5)) rd2_reg(.d(m_ext_v ? m_ext_inst_rd_active : rd_1), .q(rd_2), .clk(clk), .rst(rst), .ce(!stall || skip_stall_wb));
wire [4:0] rs1_0, rs2_0;
assign rs1_0 = inst[19:15];
assign rs2_0 = inst[24:20];

wire csr_set0, csr_clear0, csr_write0;
assign csr_set0 = funct3[1] & ~funct3[0];
assign csr_clear0 = funct3[1] & funct3[0];
assign csr_write0 = ~funct3[1] & funct3[0];
reg [11:0] csr_addr1;
always @(posedge clk) begin
  if (!stall) begin
    csr_set1 <= csr_set0;
    csr_clear1 <= csr_clear0;
    csr_write1 <= csr_write0;
    csr_set2 <= csr_set1;
    csr_clear2 <= csr_clear1;
    csr_write2 <= csr_write1;
    csr_addr1 <= inst[31:20];
    csr_addr2 <= csr_addr1;
  end
end

// simple outputs
assign mem_we = !noop1 && is_store1 && !stall;
assign br_un = funct3_1[1];

reg m_ext_v_d;
always @(posedge clk)
  m_ext_v_d <= m_ext_v;

assign reg_we = (!noop2 && (rd_2 != 5'd0) && !m_ext_v_d && (!stall || skip_stall_wb)) || (m_ext_v_d && m_ext_inst_rd != 5'd0);
assign csr_en = !noop2 && is_csr2;

assign is_load = is_load1;

// imm_gen logic
// function of opcode0, funct3_0 
always @(*) begin
    case (opcode)
      `OPCC_ARI_RTYPE: begin
        imm_sel = `R_TYPE;
      end
      `OPCC_ARI_ITYPE: begin
        imm_sel = (funct3 == `FNC_SLL || funct3 == `FNC_SRL_SRA) ? `Is_TYPE : `I_TYPE;
      end
      `OPCC_LOAD: begin
        imm_sel = `I_TYPE;
      end
      `OPCC_STORE: begin
        imm_sel = `S_TYPE;
      end
      `OPCC_AUIPC, `OPCC_LUI: imm_sel = `U_TYPE;
      `OPCC_BRANCH: begin
        imm_sel = `B_TYPE;
      end
      `OPCC_JALR: begin
        imm_sel = `I_TYPE;
      end
      `OPCC_JAL: begin
        imm_sel = `J_TYPE;
      end
      `OPCC_CSR: begin
        imm_sel = `C_TYPE;
      end
      default: imm_sel = `I_TYPE;
    endcase
end

always @(*) begin     
    case (opcode)
       `OPCC_ARI_ITYPE, `OPCC_ARI_RTYPE: alu_sel0 = 2'd3;
        `OPCC_LUI: alu_sel0 = 2'd0;
        `OPCC_CSR: alu_sel0 = {1'd0, !funct3[2]};
        default: alu_sel0 = 2'd2;
    endcase
end 

// a_sel, b_sel
always @(*) begin
  case (opcode)
    `OPCC_ARI_RTYPE: begin
      a_sel0 = 1;
      b_sel0 = 0;
    end
    `OPCC_ARI_ITYPE: begin
      a_sel0 = 1;
      b_sel0 = 1;
    end
    `OPCC_LOAD: begin
      a_sel0 = 1;
      b_sel0 = 1;
    end
    `OPCC_STORE: begin
      a_sel0 = 1;
      b_sel0 = 1;
    end
    `OPCC_AUIPC: begin
      a_sel0 = 0;
      b_sel0 = 1;
    end
    `OPCC_LUI: begin
      a_sel0 = 1'bx; // doesn't matter
      b_sel0 = 1; 
    end
    `OPCC_BRANCH: begin
      a_sel0 = 0;
      b_sel0 = 1;
    end
    `OPCC_JALR: begin
      a_sel0 = 1;
      b_sel0 = 1;
    end
    `OPCC_JAL: begin
      a_sel0 = 0;
      b_sel0 = 1;
    end
    `OPCC_CSR: begin
      a_sel0 = !funct3[2];
      b_sel0 = funct3[2];
    end
    default: begin
      a_sel0 = 1'b1;
      b_sel0 = 1'b1;  
    end
  endcase
end

// wb_sel, reg_we logic
always @(*) begin
  case (opcode)
    `OPCC_ARI_RTYPE, `OPCC_ARI_ITYPE, `OPCC_LUI, `OPCC_AUIPC: wb_sel0 = 1;
    `OPCC_LOAD: wb_sel0 = 2;
    `OPCC_CSR: wb_sel0 = 3;
    default: wb_sel0 = 0; // store, jumps
  endcase
end

// branch logic
always @(*) begin
  case (funct3) 
    `FNC_BLTU, `FNC_BLT: branch_rel0 = 3'b11x;
    `FNC_BEQ: branch_rel0 = 3'b0x1;
    `FNC_BNE: branch_rel0 = 3'b0x0;
    `FNC_BGE, `FNC_BGEU: branch_rel0 = 3'b10x;
    default: branch_rel0 = 3'bxxx;
  endcase
end

// Divider rd tracking
always @(posedge clk) begin
  m_ext_inst_rd <= m_ext_inst_rd_active;
  if ((is_div_rem0 || is_mult0) && !noop1_n)
    m_ext_inst_rd_1 <= inst[11:7];
  if (m_ext_issued)
    m_ext_inst_rd_active <= m_ext_inst_rd_1;
  if (rst | m_ext_v)
    m_ext_inst_rd_1 <= 5'd0;
  if (rst | m_ext_v)
    m_ext_inst_rd_active <= 5'd0;
end
assign use_m_ext_inst_rd = m_ext_v_d;

// noop and pc_sel logic
reg valid_branch;
reg m_ext_hazard, m_ext_axis_stall;
always @(*) begin
  noop2_n =  noop1;
  valid_branch = (!(branch_rel1[1] ^ br_lt) && branch_rel1[2]) || (!(branch_rel1[0] ^ br_eq) && !branch_rel1[2]);
  // M-extension busy: any instruction reading pending M-ext dest via int rs1/rs2 must stall
  m_ext_hazard = (m_ext_inst_rd_1 != 5'd0 && ((rs1_0 == m_ext_inst_rd_1 && uses_rs10) || (rs2_0 == m_ext_inst_rd_1 && uses_rs20))) ||
                 (m_ext_inst_rd_active != 5'd0 && ((rs1_0 == m_ext_inst_rd_active && uses_rs10) || (rs2_0 == m_ext_inst_rd_active && uses_rs20)));
  m_ext_axis_stall = (is_div_rem0 || is_mult0) && (m_ext_inst_rd_1 != 5'd0 || m_ext_inst_rd_active != 5'd0);
  add_bubble = (!noop1 && (is_load1 || is_csr1) && ((rs1_0 == rd_1 && uses_rs10) || (rs2_0 == rd_1 && uses_rs20)) && rd_1 != 5'd0) || m_ext_hazard || m_ext_axis_stall;
  noop1_n = (rst) ? 0 : (interrupt_pending || (opcode == `OPCC_FENCE_I) || (!noop1 && (is_jump1 || (valid_branch && is_branch1))) || add_bubble);
  pc_sel = !noop1 && (is_jump1 || (valid_branch && is_branch1));
end
assign is_mret = is_mret0 & !noop1_n;
assign is_ecall = is_ecall0 & !noop1_n;

// forwarding logic
reg a_hazard_1, b_hazard_1;
reg div_fu_not_ready;
always @(*) begin

    a_hazard_1 = !noop1 && (rs1_0 == rd_1) && (is_exec_res1);
    b_hazard_1 = !noop1 && (rs2_0 == rd_1) && (is_exec_res1);

    afwd_sel = (rs1_0 != 5'd0) && ((reg_we && (rs1_0 == rd_2) && (is_exec_res2 || is_load2 || is_jump2 || is_csr2)) || (m_ext_v_d && (rs1_0 == m_ext_inst_rd) && uses_rs10) || a_hazard_1);
    afwd_dout = (!a_hazard_1) ? wb : alu_exec;
    bfwd_sel = (rs2_0 != 5'd0) && ((reg_we && (rs2_0 == rd_2) && (is_exec_res2 || is_load2 || is_jump2 || is_csr2)) || (m_ext_v_d && (rs2_0 == m_ext_inst_rd) && uses_rs20) || b_hazard_1);
    bfwd_dout = (!b_hazard_1) ? wb : alu_exec;

    // Stall while divider path (for div/rem only) has no valid divisor path ready
    issue_m_ext = (is_div_rem || is_mult) && m_ext_inst_rd_active == 5'd0 && !noop1;
    div_fu_not_ready = is_div_rem && issue_m_ext && !(div_divisor_tready && div_dividend_tready);
    stall = m_ext_v || div_fu_not_ready;
    skip_stall_wb = m_ext_v;

  end

  reg inst2_valid_r;
  always @(posedge clk)
    inst2_valid_r <= !noop2 && !stall && !(skip_stall_wb && m_ext_v);
  assign inst2_valid = inst2_valid_r;

endmodule