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
  output logic        mem_we,

  // ------------------------------------------------------------
  // Debug / Validation Port
  // ------------------------------------------------------------
  // When asserted, the EX stage commits its result but the PC and
  // IF/EX register are frozen (unless a branch or jump resolves).
  // Used by the test bridge to drain the pipeline stage between
  // clock steps, keeping external behaviour single-cycle-equivalent.
  // Tie to 0 in production / synthesis.
  input  logic        debug_stall,

  // ------------------------------------------------------------
  // GPIO Output (latency measurement / general purpose)
  // ------------------------------------------------------------
  // Driven by MMIO writes to GPIO_BASE (0x4000_0600).
  // Tie unconnected in simulation; route to FPGA pins in synthesis.
  output logic [31:0] gpio_out
);

  // ============================================================
  // LX32 Processor System — 2-Stage Pipeline (IF | EX)
  // ============================================================
  //
  // Stage IF (Instruction Fetch):
  //   Present pc to the external instruction memory and capture
  //   the combinatorial result into the IF/EX pipeline register
  //   at each rising clock edge.
  //
  // Stage EX (Decode + Execute + Write-Back):
  //   All decode, register-read, ALU, branch, memory, and write-
  //   back operations run on if_ex_instr / if_ex_pc.
  //
  // Branch/jump penalty: 1 cycle (flush the IF/EX register).
  // LX.WAIT stall  : freeze PC and IF/EX for N cycles.
  // DMA-busy stall : freeze PC and IF/EX until DMA engine is idle.
  //
  // The external interface (pc_out, instr, mem_*) is unchanged
  // from the single-cycle version so all existing testbenches
  // continue to work without modification.
  // ============================================================

  import lx32_isa_pkg::*;
  import lx32_alu_pkg::*;
  import lx32_branch_pkg::*;
  import lx32_mmio_pkg::*;

  // ------------------------------------------------------------
  // IF / EX Pipeline Register
  // ------------------------------------------------------------
  logic [31:0] if_ex_instr;   // Instruction in EX stage
  logic [31:0] if_ex_pc;      // PC of the instruction in EX stage
  logic        if_ex_valid;   // 0 = bubble (NOP), 1 = real instruction

  // NOP encoding: ADDI x0, x0, 0 = 32'h0000_0013
  localparam logic [31:0] NOP_INSTR = 32'h0000_0013;

  // ------------------------------------------------------------
  // Internal Signals
  // ------------------------------------------------------------
  logic [31:0] pc, next_pc;
  logic [31:0] rs1_data, rs2_data, imm_ext;
  logic [31:0] alu_a, alu_b, alu_res, rd_data;
  logic [31:0] custom_result;
  logic [31:0] effective_mem_rdata;

  // Control signals (decoded from if_ex_instr in EX stage)
  logic        reg_write, alu_src, mem_write;
  logic        branch_en, branch_taken, jump, jalr, src_a_pc;
  logic        custom_0, custom_1;
  logic [1:0]  result_src;
  alu_op_e     alu_control;
  branch_op_e  branch_op_ctrl;

  // Custom instruction / peripheral signals
  logic [15:0] sensor_val, delta_val;
  logic [31:0] matrix_ptr;
  logic        chord_match;
  logic        snapshot_rdy;
  logic        dma_report_req;
  logic [31:0] dma_report_ptr;
  logic        dma_busy;

  // DMA bus master (stub: immediate acknowledge for simulation)
  logic        dma_bus_req;
  logic [31:0] dma_bus_addr;
  logic [31:0] dma_bus_rdata;
  logic        dma_bus_ack;

  // USB endpoint byte stream (not connected in simulation)
  logic        usb_wr;
  logic [2:0]  usb_byte_idx;
  logic [7:0]  usb_wdata;

  // MMIO decode wiring
  logic        sensor_mmio_req, dma_mmio_req, rt_mmio_req, gpio_mmio_req;
  logic        intc_mmio_req;
  logic [31:0] sensor_mmio_rdata, dma_mmio_rdata, rt_mmio_rdata, intc_mmio_rdata;
  logic        mmio_is_sensor, mmio_is_dma, mmio_is_rt, mmio_is_gpio, mmio_is_intc;

  // Interrupt controller signals
  logic [7:0]  irq_src;
  logic        irq_out;

  // LX.WAKE: when LX.WAIT rs1 == WFI_SENTINEL, stall until irq_out asserts.
  localparam logic [31:0] WFI_SENTINEL = 32'hFFFF_FFFF;
  logic        is_wfi_mode;   // true while in WFI stall

  // Rapid-trigger signals
  logic [5:0]  rt_rd_idx;
  logic [15:0] rt_rd_val;
  logic        rt_event_valid;
  logic [5:0]  rt_event_key;
  logic        rt_event_is_press;

  // GPIO output register
  logic [31:0] gpio_out_reg;

  // External memory interface gating
  logic [31:0] lsu_mem_addr, lsu_mem_wdata;
  logic        lsu_mem_we;

  // LX.WAIT stall state
  logic [31:0] wait_counter;
  logic        wait_active;
  logic        wait_start;
  logic        wait_consumed;
  logic        is_wait_instr;   // Detected in EX stage (if_ex_instr)
  logic        is_report_instr; // Detected in EX stage

  // Pipeline stall / flush control
  logic        pipe_stall;   // Freeze PC and IF/EX register
  logic        pipe_flush;   // Replace IF/EX with NOP bubble

  // ------------------------------------------------------------
  // Pipeline Stall and Flush
  // ------------------------------------------------------------
  assign is_wait_instr   = if_ex_valid && custom_1 && (if_ex_instr[14:12] == 3'b000);
  assign is_report_instr = if_ex_valid && custom_1 && (if_ex_instr[14:12] == 3'b001);

  // wait_active is high from the cycle after wait_start until counter drains.
  assign wait_active = (wait_counter != 32'h0);

  // wait_start fires once per WAIT instruction (guard with wait_consumed).
  assign wait_start = is_wait_instr && !wait_active && !wait_consumed && !is_wfi_mode;

  // WFI mode: rs1 == WFI_SENTINEL on a LX.WAIT → stall until IRQ.
  assign is_wfi_mode = is_wait_instr && (rs1_data == WFI_SENTINEL) && !irq_out && !wait_consumed;

  // Stall: pipeline is frozen while counting wait cycles, in WFI mode, or while DMA is busy.
  assign pipe_stall = wait_active || is_wfi_mode || (dma_busy && is_report_instr);

  // Flush IF/EX: insert a bubble when a branch/jump resolves, or when
  // wait_start fires (the WAIT instruction has completed its EX cycle;
  // replace it with a bubble so the next real instruction does not sneak
  // into EX while the wait counter is running).
  // debug_stall also flushes: after EX commits the in-flight instruction
  // the slot is invalidated so the validator sees a clean pipeline state.
  assign pipe_flush = branch_taken || jump || wait_start || debug_stall;

  // ------------------------------------------------------------
  // Wait Counter
  // ------------------------------------------------------------
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      wait_counter  <= 32'h0;
      wait_consumed <= 1'b0;
    end else if (wait_start) begin
      wait_counter  <= rs1_data;
      wait_consumed <= 1'b1;
    end else if (wait_active) begin
      wait_counter  <= wait_counter - 32'd1;
    end else if (!is_wait_instr) begin
      // Clear the guard flag once WAIT leaves the EX stage.
      wait_consumed <= 1'b0;
    end
  end

  // ------------------------------------------------------------
  // Program Counter (IF Stage)
  // ------------------------------------------------------------
  /* verilator lint_off SYNCASYNCNET */
  always_ff @(posedge clk or posedge rst) begin
    if (rst)
      pc <= 32'h0;
    else if (!pipe_stall && !wait_start) begin
      // During a debug drain tick: freeze PC unless a branch/jump resolves
      // (in which case next_pc already holds the correct target).
      if (debug_stall && !branch_taken && !jump)
        pc <= pc;
      else
        pc <= next_pc;
    end
    // Otherwise: hold current PC (stall).
  end
  /* verilator lint_on SYNCASYNCNET */

  assign pc_out = pc;

  // next_pc is computed from the EX stage (if_ex_pc).
  assign next_pc = jump
                 ? (jalr ? ((rs1_data + imm_ext) & 32'hFFFF_FFFE)
                         : (if_ex_pc + imm_ext))
                 : ((branch_en && branch_taken) ? (if_ex_pc + imm_ext)
                                                : (pc + 32'd4));

  // ------------------------------------------------------------
  // IF / EX Pipeline Register
  // ------------------------------------------------------------
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      if_ex_instr <= NOP_INSTR;
      if_ex_pc    <= 32'h0;
      if_ex_valid <= 1'b0;
    end else if (pipe_flush) begin
      // Insert bubble — discard the speculatively-fetched instruction.
      if_ex_instr <= NOP_INSTR;
      if_ex_pc    <= pc;
      if_ex_valid <= 1'b0;
    end else if (!pipe_stall) begin
      // Normal advance: capture the instruction the IF stage just fetched.
      if_ex_instr <= instr;
      if_ex_pc    <= pc;
      if_ex_valid <= 1'b1;
    end
    // else: stall — keep IF/EX frozen.
  end

  // ------------------------------------------------------------
  // Main Control Unit (EX Stage — decodes if_ex_instr)
  // ------------------------------------------------------------
  control_unit ctrl (
    .opcode      (opcode_t'(if_ex_instr[6:0])),
    .funct3      (if_ex_instr[14:12]),
    .funct7_5    (if_ex_instr[30]),
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
    .branch_op   (branch_op_ctrl),
    .alu_control (alu_control)
  );

  // Suppress write-back for bubble instructions.
  wire reg_write_en = reg_write && if_ex_valid;
  wire mem_write_en = mem_write && if_ex_valid;

  // ------------------------------------------------------------
  // Sensor Controller
  // ------------------------------------------------------------
  sensor_controller sensor (
    .clk          (clk),
    .rst          (rst),
    .sensor_idx   (rs1_data[5:0]),
    .sensor_val   (sensor_val),
    .matrix_ptr   (matrix_ptr),
    .delta_val    (delta_val),
    .chord_mask   (rs1_data),
    .chord_match  (chord_match),
    .snapshot_rdy (snapshot_rdy),
    .rt_rd_idx    (rt_rd_idx),
    .rt_rd_val    (rt_rd_val),
    .mmio_req     (sensor_mmio_req),
    .mmio_we      (mem_write_en),
    .mmio_addr    (lsu_mem_addr[7:2]),
    .mmio_wdata   (lsu_mem_wdata),
    .mmio_rdata   (sensor_mmio_rdata)
  );

  // ------------------------------------------------------------
  // Hardware Rapid-Trigger Unit
  // ------------------------------------------------------------
  rapid_trigger rt (
    .clk           (clk),
    .rst           (rst),
    .rt_rd_idx     (rt_rd_idx),
    .rt_rd_val     (rt_rd_val),
    .event_valid   (rt_event_valid),
    .event_key     (rt_event_key),
    .event_is_press(rt_event_is_press),
    .mmio_req      (rt_mmio_req),
    .mmio_we       (mem_write_en),
    .mmio_addr     (lsu_mem_addr[7:2]),
    .mmio_wdata    (lsu_mem_wdata),
    .mmio_rdata    (rt_mmio_rdata)
  );

  // ------------------------------------------------------------
  // DMA Controller
  // ------------------------------------------------------------

  // Simulation bus master: single-cycle acknowledge.
  assign dma_bus_ack   = dma_bus_req;
  assign dma_bus_rdata = mem_rdata;  // reuse data memory read port (addr driven by DMA)

  assign dma_report_req = is_report_instr && !dma_busy;
  assign dma_report_ptr = rs1_data;

  dma_controller dma (
    .clk          (clk),
    .rst          (rst),
    .report_req   (dma_report_req),
    .report_ptr   (dma_report_ptr),
    .dma_busy     (dma_busy),
    .bus_req      (dma_bus_req),
    .bus_addr     (dma_bus_addr),
    .bus_rdata    (dma_bus_rdata),
    .bus_ack      (dma_bus_ack),
    .usb_wr       (usb_wr),
    .usb_byte_idx (usb_byte_idx),
    .usb_wdata    (usb_wdata),
    .mmio_req     (dma_mmio_req),
    .mmio_we      (mem_write_en),
    .mmio_addr    (lsu_mem_addr[7:2]),
    .mmio_wdata   (lsu_mem_wdata),
    .mmio_rdata   (dma_mmio_rdata)
  );

  // ------------------------------------------------------------
  // Interrupt Controller
  // ------------------------------------------------------------
  // IRQ source[0] = USB SOF (driven by usb_hid_bridge.sof_irq — stub: tied 0 here)
  // IRQ source[1] = DMA done (dma_busy falling edge → one-cycle pulse)
  logic dma_busy_prev;
  always_ff @(posedge clk or posedge rst) begin
    if (rst) dma_busy_prev <= 1'b0;
    else     dma_busy_prev <= dma_busy;
  end
  assign irq_src = {6'h0, (dma_busy_prev && !dma_busy), 1'b0}; // [1]=DMA done, [0]=SOF

  interrupt_controller intc (
    .clk        (clk),
    .rst        (rst),
    .irq_src    (irq_src),
    .irq_out    (irq_out),
    .mmio_req   (intc_mmio_req),
    .mmio_we    (mem_write_en),
    .mmio_addr  (lsu_mem_addr[7:2]),
    .mmio_wdata (lsu_mem_wdata),
    .mmio_rdata (intc_mmio_rdata)
  );

  // ------------------------------------------------------------
  // Custom Instruction Result Mux (EX Stage)
  // ------------------------------------------------------------
  always_comb begin
    unique case (if_ex_instr[14:12])
      3'b000: custom_result = {16'h0, sensor_val};  // LX.SENSOR
      3'b001: custom_result = matrix_ptr;            // LX.MATRIX
      3'b010: custom_result = {16'h0, delta_val};    // LX.DELTA
      3'b011: custom_result = {31'h0, chord_match};  // LX.CHORD
      default: custom_result = 32'h0;
    endcase
  end

  // ------------------------------------------------------------
  // Register File (EX Stage — reads if_ex_instr register fields)
  // ------------------------------------------------------------
  register_file rf (
    .clk      (clk),
    .rst      (rst),
    .addr_rs1 (if_ex_instr[19:15]),
    .addr_rs2 (if_ex_instr[24:20]),
    .addr_rd  (if_ex_instr[11:7]),
    .data_rd  (rd_data),
    .we       (reg_write_en),
    .data_rs1 (rs1_data),
    .data_rs2 (rs2_data)
  );

  // ------------------------------------------------------------
  // Immediate Generation (EX Stage)
  // ------------------------------------------------------------
  imm_gen igen (
    .instr (if_ex_instr),
    .imm   (imm_ext)
  );

  // ------------------------------------------------------------
  // ALU (EX Stage)
  // ------------------------------------------------------------
  assign alu_a = src_a_pc ? if_ex_pc : rs1_data;
  assign alu_b = alu_src  ? imm_ext  : rs2_data;

  alu core_alu (
    .src_a       (alu_a),
    .src_b       (alu_b),
    .alu_control (alu_control),
    .alu_result  (alu_res)
  );

  // ------------------------------------------------------------
  // Branch Unit (EX Stage)
  // ------------------------------------------------------------
  branch_unit core_branch_unit (
    .src_a        (rs1_data),
    .src_b        (rs2_data),
    .is_branch    (branch_en),
    .branch_op    (branch_op_ctrl),
    .branch_taken (branch_taken)
  );

  // ------------------------------------------------------------
  // Load / Store Unit (EX Stage)
  // ------------------------------------------------------------
  lsu core_lsu (
    .alu_result (alu_res),
    .write_data (rs2_data),
    .mem_write  (mem_write_en),
    .mem_addr   (lsu_mem_addr),
    .mem_wdata  (lsu_mem_wdata),
    .mem_we     (lsu_mem_we)
  );

  // ------------------------------------------------------------
  // MMIO Address Decode
  // ------------------------------------------------------------
  assign mmio_is_sensor = (lsu_mem_addr >= SENSOR_CTRL_BASE) &&
                          (lsu_mem_addr <= SENSOR_CTRL_END);
  assign mmio_is_dma    = (lsu_mem_addr >= DMA_CTRL_BASE) &&
                          (lsu_mem_addr <= DMA_CTRL_END);
  assign mmio_is_rt     = (lsu_mem_addr >= RT_CTRL_BASE) &&
                          (lsu_mem_addr <= RT_CTRL_END);
  assign mmio_is_gpio   = (lsu_mem_addr >= GPIO_BASE) &&
                          (lsu_mem_addr <= GPIO_END);
  assign mmio_is_intc   = (lsu_mem_addr >= INTC_BASE) &&
                          (lsu_mem_addr <= INTC_END);

  assign sensor_mmio_req = (result_src == 2'b01 || mem_write_en) && mmio_is_sensor;
  assign dma_mmio_req    = (result_src == 2'b01 || mem_write_en) && mmio_is_dma;
  assign rt_mmio_req     = (result_src == 2'b01 || mem_write_en) && mmio_is_rt;
  assign gpio_mmio_req   = (result_src == 2'b01 || mem_write_en) && mmio_is_gpio;
  assign intc_mmio_req   = (result_src == 2'b01 || mem_write_en) && mmio_is_intc;

  always_comb begin
    if      (mmio_is_sensor) effective_mem_rdata = sensor_mmio_rdata;
    else if (mmio_is_dma)    effective_mem_rdata = dma_mmio_rdata;
    else if (mmio_is_rt)     effective_mem_rdata = rt_mmio_rdata;
    else if (mmio_is_gpio)   effective_mem_rdata = gpio_out_reg;
    else if (mmio_is_intc)   effective_mem_rdata = intc_mmio_rdata;
    else                     effective_mem_rdata = mem_rdata;
  end

  assign mem_addr  = lsu_mem_addr;
  assign mem_wdata = lsu_mem_wdata;
  assign mem_we    = lsu_mem_we && !mmio_is_sensor && !mmio_is_dma
                                && !mmio_is_rt     && !mmio_is_gpio
                                && !mmio_is_intc;

  // GPIO register — writable via MMIO; readable back for toggle support.
  always_ff @(posedge clk or posedge rst) begin
    if (rst)
      gpio_out_reg <= 32'h0;
    else if (gpio_mmio_req && mem_write_en && (lsu_mem_addr[7:2] == 6'h00))
      gpio_out_reg <= lsu_mem_wdata;
  end
  assign gpio_out = gpio_out_reg;

  // ------------------------------------------------------------
  // Write-Back Mux (EX Stage)
  // ------------------------------------------------------------
  always_comb begin
    case (result_src)
      2'b01:   rd_data = effective_mem_rdata;
      2'b10:   rd_data = if_ex_pc + 32'd4;    // Link register for JAL/JALR
      2'b11:   rd_data = imm_ext;              // LUI immediate
      default: rd_data = custom_0 ? custom_result : alu_res;
    endcase
  end

endmodule
