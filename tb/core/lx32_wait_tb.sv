`timescale 1ns/1ps

module lx32_wait_tb;

  import lx32_isa_pkg::*;

  logic clk;
  logic rst;
  logic [31:0] instr;
  logic [31:0] pc_out;
  logic [31:0] mem_addr;
  logic [31:0] mem_wdata;
  logic [31:0] mem_rdata;
  logic mem_we;

  function automatic logic [31:0] enc_custom_i(
      input logic [2:0] funct3,
      input logic [4:0] rs1,
      input logic [4:0] rd,
      input logic [6:0] opcode
  );
    enc_custom_i = {12'h000, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] enc_addi(
      input logic [4:0] rd,
      input logic [4:0] rs1,
      input logic [11:0] imm12
  );
    enc_addi = {imm12, rs1, 3'b000, rd, OP_OP_IMM};
  endfunction

  lx32_system dut (
      .clk      (clk),
      .rst      (rst),
      .pc_out   (pc_out),
      .instr    (instr),
      .mem_addr (mem_addr),
      .mem_wdata(mem_wdata),
      .mem_rdata(mem_rdata),
      .mem_we   (mem_we)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  initial begin
    bit released;
    logic [31:0] pc_before_wait;
    logic [31:0] pc_after_issue;

    mem_rdata = 32'h0;
    instr = 32'h00000013; // NOP
    rst = 1'b1;

    repeat (3) @(posedge clk);
    rst = 1'b0;
    @(negedge clk);

    // Program x1=3 through datapath.
    instr = enc_addi(5'd1, 5'd0, 12'd3);
    @(posedge clk);
    @(negedge clk);

    pc_before_wait = pc_out;
    instr = enc_custom_i(3'b000, 5'd1, 5'd0, OP_CUSTOM_1);

    @(posedge clk);
    pc_after_issue = pc_out;
    assert(pc_after_issue == pc_before_wait)
      else $fatal(1, "WAIT issue should hold PC");

    // Must hold for at least 3 cycles (x1=3).
    repeat (3) begin
      @(posedge clk);
      assert(pc_out == pc_after_issue)
        else $fatal(1, "WAIT should stall PC, got %0d expected %0d", pc_out, pc_after_issue);
    end

    released = 1'b0;
    repeat (4) begin
      @(posedge clk);
      if (pc_out == (pc_after_issue + 32'd4))
        released = 1'b1;
    end
    assert(released)
      else $fatal(1, "WAIT did not release within expected bound");

    $display("lx32_wait_tb: PASS");
    $finish;
  end

endmodule

