`timescale 1ns/1ps

module lx32_chord_tb;

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
    mem_rdata = 32'h0;
    instr = 32'h00000013; // NOP
    rst = 1'b1;

    repeat (3) @(posedge clk);
    rst = 1'b0;
    @(negedge clk);

    // active_keys in stub is 0x000000FF; program x1=0x0000000F
    instr = enc_addi(5'd1, 5'd0, 12'h00F);
    @(posedge clk);
    @(negedge clk);

    instr = enc_custom_i(3'b011, 5'd1, 5'd3, OP_CUSTOM_0);
    #1;
    assert(dut.chord_match == 1'b1) else $fatal(1, "LX.CHORD expected match");
    assert(dut.rd_data == 32'd1) else $fatal(1, "LX.CHORD expected rd_data=1");

    // mask outside active_keys set should fail
    instr = enc_addi(5'd1, 5'd0, 12'h100);
    @(posedge clk);
    @(negedge clk);

    instr = enc_custom_i(3'b011, 5'd1, 5'd3, OP_CUSTOM_0);
    #1;
    assert(dut.chord_match == 1'b0) else $fatal(1, "LX.CHORD expected no match");
    assert(dut.rd_data == 32'd0) else $fatal(1, "LX.CHORD expected rd_data=0");

    $display("lx32_chord_tb: PASS");
    $finish;
  end

endmodule


