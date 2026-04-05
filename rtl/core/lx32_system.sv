module lx32_system (
  // ------------------------------------------------------------
  // System Clock and Reset
  // ------------------------------------------------------------
  input  logic        clk,
  input  logic        rst,

  // ------------------------------------------------------------
  // Instruction Interface
  // ------------------------------------------------------------
  output logic [31:0] pc_out,
  input  logic [31:0] instr,

  // ------------------------------------------------------------
  // Data Memory Interface
  // ------------------------------------------------------------
  output logic [31:0] mem_addr,
  output logic [31:0] mem_wdata,
  input  logic [31:0] mem_rdata,
  output logic        mem_we
);

  // ============================================================
  // LX32 Processor System (Single Cycle)
  // ============================================================
  // Integration of all core sub-modules:
  // - Control Unit, ALU, Branch Unit, LSU, RF and ImmGen.
  //
  // Design Principles:
  //   - Clear signal naming and hierarchical structure.
  //   - Single-cycle execution datapath.
  //   - Asynchronous reset for Program Counter.
  // ============================================================

  import lx32_isa_pkg::*;
  import lx32_alu_pkg::*;
  import lx32_branch_pkg::*;

  // ------------------------------------------------------------
  // Internal Signals
  // ------------------------------------------------------------
  logic [31:0] pc, next_pc;
  logic [31:0] rs1_data, rs2_data, imm_ext;
  logic [31:0] alu_a, alu_b, alu_res, rd_data;

  // Control signals
  logic        reg_write, alu_src, mem_write;
  logic        branch_en, branch_taken, jump, jalr, src_a_pc;
  logic [1:0]  result_src;
  alu_op_e     alu_control;
  branch_op_e  branch_op_ctrl; // Internal wire for decoded branch type

  // ------------------------------------------------------------
  // Program Counter (PC) Logic - Asynchronous Reset
  // ------------------------------------------------------------
  /* verilator lint_off SYNCASYNCNET */
  always_ff @(posedge clk or posedge rst) begin
    if (rst) pc <= 32'h0;
    else     pc <= next_pc;
  end
  /* verilator lint_on SYNCASYNCNET */

  assign pc_out  = pc;

  // PC target selection: JAL/JALR have priority over conditional branch
  assign next_pc = jump
                 ? (jalr ? ((rs1_data + imm_ext) & 32'hFFFF_FFFE) : (pc + imm_ext))
                 : ((branch_en && branch_taken) ? (pc + imm_ext) : (pc + 4));

  // ------------------------------------------------------------
  // Main Control Unit
  // ------------------------------------------------------------
  control_unit ctrl (
    .opcode      (opcode_t'(instr[6:0])),
    .funct3      (instr[14:12]),
    .funct7_5    (instr[30]),
    .reg_write   (reg_write),
    .alu_src     (alu_src),
    .mem_write   (mem_write),
    .result_src  (result_src),
    .branch      (branch_en),
    .jump        (jump),
    .jalr        (jalr),
    .src_a_pc    (src_a_pc),
    .branch_op   (branch_op_ctrl), // Connected to new control output
    .alu_control (alu_control)
  );

  // ------------------------------------------------------------
  // Register File (RF)
  // ------------------------------------------------------------
  register_file rf (
    .clk      (clk),
    .rst      (rst),
    .addr_rs1 (instr[19:15]),
    .addr_rs2 (instr[24:20]),
    .addr_rd  (instr[11:7]),
    .data_rd  (rd_data),
    .we       (reg_write),
    .data_rs1 (rs1_data),
    .data_rs2 (rs2_data)
  );

  // ------------------------------------------------------------
  // Immediate Generation Unit
  // ------------------------------------------------------------
  imm_gen igen (
    .instr (instr),
    .imm   (imm_ext)
  );

  // ------------------------------------------------------------
  // Arithmetic Logic Unit (ALU)
  // ------------------------------------------------------------
  assign alu_a = src_a_pc ? pc : rs1_data;
  assign alu_b = alu_src ? imm_ext : rs2_data;

  alu core_alu (
    .src_a       (alu_a),
    .src_b       (alu_b),
    .alu_control (alu_control),
    .alu_result  (alu_res)
  );

  // ------------------------------------------------------------
  // Branch Evaluation Unit
  // ------------------------------------------------------------
  branch_unit core_branch_unit (
    .src_a        (rs1_data),       // Use raw register data for comparison
    .src_b        (rs2_data),       // Branches compare x[rs1] and x[rs2]
    .is_branch    (branch_en),
    .branch_op    (branch_op_ctrl), // Uses the decoded enum from Control Unit
    .branch_taken (branch_taken)
  );

  // ------------------------------------------------------------
  // Load/Store Unit (LSU)
  // ------------------------------------------------------------
  lsu core_lsu (
    .alu_result (alu_res),
    .write_data (rs2_data),
    .mem_write  (mem_write),
    .mem_addr   (mem_addr),
    .mem_wdata  (mem_wdata),
    .mem_we     (mem_we)
  );

  // ------------------------------------------------------------
  // Write-Back Mux (Result Selection)
  // ------------------------------------------------------------
  always_comb begin
    case (result_src)
      2'b01:   rd_data = mem_rdata; // Load from memory
      2'b10:   rd_data = pc + 32'd4; // Link register for JAL/JALR
      2'b11:   rd_data = imm_ext;    // LUI immediate
      default: rd_data = alu_res;   // ALU result
    endcase
  end

endmodule
