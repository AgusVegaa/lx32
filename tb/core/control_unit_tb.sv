`timescale 1ns/1ps

module control_unit_tb;

  // Import real architectural packages
  import lx32_isa_pkg::*;
  import lx32_alu_pkg::*;
  import lx32_branch_pkg::*;

  // ============================================================
  // LX32 Testbench: Control Unit
  // ============================================================
  // - Validates main decode logic and ALU refinement
  // - Assertion-based verification for all control signals
  // - VCD tracing enabled
  // ============================================================

  // ------------------------------------------------------------
  // DUT Signals
  // ------------------------------------------------------------
  opcode_t    opcode;
  logic [2:0] funct3;
  logic       funct7_5;

  logic       reg_write;
  logic       alu_src;
  logic       mem_write;    // Now validated in check_decode
  logic [1:0] result_src;   // Now validated in check_decode
  logic       branch;
  logic       jump;
  logic       jalr;
  logic       src_a_pc;
  lx32_branch_pkg::branch_op_e branch_op;
  alu_op_e    alu_control;

  // ------------------------------------------------------------
  // DUT Instance
  // ------------------------------------------------------------
  control_unit dut (
    .opcode      (opcode),
    .funct3      (funct3),
    .funct7_5    (funct7_5),
    .reg_write   (reg_write),
    .alu_src     (alu_src),
    .mem_write   (mem_write),
    .result_src  (result_src),
    .branch      (branch),
    .jump        (jump),
    .jalr        (jalr),
    .src_a_pc    (src_a_pc),
    .branch_op   (branch_op),
    .alu_control (alu_control)
  );

  // ------------------------------------------------------------
  // VCD Tracing
  // ------------------------------------------------------------
  initial begin
    if ($test$plusargs("vcd")) begin
      $dumpfile("control_unit_tb.vcd");
      $dumpvars(0, control_unit_tb);
    end
  end

  // ------------------------------------------------------------
  // Utility Task: Apply and Check Decode
  // ------------------------------------------------------------
  task automatic check_decode(
    input opcode_t  exp_opcode,
    input logic [2:0] exp_f3,
    input logic       exp_f7,
    input logic       exp_reg_write,
    input logic       exp_alu_src,
    input logic       exp_mem_write,
    input logic [1:0] exp_res_src,
    input logic       exp_branch,
    input logic       exp_jump,
    input logic       exp_jalr,
    input logic       exp_src_a_pc,
    input branch_op_e exp_branch_op,
    input alu_op_e    exp_alu
  );
    begin
      opcode   = exp_opcode;
      funct3   = exp_f3;
      funct7_5 = exp_f7;

      #1; // combinational settle

      assert(reg_write  === exp_reg_write);
      assert(alu_src    === exp_alu_src);
      assert(mem_write  === exp_mem_write); // Fixes UNUSEDSIGNAL
      assert(result_src === exp_res_src);   // Fixes UNUSEDSIGNAL
      assert(branch     === exp_branch);
      assert(jump       === exp_jump);
      assert(jalr       === exp_jalr);
      assert(src_a_pc   === exp_src_a_pc);
      assert(branch_op  === exp_branch_op);
      assert(alu_control === exp_alu)
        else $fatal(1, "Decode mismatch | opcode=%s | Expected ALU:%s Got:%s",
                    exp_opcode.name(), exp_alu.name(), alu_control.name());
    end
  endtask

  // ------------------------------------------------------------
  // Test Sequence
  // ------------------------------------------------------------
  initial begin
    $display(">>> Starting Control Unit Decode Tests <<<");

    // R-Type ADD: opcode OP_OP, funct3 0, funct7_5 0
    check_decode(OP_OP, 3'b000, 1'b0, 1, 0, 0, 2'b00, 0, 0, 0, 0, BR_EQ, ALU_ADD);

    // R-Type SUB: opcode OP_OP, funct3 0, funct7_5 1
    check_decode(OP_OP, 3'b000, 1'b1, 1, 0, 0, 2'b00, 0, 0, 0, 0, BR_EQ, ALU_SUB);

    // Load Word: opcode OP_LOAD
    check_decode(OP_LOAD, 3'b010, 1'b0, 1, 1, 0, 2'b01, 0, 0, 0, 0, BR_EQ, ALU_ADD);

    // Store Word: opcode OP_STORE
    check_decode(OP_STORE, 3'b010, 1'b0, 0, 1, 1, 2'b00, 0, 0, 0, 0, BR_EQ, ALU_ADD);

    // Branch Equal: opcode OP_BRANCH
    check_decode(OP_BRANCH, 3'b000, 1'b0, 0, 0, 0, 2'b00, 1, 0, 0, 0, BR_EQ, ALU_SUB);

    // LUI
    check_decode(OP_LUI, 3'b000, 1'b0, 1, 1, 0, 2'b11, 0, 0, 0, 0, BR_EQ, ALU_ADD);

    // AUIPC
    check_decode(OP_AUIPC, 3'b000, 1'b0, 1, 1, 0, 2'b00, 0, 0, 0, 1, BR_EQ, ALU_ADD);

    // JAL
    check_decode(OP_JAL, 3'b000, 1'b0, 1, 0, 0, 2'b10, 0, 1, 0, 0, BR_EQ, ALU_ADD);

    // JALR
    check_decode(OP_JALR, 3'b000, 1'b0, 1, 1, 0, 2'b10, 0, 1, 1, 0, BR_EQ, ALU_ADD);

    $display("control_unit_tb: All tests passed");
    $dumpflush;
    $finish;
  end

endmodule
