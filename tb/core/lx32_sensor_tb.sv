`timescale 1ns/1ps

module lx32_sensor_tb;

  import lx32_isa_pkg::*;
  import lx32_mmio_pkg::*;

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

    // Program x1=5 through normal datapath (ADDI x1, x0, 5)
    instr = enc_addi(5'd1, 5'd0, 12'd5);
    @(posedge clk);
    @(negedge clk);

    // LX.SENSOR
    instr = enc_custom_i(3'b000, 5'd1, 5'd2, OP_CUSTOM_0);
    #1;
    assert(dut.custom_0) else $fatal(1, "LX.SENSOR did not assert custom_0");
    assert(dut.rd_data == 32'd1005) else $fatal(1, "LX.SENSOR wrong value: %0d", dut.rd_data);

    // LX.MATRIX
    instr = enc_custom_i(3'b001, 5'd0, 5'd2, OP_CUSTOM_0);
    #1;
    assert(dut.rd_data == SENSOR_DATA_BASE)
      else $fatal(1, "LX.MATRIX wrong pointer: 0x%08h", dut.rd_data);

    // LX.DELTA
    instr = enc_custom_i(3'b010, 5'd1, 5'd2, OP_CUSTOM_0);
    #1;
    assert(dut.rd_data == 32'd20) else $fatal(1, "LX.DELTA wrong value: %0d", dut.rd_data);

    $display("lx32_sensor_tb: PASS");
    $finish;
  end

endmodule


