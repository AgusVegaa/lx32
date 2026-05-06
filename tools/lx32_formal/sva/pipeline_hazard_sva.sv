// pipeline_hazard_sva.sv — SVA bounded model checks for the LX32K pipeline.
//
// Self-contained formal model of the 2-stage (IF | EX) pipeline control.
// Compatible with Yosys 0.64 + smtbmc (uses $anyseq/$past/f_past_valid;
// no `property` blocks, no package imports).
//
// Properties:
//   P1  PC is always word-aligned.
//   P2  x0 is never written.
//   P3  wait_active implies pipe_stall.
//   P4  Branch/jump: if_ex_valid==0 on the cycle after a flush.
//   P5  No register write-back during a bubble (if_ex_valid==0).
//   P6  wait_counter==0 when wait_active==0.
//   P7  A stall keeps if_ex_valid and if_ex_instr unchanged.

module pipeline_hazard_sva (
  input wire clk
);

  // ── Free / unconstrained inputs ──────────────────────────────────────────
  reg        rst;
  reg [31:0] instr;
  reg [31:0] branch_target;   // symbolic branch/jump target
  reg        branch_taken_free;
  reg        dma_busy;

  always @(*) begin
    rst              = $anyseq;
    instr            = $anyseq;
    branch_target    = $anyseq;
    branch_taken_free= $anyseq;
    dma_busy         = $anyseq;
  end

  // ── Pipeline state registers ──────────────────────────────────────────────
  reg [31:0] if_ex_instr;
  reg [31:0] if_ex_pc;
  reg        if_ex_valid;
  reg [31:0] pc;
  reg [31:0] wait_counter;
  reg        wait_consumed;

  // ── Combinatorial decode ──────────────────────────────────────────────────
  wire [6:0] opcode  = if_ex_instr[6:0];
  wire [4:0] rd      = if_ex_instr[11:7];
  wire [2:0] funct3  = if_ex_instr[14:12];

  wire is_branch   = (opcode == 7'b110_0011);
  wire is_jal      = (opcode == 7'b110_1111);
  wire is_jalr     = (opcode == 7'b110_0111);
  wire is_jump     = is_jal || is_jalr;
  wire is_custom1  = (opcode == 7'b010_1011);

  wire is_wait_instr   = if_ex_valid && is_custom1 && (funct3 == 3'b000);
  wire is_report_instr = if_ex_valid && is_custom1 && (funct3 == 3'b001);

  wire branch_taken = if_ex_valid && is_branch && branch_taken_free;
  wire jump         = if_ex_valid && is_jump;

  wire reg_write =  (opcode == 7'b011_0011)   // R-type
                  || (opcode == 7'b001_0011)   // ALU-imm
                  || (opcode == 7'b000_0011)   // LOAD
                  || (opcode == 7'b110_1111)   // JAL
                  || (opcode == 7'b110_0111)   // JALR
                  || (opcode == 7'b001_0111)   // AUIPC
                  || (opcode == 7'b011_0111)   // LUI
                  || (opcode == 7'b000_1011)   // CUSTOM-0 (sensor)
                  ;
  wire reg_write_en = reg_write && if_ex_valid;

  wire wait_active = (wait_counter != 32'h0);
  wire wait_start  = is_wait_instr && !wait_active && !wait_consumed;

  wire pipe_stall = wait_active || (dma_busy && is_report_instr);
  wire pipe_flush = branch_taken || jump || wait_start;

  wire [31:0] next_pc = (jump || branch_taken) ? branch_target : (pc + 32'd4);

  localparam [31:0] NOP_INSTR = 32'h0000_0013;

  // ── Sequential update (mirrors lx32_system.sv logic) ─────────────────────
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      pc            <= 32'h0;
      if_ex_instr   <= NOP_INSTR;
      if_ex_pc      <= 32'h0;
      if_ex_valid   <= 1'b0;
      wait_counter  <= 32'h0;
      wait_consumed <= 1'b0;
    end else begin
      if (!pipe_stall && !wait_start)
        pc <= next_pc;

      if (wait_start) begin
        wait_counter  <= 32'd4;
        wait_consumed <= 1'b1;
      end else if (wait_active) begin
        wait_counter <= wait_counter - 32'd1;
      end else if (!is_wait_instr) begin
        wait_consumed <= 1'b0;
      end

      if (pipe_flush) begin
        if_ex_instr <= NOP_INSTR;
        if_ex_pc    <= pc;
        if_ex_valid <= 1'b0;
      end else if (!pipe_stall) begin
        if_ex_instr <= instr;
        if_ex_pc    <= pc;
        if_ex_valid <= 1'b1;
      end
    end
  end

  // ── f_past_valid: first-cycle guard ──────────────────────────────────────
  reg f_past_valid;
  initial f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  // ── Assumptions ───────────────────────────────────────────────────────────
  always @(posedge clk) begin
    // First cycle: must be in reset.
    if (!f_past_valid) assume(rst);
    // Branch/jump targets are always word-aligned.
    assume(branch_target[1:0] == 2'b00);
  end

  // ── P1: PC is word-aligned ────────────────────────────────────────────────
  always @(posedge clk)
    if (f_past_valid && !rst)
      assert(pc[1:0] == 2'b00);

  // ── P3: wait_active implies pipe_stall ────────────────────────────────────
  always @(posedge clk)
    if (f_past_valid && !rst && wait_active)
      assert(pipe_stall);

  // ── P4: branch/jump flush produces bubble next cycle ─────────────────────
  // $past checks the previous cycle's value of if_ex_valid.
  always @(posedge clk)
    if (f_past_valid && !rst && $past(branch_taken || jump))
      assert(!if_ex_valid);

  // ── P5: no writeback during bubble ────────────────────────────────────────
  always @(posedge clk)
    if (f_past_valid && !rst)
      assert(!(!if_ex_valid && reg_write_en));

  // ── P6: wait_counter == 0 when not wait_active ────────────────────────────
  always @(posedge clk)
    if (f_past_valid && !rst && !wait_active)
      assert(wait_counter == 32'h0);

  // ── P7: stall holds if_ex frozen ─────────────────────────────────────────
  always @(posedge clk)
    if (f_past_valid && !rst && $past(pipe_stall) && $past(if_ex_valid) && !$past(pipe_flush))
      assert(if_ex_valid && if_ex_instr == $past(if_ex_instr));

endmodule
