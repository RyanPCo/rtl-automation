// CSR addresses (hex)
// mstatus 300, misa 301, mie 304, mtvec 305,
// mscratch 340, mepc 341, mcause 342, mip 344,
// mcycle 800, minstret 802, mcycleh B80, minstreth B82, mhartid F14

module csr_regfile(
    input clk,
    input rst,
    input csr_set,
    input csr_clear,
    input csr_write,
    input [11:0] csr_addr,
    input [31:0] csr_data_in,
    output [31:0] csr_data_out,

    input machine_timer_interrupt,
    input machine_external_interrupt,
    input inst_retired,  // 1 when an instruction retires (for minstret)
    input [31:0] pc,    // current PC; captured into mepc when trap is taken
    input pc_sel, // current exec inst is a jump or branch
    input mret,         // 1 when mret instruction is executing (restore MIE from MPIE, return to mepc)
    input ecall,        // 1 when ecall is taken: capture pc to mepc, set mcause=11, update mstatus, jump to mtvec
    output interrupt_pending,
    output [31:0] mtvec_out,
    output [31:0] mepc_out
);

  // Address constants (hex)
  localparam [11:0] CSR_MSTATUS  = 12'h300;
  localparam [11:0] CSR_MISA     = 12'h301;
  localparam [11:0] CSR_MIE      = 12'h304;
  localparam [11:0] CSR_MTVEC   = 12'h305;
  localparam [11:0] CSR_MSCRATCH = 12'h340;
  localparam [11:0] CSR_MEPC     = 12'h341;
  localparam [11:0] CSR_MCAUSE   = 12'h342;
  localparam [11:0] CSR_MIP      = 12'h344;
  localparam [11:0] CSR_TOHOST   = 12'h51e;
  localparam [11:0] CSR_MCYCLE   = 12'h800;
  localparam [11:0] CSR_MINSTRET = 12'h802;
  localparam [11:0] CSR_MCYCLEH  = 12'hB80;
  localparam [11:0] CSR_MINSTRETH= 12'hB82;
  localparam [11:0] CSR_MHARTID  = 12'hF14;

  // --- Separate registers ---
  reg [31:0] mscratch;
  reg [31:0] mstatus;
  reg [31:0] mepc;
  reg [31:0] mcause;
  reg [31:0] tohost;
  reg [63:0] mcycle;
  reg [63:0] minstret;
  reg [31:0] mie;
  reg [31:0] mtvec;   // [1:0] MODE, [31:2] BASE (4-byte aligned)
  reg [31:0] mip_reg; // writable bits; bits 7 (MTI) and 11 (MEI) are driven and not overwritten

  // Read-only constants
  localparam [31:0] MISA_VAL  = 32'h4000_1100;  // RV32IM
  localparam [31:0] MHARTID_VAL = 32'd0;

  wire csr_op = csr_write | csr_set | csr_clear;

  // --- MIP: mip_reg holds only writable bits; bits 7 (MTI) and 11 (MEI) are driven by hardware and not stored.
  wire [31:0] mip_read = mip_reg |
                         ((32'd1 << 7)  & {32{machine_timer_interrupt}}) |
                         ((32'd1 << 11) & {32{machine_external_interrupt}});

  // --- Next values for CSR writes (before applying to regs)
  reg [31:0] rdata;
  wire [31:0] wdata_scratch, wdata_status, wdata_epc, wdata_cause, wdata_mie, wdata_mtvec;
  wire [31:0] wdata_mip;  // writable bits only; bits 7 and 11 forced to 0 in stored value
  wire [63:0] wdata_mcycle, wdata_minstret;
  wire [31:0] wdata_tohost;

  function [31:0] csr_next_value;
    input [31:0] old_val;
    input [31:0] in_val;
    input set, clear, write;
    begin
      if (write)       csr_next_value = in_val;
      else if (set)    csr_next_value = old_val | csr_data_in;
      else if (clear)  csr_next_value = old_val & ~(csr_data_in);
      else             csr_next_value = old_val;
    end
  endfunction

  assign wdata_scratch = csr_next_value(mscratch, csr_data_in, csr_set, csr_clear, csr_write);
  assign wdata_status  = csr_next_value(mstatus,  csr_data_in, csr_set, csr_clear, csr_write);
  assign wdata_epc     = csr_next_value(mepc,    csr_data_in, csr_set, csr_clear, csr_write);
  // the last interrupt pending indicates that it's a software interrupt
  assign wdata_cause   = csr_next_value(mcause,  csr_data_in, csr_set, csr_clear, csr_write);
  assign wdata_tohost  = csr_next_value(tohost,  csr_data_in, csr_set, csr_clear, csr_write);
  assign wdata_mie     = csr_next_value(mie,     csr_data_in, csr_set, csr_clear, csr_write);
  assign wdata_mtvec   = csr_next_value(mtvec,   csr_data_in, csr_set, csr_clear, csr_write);
  // MIP: driven bits 7 and 11 cannot be overwritten; store only writable part
  assign wdata_mip     = csr_next_value(mip_read, csr_data_in, csr_set, csr_clear, csr_write) & ~(32'd1 << 7) & ~(32'd1 << 11);
  // For mcycle/minstret we only support full 32-bit write to low or high; simple update
  assign wdata_mcycle  = (csr_addr == CSR_MCYCLE)  ? {mcycle[63:32], csr_next_value(mcycle[31:0],  csr_data_in, csr_set, csr_clear, csr_write)} :
                         (csr_addr == CSR_MCYCLEH) ? {csr_next_value(mcycle[63:32], csr_data_in, csr_set, csr_clear, csr_write), mcycle[31:0]} : mcycle;
  assign wdata_minstret= (csr_addr == CSR_MINSTRET) ? {minstret[63:32], csr_next_value(minstret[31:0],  csr_data_in, csr_set, csr_clear, csr_write)} :
                         (csr_addr == CSR_MINSTRETH)? {csr_next_value(minstret[63:32], csr_data_in, csr_set, csr_clear, csr_write), minstret[31:0]} : minstret;

  // --- csr_data_out: selected CSR value (combinational)
  always @(*) begin
    rdata = 32'd0;
    case (csr_addr)
      CSR_MSTATUS:   rdata = mstatus;
      CSR_MISA:      rdata = MISA_VAL;
      CSR_MIE:       rdata = mie;
      CSR_MTVEC:     rdata = mtvec;
      CSR_MSCRATCH:  rdata = mscratch;
      CSR_MEPC:      rdata = mepc;
      CSR_MCAUSE:    rdata = mcause;
      CSR_MIP:       rdata = mip_read;
      CSR_TOHOST:    rdata = tohost;
      CSR_MCYCLE:    rdata = mcycle[31:0];
      CSR_MINSTRET:  rdata = minstret[31:0];
      CSR_MCYCLEH:   rdata = mcycle[63:32];
      CSR_MINSTRETH: rdata = minstret[63:32];
      CSR_MHARTID:   rdata = MHARTID_VAL;
      default:       rdata = 32'd0;
    endcase
  end
  assign csr_data_out = rdata;

  // --- interrupt_pending: any enabled interrupt pending and interrupts are still enabled
  assign interrupt_pending = |(mie & mip_read) & mstatus[3] & ~pc_sel;

  // --- mtvec_out: trap vector base for CPU to jump on interrupt (mtvec[31:2] = base, [1:0] = mode)
  assign mtvec_out = mtvec;
  // --- mepc_out: return address for mret (PC <- mepc)
  assign mepc_out = mepc;

  // --- Sequential update and counters
  always @(posedge clk) begin
    if (rst) begin
      mscratch <= 32'd0;
      mstatus  <= 32'd0;
      mepc     <= 32'd0;
      mcause   <= 32'd0;
      tohost   <= 32'd0;
      mcycle   <= 64'd0;
      minstret <= 64'd0;
      mie      <= 32'd0;
      mtvec    <= 32'd0;
      mip_reg  <= 32'd0;
    end else begin
      mcycle   <= mcycle + 64'd1;
      if (inst_retired)
        minstret <= minstret + inst_retired;
      else
        minstret <= minstret;

      // On trap: capture PC into mepc (interrupt_pending is high only one cycle; MIE is cleared on trap)
      // Use nonblocking full-word mstatus update so synthesis infers the register correctly.
      if (interrupt_pending) begin
        mepc <= pc;
        mstatus <= (mstatus & 32'hFFFF_FF77) | (mstatus[3] << 7);  // MPIE=MIE, MIE=0 (bits 7,3)
        // RISC-V: mcause[31]=1 for interrupt, [30:0]=exception code. Zephyr __soc_is_irq checks bit 31.
        mcause <= (machine_timer_interrupt) ? (32'd1 << 31) | 32'd7 : machine_external_interrupt ? (32'd1 << 31) | 32'd11 : (32'd1 << 31) | 32'd3;
      end else if (ecall & ~pc_sel) begin
        // ECALL: save PC of ecall to mepc, mcause=11 (ECALL from M-mode), elevate to M-mode, clear MIE
        mepc <= pc;
        mstatus <= (mstatus & 32'hFFFF_FF77) | (mstatus[3] << 7);  // MPIE=MIE, MIE=0
        mcause <= 32'd11;  // Environment call from M-mode
      end else if (mret) begin
        // mret: MIE <- MPIE, MPIE <- 1 (mstatus bit 3 = MIE, bit 7 = MPIE)
        mstatus <= (mstatus & 32'hFFFF_FF77) | (mstatus[7] << 3) | (32'd1 << 7);
      end else if (csr_op) begin
        case (csr_addr)
          CSR_MSCRATCH: mscratch <= wdata_scratch;
          CSR_MSTATUS:  mstatus  <= wdata_status;
          CSR_MEPC:     mepc     <= wdata_epc;
          CSR_MCAUSE:   mcause   <= wdata_cause;
          CSR_TOHOST:   tohost   <= wdata_tohost;
          CSR_MIE:      mie      <= wdata_mie;
          CSR_MTVEC:    mtvec    <= wdata_mtvec;
          CSR_MIP:      mip_reg  <= wdata_mip;
          CSR_MCYCLE:   mcycle   <= wdata_mcycle;
          CSR_MCYCLEH:  mcycle   <= wdata_mcycle;
          CSR_MINSTRET: minstret <= wdata_minstret;
          CSR_MINSTRETH:minstret <= wdata_minstret;
          default: ;
        endcase
      end 
        
    end
  end

endmodule
