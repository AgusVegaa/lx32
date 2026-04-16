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
  import lx32_mmio_pkg::*;

  // ------------------------------------------------------------
  // Internal Signals
  // ------------------------------------------------------------
  logic [31:0] pc, next_pc;
  logic [31:0] rs1_data, rs2_data, imm_ext;
  logic [31:0] alu_a, alu_b, alu_res, rd_data;
  logic [31:0] custom_result;
  logic [31:0] effective_mem_rdata;

  // Control signals
  logic        reg_write, alu_src, mem_write;
  logic        branch_en, branch_taken, jump, jalr, src_a_pc;
  logic        custom_0, custom_1;
  logic [1:0]  result_src;
  alu_op_e     alu_control;
  branch_op_e  branch_op_ctrl; // Internal wire for decoded branch type

  // Custom instruction / peripheral stub signals
  logic [15:0] sensor_val, delta_val;
  logic [31:0] matrix_ptr;
  logic        chord_match;
  logic        dma_report_req;
  logic [31:0] dma_report_ptr;

  // MMIO decode wiring
  logic        sensor_mmio_req, dma_mmio_req;
  logic [31:0] sensor_mmio_rdata, dma_mmio_rdata;
  logic        mmio_is_sensor, mmio_is_dma;

  // External memory interface gating
  logic [31:0] lsu_mem_addr, lsu_mem_wdata;
  logic        lsu_mem_we;

  // WAIT custom instruction state
  logic [31:0] wait_counter;
  logic        wait_active;
  logic        wait_start;
  logic        wait_consumed;
  logic        is_wait_instr;

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
  assign wait_active = (wait_counter != 32'h0);

  assign next_pc = (wait_active || wait_start)
                 ? pc
                 : (jump
                 ? (jalr ? ((rs1_data + imm_ext) & 32'hFFFF_FFFE) : (pc + imm_ext))
                 : ((branch_en && branch_taken) ? (pc + imm_ext) : (pc + 4)));

  assign is_wait_instr = custom_1 && (instr[14:12] == 3'b000);
  assign wait_start = is_wait_instr && !wait_active && !wait_consumed;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      wait_counter <= 32'h0;
      wait_consumed <= 1'b0;
    end else if (wait_start) begin
      // Read cycle count from bits[11:7] (rd field): the LX32 compiler encodes
      // lx.wait with the source register at rd, not rs1.
      wait_counter <= wait_src_data;
      wait_consumed <= 1'b1;
    end else if (wait_active) begin
      wait_counter <= wait_counter - 32'd1;
    end else if (!is_wait_instr) begin
      wait_consumed <= 1'b0;
    end
  end

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
    .custom_0    (custom_0),
    .custom_1    (custom_1),
    .branch_op   (branch_op_ctrl), // Connected to new control output
    .alu_control (alu_control)
  );

  sensor_controller sensor_stub (
    .clk        (clk),
    .rst        (rst),
    .sensor_idx (rs1_data[5:0]),
    .sensor_val (sensor_val),
    .matrix_ptr (matrix_ptr),
    .delta_val  (delta_val),
    .chord_mask (rs1_data),
    .chord_match(chord_match),
    .mmio_req   (sensor_mmio_req),
    .mmio_we    (mem_write),
    .mmio_addr  (lsu_mem_addr[7:2]),
    .mmio_rdata (sensor_mmio_rdata)
  );

  dma_controller dma_stub (
    .clk        (clk),
    .rst        (rst),
    .report_req (dma_report_req),
    .report_ptr (dma_report_ptr),
    .mmio_req   (dma_mmio_req),
    .mmio_we    (mem_write),
    .mmio_addr  (lsu_mem_addr[7:2]),
    .mmio_wdata (lsu_mem_wdata),
    .mmio_rdata (dma_mmio_rdata)
  );

  assign dma_report_req = custom_1 && (instr[14:12] == 3'b001);
  assign dma_report_ptr = rs1_data;

  always_comb begin
    unique case (instr[14:12])
      3'b000: custom_result = {16'h0, sensor_val};
      3'b001: custom_result = matrix_ptr;
      3'b010: custom_result = {16'h0, delta_val};
      3'b011: custom_result = {31'h0, chord_match};
      default: custom_result = 32'h0;
    endcase
  end

  // ------------------------------------------------------------
  // Register File (RF)
  // ------------------------------------------------------------
  // wait_src_data: the register at instr[11:7] (rd field).
  // The LX32 compiler encodes lx.wait as: rd = cycle_count_reg, rs1 = x0.
  // The RTL reads the cycle count from this port instead of rs1_data.
  logic [31:0] wait_src_data;

  register_file rf (
    .clk        (clk),
    .rst        (rst),
    .addr_rs1   (instr[19:15]),
    .addr_rs2   (instr[24:20]),
    .addr_rd    (instr[11:7]),
    .data_rd    (rd_data),
    .we         (reg_write),
    .data_rs1   (rs1_data),
    .data_rs2   (rs2_data),
    .data_rd_src(wait_src_data)
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
    .mem_addr   (lsu_mem_addr),
    .mem_wdata  (lsu_mem_wdata),
    .mem_we     (lsu_mem_we)
  );

  assign mmio_is_sensor = (lsu_mem_addr >= SENSOR_CTRL_BASE) && (lsu_mem_addr <= SENSOR_CTRL_END);
  assign mmio_is_dma    = (lsu_mem_addr >= DMA_CTRL_BASE) && (lsu_mem_addr <= DMA_CTRL_END);

  assign sensor_mmio_req = (result_src == 2'b01 || mem_write) && mmio_is_sensor;
  assign dma_mmio_req    = (result_src == 2'b01 || mem_write) && mmio_is_dma;

  always_comb begin
    if (mmio_is_sensor) effective_mem_rdata = sensor_mmio_rdata;
    else if (mmio_is_dma) effective_mem_rdata = dma_mmio_rdata;
    else effective_mem_rdata = mem_rdata;
  end

  assign mem_addr  = lsu_mem_addr;
  assign mem_wdata = lsu_mem_wdata;
  assign mem_we    = lsu_mem_we && !mmio_is_sensor && !mmio_is_dma;

  // ------------------------------------------------------------
  // Write-Back Mux (Result Selection)
  // ------------------------------------------------------------
  always_comb begin
    case (result_src)
      2'b01:   rd_data = effective_mem_rdata; // Load from memory/MMIO
      2'b10:   rd_data = pc + 32'd4; // Link register for JAL/JALR
      2'b11:   rd_data = imm_ext;    // LUI immediate
      default: rd_data = custom_0 ? custom_result : alu_res;
    endcase
  end

endmodule
