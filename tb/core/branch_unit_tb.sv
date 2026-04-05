`timescale 1ns/1ps

module branch_unit_tb;

  // Import branch operation enum used by the DUT interface.
  import lx32_branch_pkg::*;

  // ============================================================
  // LX32 Testbench: Branch Evaluation Unit
  // ============================================================
  // - Deterministic stimulus
  // - Structured checks
  // - Assertion-based validation
  // - Ready for VCD tracing
  // ============================================================

  localparam int WIDTH = 32;

  // ------------------------------------------------------------
  // DUT Signals
  // ------------------------------------------------------------
  logic [WIDTH-1:0] src_a;
  logic [WIDTH-1:0] src_b;
  logic             is_branch;
  branch_op_e       branch_op;
  logic             branch_taken;

  // ------------------------------------------------------------
  // DUT Instance
  // ------------------------------------------------------------
  branch_unit #(
    .WIDTH(WIDTH)
  ) dut (
    .src_a        (src_a),
    .src_b        (src_b),
    .is_branch    (is_branch),
    .branch_op    (branch_op),
    .branch_taken (branch_taken)
  );

  // ------------------------------------------------------------
  // VCD Tracing
  // ------------------------------------------------------------
  initial begin
    $dumpfile("tb_branch_unit.vcd");
    $dumpvars(0, branch_unit_tb);
  end

  // ------------------------------------------------------------
  // Utility Task: Apply and Check
  // ------------------------------------------------------------
  task automatic check_branch(
    input logic [WIDTH-1:0] a,
    input logic [WIDTH-1:0] b,
    input logic             en,
    input branch_op_e       op,
    input logic             expected
  );
    begin
      src_a     = a;
      src_b     = b;
      is_branch = en;
      branch_op = op;

      #1; // combinational settle

      assert (branch_taken === expected)
        else $fatal(1,
          "Branch check failed | op=%s a=%h b=%h expected=%b got=%b",
          op.name(), a, b, expected, branch_taken);
    end
  endtask

  // ------------------------------------------------------------
  // Test Sequence
  // ------------------------------------------------------------
  initial begin
    $display(">>> Starting Branch Unit Tests <<<");

    // Gating check: Disabled branch (is_branch = 0)
    // Even if A == B, branch_taken must be 0
    check_branch(32'h1, 32'h1, 1'b0, BR_EQ, 1'b0);

    // Equality (EQ / NE)
    check_branch(32'hA, 32'hA, 1'b1, BR_EQ, 1'b1);
    check_branch(32'hA, 32'hB, 1'b1, BR_EQ, 1'b0);
    check_branch(32'hA, 32'hA, 1'b1, BR_NE, 1'b0);
    check_branch(32'hA, 32'hB, 1'b1, BR_NE, 1'b1);

    // Signed comparisons (LT / GE)
    // 00000001 (1) < 00000002 (2) -> True
    check_branch(32'h1, 32'h2, 1'b1, BR_LT, 1'b1);
    // FFFFFFFF (-1) < 00000001 (1) -> True
    check_branch(32'hFFFFFFFF, 32'h00000001, 1'b1, BR_LT, 1'b1);
    check_branch(32'h2, 32'h1, 1'b1, BR_GE, 1'b1);

    // Unsigned comparisons (LTU / GEU)
    // 0 < FFFFFFFF (Max Unsigned) -> True
    check_branch(32'h0, 32'hFFFFFFFF, 1'b1, BR_LTU, 1'b1);
    // FFFFFFFF (Max) is NOT less than 0 unsigned -> False
    check_branch(32'hFFFFFFFF, 32'h0, 1'b1, BR_LTU, 1'b0);
    check_branch(32'hFFFFFFFF, 32'h0, 1'b1, BR_GEU, 1'b1);

    $display("tb_branch_unit: All tests passed");
    $dumpflush;
    $finish;
  end

endmodule
