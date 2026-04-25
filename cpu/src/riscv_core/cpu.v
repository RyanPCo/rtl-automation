`define STRINGIFY_BIOS(x) `"x/../software/bios/bios.hex`"

module cpu #(
    parameter CPU_CLOCK_FREQ = 50_000_000,
    parameter SYSTEM_CLOCK_FREQ = 100_000_000,
    parameter RESET_PC = 32'h4000_0000,
    parameter BAUD_RATE = 115200,
    parameter BIOS_MIF_HEX = `STRINGIFY_BIOS(`ABS_TOP)
) (
    input clk,
    input system_clk,
    input rst,
    input bp_enable,
    input serial_in,
    output serial_out,
    output [2:0] error_vector
);

   localparam DWIDTH = 32;
   localparam BEWIDTH = DWIDTH / 8;

   // BIOS Memory
   // Synchronous read: read takes one cycle
   // Synchronous write: write takes one cycle
   localparam BIOS_AWIDTH = 14;
   wire [BIOS_AWIDTH-1:0] bios_addra, bios_addrb;
   wire [DWIDTH-1:0]      bios_douta, bios_doutb;
   wire                   bios_ena, bios_enb;
   SYNC_ROM_DP #(.AWIDTH(BIOS_AWIDTH),
                 .DWIDTH(DWIDTH),
                 .MIF_HEX(BIOS_MIF_HEX))
   bios_mem(.q0(bios_douta),
            .addr0(bios_addra),
            .en0(bios_ena),
            .q1(bios_doutb),
            .addr1(bios_addrb),
            .en1(bios_enb),
            .clk(clk));

   // Data Memory
   // Synchronous read: read takes one cycle
   // Synchronous write: write takes one cycle
   // Write-byte-enable: select which of the four bytes to write
   localparam DMEM_AWIDTH = 15;
   wire [DMEM_AWIDTH-1:0] dmem_addra;
   wire [DWIDTH-1:0]      dmem_dina, dmem_douta;
   wire [BEWIDTH-1:0]     dmem_wbea;
   wire                   dmem_ena;
   SYNC_RAM_WBE #(.AWIDTH(DMEM_AWIDTH),
                  .DWIDTH(DWIDTH))
   dmem (.q(dmem_douta),
         .d(dmem_dina),
         .addr(dmem_addra),
         .wbe(dmem_wbea),
         .en(dmem_ena),
         .clk(clk));

   // Instruction Memory
   // Synchronous read: read takes one cycle
   // Synchronous write: write takes one cycle
   // Write-byte-enable: select which of the four bytes to write
   localparam IMEM_AWIDTH = 15;
   wire [IMEM_AWIDTH-1:0] imem_addra, imem_addrb;
   wire [DWIDTH-1:0]      imem_douta, imem_doutb;
   wire [DWIDTH-1:0]      imem_dina, imem_dinb;
   wire [BEWIDTH-1:0]       imem_wbea, imem_wbeb;
   wire                   imem_ena, imem_enb;
   SYNC_RAM_DP_WBE #(.AWIDTH(IMEM_AWIDTH),
                     .DWIDTH(DWIDTH))
   imem (.q0(imem_douta),
         .d0(imem_dina),
         .addr0(imem_addra),
         .wbe0(imem_wbea),
         .en0(imem_ena),
         .q1(imem_doutb),
         .d1(imem_dinb),
         .addr1(imem_addrb),
         .wbe1(imem_wbeb),
         .en1(imem_enb),
         .clk(clk));

   // Register file
   // Asynchronous read: read data is available in the same cycle
   // Synchronous write: write takes one cycle
   localparam RF_AWIDTH = 5;
   wire [RF_AWIDTH-1:0]   wa, ra1, ra2;
   wire [DWIDTH-1:0]      wd, rd1, rd2;
   wire                   we;
   ASYNC_RAM_1W2R # (.AWIDTH(RF_AWIDTH),
                     .DWIDTH(DWIDTH))
   rf (.addr0(wa),
       .d0(wd),
       .we0(we),
       .q1(rd1),
       .addr1(ra1),
       .q2(rd2),
       .addr2(ra2),
       .clk(clk));

  wire is_load;

   // UART and Counters
   // TODO: Instruction counter
   wire [DWIDTH-1:0] uart_addr, uart_din, uart_dout;
   wire uart_mem_we, valid_inst, noop_exec;
   wire machine_timer_interrupt;
   wire uart_rx_overflow;
   wire [399:0] uart_rx_ila_hist;
   reg [399:0] uart_rx_ila_hist_cdc;
   always @(posedge clk) uart_rx_ila_hist_cdc <= uart_rx_ila_hist;

   io_mem #(.CPU_CLOCK_FREQ(CPU_CLOCK_FREQ), .SYSTEM_CLOCK_FREQ(SYSTEM_CLOCK_FREQ), .BAUD_RATE(BAUD_RATE), .DWIDTH(DWIDTH)) 
        im (
            .clk(clk),
            .rst(rst),
            .system_clk(system_clk),
            .addr(uart_addr),
            .d(uart_din),
            .valid_inst(valid_inst),
            .q(uart_dout),
            .serial_in(serial_in),
            .serial_out(serial_out),
            .uart_rx_overflow(uart_rx_overflow),
            .ila_uart_rx_history(uart_rx_ila_hist),
            .mem_we(uart_mem_we),
            .noop_exec(noop_exec || !is_load),
            .machine_timer_interrupt(machine_timer_interrupt)
        );

   wire [DWIDTH-1:0] csr_dout;
   wire interrupt_pending;
   wire [31:0] mtvec;
   // Mask interrupt during M-extension ops: don't accept interrupt from m_ext_issued until m_ext_v
   reg div_busy;
   wire interrupt_pending_masked = interrupt_pending & ~div_busy;
   wire [31:0] mepc;

   // TODO: Your code to implement a fully functioning RISC-V core
   // Add as many modules as you want
   // Feel free to move the memory modules around

   reg [31:0] pc;

   // Instruction fetch is only defined for IMEM (0x1xxx_xxxx) and BIOS (0x4xxx_xxxx)
   wire invalid_pc = !((pc[31:28] == 4'h1) || (pc[31:28] == 4'h4));
   wire [31:0] ApB;
   wire mem_we;

   // DMEM is only implemented for a small window within the DMEM region; flag accesses outside it.
   wire dmem_region = (ApB[31:28] == 4'h1) || (ApB[31:28] == 4'h3);
   wire dmem_access = dmem_region && (mem_we || is_load) && !noop_exec;
   wire invalid_dmem_addr = dmem_access && (|ApB[27:DMEM_AWIDTH+2]);

   assign error_vector[0] = uart_rx_overflow;
   assign error_vector[1] = invalid_pc;
   assign error_vector[2] = invalid_dmem_addr;

    reg [DWIDTH-1:0] inst, pc_n, pc_p4, pc_exec, pc_mem, pc_mem_p4;
    assign pc_p4 = pc + 4;
    assign pc_mem_p4 = pc_mem + 4;

    wire stall, add_bubble;

    // M-extension wrapper: busy/valid and AXI stream ready (fed into control for stall/hazard)
    wire div_divisor_tready, div_dividend_tready;
    wire m_ext_v;
    wire m_ext_issued;
    wire [4:0] m_ext_inst_rd;
    wire use_m_ext_inst_rd;

    wire br_eq, br_lt, reg_we, a_sel, b_sel, csr_en, csr_set1, csr_clear1, csr_write1, csr_set2, csr_clear2, csr_write2, br_un, load_un, pc_sel, is_mret, is_ecall;
    wire [11:0] csr_addr;
    wire [1:0] bhw_1, bhw_2, wb_sel;
    wire [2:0] imm_sel;
    wire [1:0] alu_sel;
    wire [2:0] funct3;
    wire funct2;
    wire is_mult, is_div_rem, div_signed, issue_m_ext;
    wire is_I_Type;
    reg [31:0] alu_a, alu_b;
    wire [31:0] alu_res, afwd_dout, bfwd_dout;
    wire afwd_sel, bfwd_sel;
    
    reg [DWIDTH-1:0] wb;
    wire skip_stall_wb;

    control_logic cl (
        .clk(clk),
        .rst(rst),
        .interrupt_pending(interrupt_pending_masked),
        .inst(inst),
        .br_eq(br_eq),
        .br_lt(br_lt),
        .pc(pc),

        .pc_sel(pc_sel),
        .imm_sel(imm_sel),
        .reg_we(reg_we),
        .a_sel(a_sel),
        .b_sel(b_sel),
        .alu_sel(alu_sel),
        .funct3_1(funct3),
        .funct2_1(funct2),
        .is_mult(is_mult),
        .is_div_rem(is_div_rem),
        .issue_m_ext(issue_m_ext),
        .div_signed(div_signed),
        .is_I_Type(is_I_Type),
        .wb_sel(wb_sel),
        .csr_en(csr_en),
        .csr_set1(csr_set1),
        .csr_clear1(csr_clear1),
        .csr_write1(csr_write1),
        .csr_set2(csr_set2),
        .csr_clear2(csr_clear2),
        .csr_write2(csr_write2),
        .csr_addr2(csr_addr),
        .br_un(br_un),
        .mem_we(mem_we),
        .bhw_1(bhw_1),
        .bhw_2(bhw_2),
        .load_un(load_un),

        .alu_exec(alu_res),
        .wb(wb),
        .afwd_sel(afwd_sel),
        .afwd_dout(afwd_dout),
        .bfwd_sel(bfwd_sel),
        .bfwd_dout(bfwd_dout),
        .noop1(noop_exec),
        .is_load(is_load),

        .inst2_valid(valid_inst),
        .stall(stall),
        .skip_stall_wb(skip_stall_wb),
        .add_bubble(add_bubble),

        .is_mret(is_mret),
        .is_ecall(is_ecall),

        .div_divisor_tready(div_divisor_tready),
        .div_dividend_tready(div_dividend_tready),
        .m_ext_v(m_ext_v),
        .m_ext_issued(m_ext_issued),
        .m_ext_inst_rd(m_ext_inst_rd),
        .use_m_ext_inst_rd(use_m_ext_inst_rd)
    );

    assign ApB = alu_a + alu_b;

    wire [DWIDTH-1:0] rd1_exec, rd2_exec, imm_exec;
    wire [31:0] imm;
    immgen igen(
        .immsel(imm_sel),
        .inst(inst[31:7]),
        .imm(imm)
    );

    alu cpu_alu(
        .A(alu_a),
        .B(alu_b),
        .ALUSel(alu_sel),
        .funct2(funct2),
        .funct3(funct3),
        .is_I_Type(is_I_Type),
        .ApB(ApB),
        .result(alu_res)
    );

    wire [31:0] m_ext_wb_data;
    riscv_divider u_riscv_divider (
      .clk(clk),
      .rst(rst),
      .stall(stall),
      .is_div_rem(is_div_rem),
      .is_mult(is_mult),
      .issue_m_ext(issue_m_ext),
      .div_signed(div_signed),
      .funct3(funct3),
      .rs1_val(rd1_exec),
      .rs2_val(rd2_exec),
      .s_axis_divisor_tready(div_divisor_tready),
      .s_axis_dividend_tready(div_dividend_tready),
      .m_ext_v(m_ext_v),
      .m_ext_issued(m_ext_issued),
      .m_ext_wb_data(m_ext_wb_data)
    );

    always @(posedge clk) begin
      if (rst)            div_busy <= 1'b0;
      else if (m_ext_issued) div_busy <= 1'b1;
      else if (m_ext_v)      div_busy <= 1'b0;
    end
    
    // PC REG and PC MUX
    REGISTER_R_CE #(.N(DWIDTH), .INIT(RESET_PC)) PC_REG (.d(pc_n), .q(pc), .clk(clk), .rst(rst), .ce(1'b1));
    always @(*) begin
        case (pc_sel) 
            1'b0: pc_n = pc_p4;
            1'b1: pc_n = alu_a + imm_exec;
            default: pc_n = RESET_PC;
        endcase
        if (stall || add_bubble) begin
            pc_n = pc;
        end
        if (rst) begin
            pc_n = RESET_PC;
        end
        if (interrupt_pending_masked & ~pc_sel) begin
            pc_n = {mtvec[31:2], 2'b00};  // trap vector base (mtvec[1:0] is mode)
        end
        if (is_mret & ~pc_sel) begin
            pc_n = mepc;  // return from trap handler
        end
        if (is_ecall & ~pc_sel) begin
            pc_n = {mtvec[31:2], 2'b00};  // trap to mtvec (environment call)
        end
    end

    assign imem_dina = 32'b0;
    assign imem_addra = pc_n[IMEM_AWIDTH+1:2];
    assign imem_ena = !stall || rst;
    assign imem_wbea = 4'b0;

    assign bios_addra = pc_n[BIOS_AWIDTH+1:2];
    assign bios_ena = !stall || rst;

    // inst mux
    always @(*) begin
        case (pc[30])
            1'b0: inst = imem_douta;
            1'b1: inst = bios_douta;
        endcase
    end

    // regfile
    wire [RF_AWIDTH-1:0] wa_int, wa_pipe;
    REGISTER_R_CE #(.N(RF_AWIDTH)) wa1(.d(inst[11:7]), .q(wa_int), .clk(clk), .rst(rst), .ce(!stall));
    REGISTER_R_CE #(.N(RF_AWIDTH)) wa2(.d(wa_int), .q(wa_pipe), .clk(clk), .rst(rst), .ce(!stall));
    assign wa = use_m_ext_inst_rd ? m_ext_inst_rd : wa_pipe;
    assign ra1 = inst[19:15];
    assign ra2 = inst[24:20];
    assign we = reg_we;

    // exec stage pipelining
    reg [DWIDTH-1:0] rd1_exec_n, rd2_exec_n;
    always @(*) begin
        case (afwd_sel)
            1'b0: rd1_exec_n = rd1;
            1'b1: rd1_exec_n = afwd_dout;
        endcase
        case (bfwd_sel)
            1'b0: rd2_exec_n = rd2;
            1'b1: rd2_exec_n = bfwd_dout;
        endcase
    end

    REGISTER_R_CE #(.N(DWIDTH)) rd1_reg(
        .d(rd1_exec_n), 
        .q(rd1_exec), 
        .clk(clk),
        .rst(rst),
        .ce(!stall));
    REGISTER_R_CE #(.N(DWIDTH)) rd2_reg(
        .d(rd2_exec_n), 
        .q(rd2_exec), 
        .clk(clk),
        .rst(rst),
        .ce(!stall));
    REGISTER_R_CE #(.N(DWIDTH)) imm_reg(.d(imm), .q(imm_exec), .clk(clk), .rst(rst), .ce(!stall));
    REGISTER_R_CE #(.N(DWIDTH)) pc_exec_reg(.d(pc), .q(pc_exec), .clk(clk), .rst(rst), .ce(!stall));

    // TODO Forwarding MUXes

    // A Sel mux
    always @(*) begin
        case (a_sel)
            1'b0: alu_a = pc_exec;
            1'b1: alu_a = rd1_exec;
        endcase
        case (b_sel)
            1'b0: alu_b = rd2_exec;
            1'b1: alu_b = imm_exec;
        endcase
    end

    branch_comparator bc(
        .reg1(rd1_exec),
        .reg2(rd2_exec),
        .BrUn(br_un),
        .BrEq(br_eq),
        .BrLt(br_lt)
    );

    // mem inputs

    reg [DWIDTH-1:0] mem_din;
    reg [BEWIDTH-1:0] mem_wbe;

    wire [DWIDTH-1:0] mem_din_raw;
    assign mem_din_raw = rd2_exec;
    always @(*) begin
        mem_wbe = 4'd0;
        mem_din = 32'd0;
        case (bhw_1) 
            2'd0: begin
                case (ApB[1:0]) 
                    2'd0: begin
                        mem_wbe = 4'b0001;
                        mem_din = {24'dx, mem_din_raw[7:0]};
                    end
                    2'd1: begin
                        mem_wbe = 4'b0010;
                        mem_din = {16'dx, mem_din_raw[7:0], 8'dx};
                    end
                    2'd2: begin
                        mem_wbe = 4'b0100;
                        mem_din = {8'dx, mem_din_raw[7:0], 16'dx};
                    end
                    default: begin // 3
                        mem_wbe = 4'b1000;
                        mem_din = {mem_din_raw[7:0], 24'dx};
                    end
                endcase
            end
            2'd1: begin
                case (ApB[1:0])
                    2'd0: begin
                        mem_wbe = 4'b0011;
                        mem_din = {16'dx, mem_din_raw[15:0]};
                    end
                    default: begin // 2
                        mem_wbe = 4'b1100;
                        mem_din = {mem_din_raw[15:0], 16'dx};
                    end
                endcase
            end
            default: begin
                mem_wbe = 4'b1111;
                mem_din = mem_din_raw;
            end
        endcase
    end

    assign dmem_dina = mem_din;
    assign dmem_wbea = (ApB[28] & mem_we) ? mem_wbe : 4'b0;
    assign dmem_addra = ApB[DMEM_AWIDTH+1:2];
    assign dmem_ena = !stall;

    assign imem_dinb = mem_din;
    assign imem_wbeb = (ApB[29] & mem_we) ? mem_wbe : 4'b0;
    assign imem_addrb = ApB[IMEM_AWIDTH+1:2];
    assign imem_enb = !stall; 

    assign bios_addrb = ApB[BIOS_AWIDTH+1:2];
    assign bios_enb = !stall;

    assign uart_mem_we = mem_we;
    assign uart_addr = ApB;
    assign uart_din = mem_din;

    // mem outputs
    wire [DWIDTH-1:0] alu_mem;
    
    // On m_ext_v, latch M-extension result into alu_mem so wb_sel==1 path gets mul/div/rem (same as FPU skip_stall_wb)
    wire [DWIDTH-1:0] alu_mem_din = m_ext_v ? m_ext_wb_data : alu_res;
    REGISTER_R_CE #(.N(DWIDTH)) alu_mem_reg(.d(alu_mem_din), .q(alu_mem), .clk(clk), .rst(rst), .ce(!stall || skip_stall_wb));
    REGISTER_R_CE #(.N(DWIDTH)) pc_mem_reg(.d(pc_exec), .q(pc_mem), .clk(clk), .rst(rst), .ce(!stall));
    
    wire [4:0] bit_offset_mem;
    assign bit_offset_mem = alu_mem[1:0]<<3;

    reg [DWIDTH-1:0] mem_sel;
    always @(*) begin
        case (alu_mem[31:28])
            4'b0001, 4'b0011: mem_sel = dmem_douta;
            4'b0100: mem_sel = bios_doutb;
            4'b1000, 4'b0000: mem_sel = uart_dout; // 0000 implies mtime
            default mem_sel = 32'b0;
        endcase
    end

    reg [DWIDTH-1:0] mem_bhw;
    always @(*) begin
        mem_bhw = mem_sel;
        case (bhw_2)
            // alu_mem not alu_res because dmem_douta is evaluated in MEM stage
            2'd0: begin
                case (alu_mem[1:0])
                    2'd0: mem_bhw = {(load_un) ? 24'b0 : {24{mem_sel[7]}}, mem_sel[7:0]};
                    2'd1: mem_bhw = {(load_un) ? 24'b0 : {24{mem_sel[15]}}, mem_sel[15:8]};
                    2'd2: mem_bhw = {(load_un) ? 24'b0 : {24{mem_sel[23]}}, mem_sel[23:16]};
                    default: mem_bhw = {(load_un) ? 24'b0 : {24{mem_sel[31]}}, mem_sel[31:24]};
                endcase
            end
            2'd1: begin
                case (alu_mem[1:0])
                    2'd0: mem_bhw = {(load_un) ? 16'b0 : {16{mem_sel[15]}}, mem_sel[15:0]};
                    default: mem_bhw = {(load_un) ? 16'b0 : {16{mem_sel[31]}}, mem_sel[31:16]};
                endcase
            end
            default: mem_bhw = mem_sel; // 3'd2
        endcase
    end

    // wb mux
    always @(*) begin
        case (wb_sel) 
            2'd0: wb = pc_mem_p4;
            2'd1: wb = alu_mem;
            2'd2: wb = mem_bhw;
            2'd3: wb = csr_dout;
            // add forwarding
        endcase
    end
    assign wd = wb;

    wire non_dmem_load_store = ApB[31:28] != 4'b0001 & (mem_we | is_load) & ApB[31:24] != 8'h02 & !noop_exec;

    // CSR regfile (not yet used for writeback; provides architectural state)
    csr_regfile csr_rf (
      .clk(clk),
      .rst(rst),
      .csr_set(csr_en && csr_set2),
      .csr_clear(csr_en && csr_clear2),
      .csr_write(csr_en && csr_write2),
      .csr_addr(csr_addr),
      .csr_data_in(alu_mem),  // value to write to CSR (rs1 or imm); wb is csr_dout for rd writeback
      .csr_data_out(csr_dout),
      .machine_timer_interrupt(machine_timer_interrupt),
      .machine_external_interrupt(1'b0),
      .inst_retired(valid_inst),
      .pc(pc),
      .interrupt_pending(interrupt_pending),
      .mtvec_out(mtvec),
      .mepc_out(mepc),
      .mret(is_mret),
      .ecall(is_ecall),
      .pc_sel(pc_sel)
    );

    `ifdef SYNTHESIS
    // ILA: pc, inst, reg_we, wd[31:0], wa[4:0], ApB, mem_we, mem_din[31:0]
    ila_0 my_ila (
        .clk(clk),
        .probe0(pc),
        .probe1(inst),
        .probe2(reg_we),
        .probe3(wd),
        .probe4(wa),
        .probe5(ApB),
        .probe6(mem_we),
        .probe7(mem_din),
        .probe8(uart_rx_ila_hist_cdc)
    );
    `endif

endmodule
