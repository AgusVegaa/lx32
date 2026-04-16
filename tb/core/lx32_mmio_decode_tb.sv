`timescale 1ns/1ps

module lx32_mmio_decode_tb;

  import lx32_isa_pkg::*;

  logic clk;
  logic rst;
  logic [31:0] instr;
  logic [31:0] pc_out;
  logic [31:0] mem_addr;
  logic [31:0] mem_wdata;
  logic [31:0] mem_rdata;
  logic mem_we;

  function automatic logic [31:0] enc_lui(
      input logic [4:0] rd,
      input logic [19:0] imm20
  );
    enc_lui = {imm20, rd, OP_LUI};
  endfunction

  function automatic logic [31:0] enc_addi(
      input logic [4:0] rd,
      input logic [4:0] rs1,
      input logic [11:0] imm12
  );
    enc_addi = {imm12, rs1, 3'b000, rd, OP_OP_IMM};
  endfunction

  function automatic logic [31:0] enc_lw(
      input logic [4:0] rd,
      input logic [4:0] rs1,
      input logic [11:0] imm12
  );
    enc_lw = {imm12, rs1, 3'b010, rd, OP_LOAD};
  endfunction

  function automatic logic [31:0] enc_sw(
      input logic [4:0] rs2,
      input logic [4:0] rs1,
      input logic [11:0] imm12
  );
    enc_sw = {imm12[11:5], rs2, rs1, 3'b010, imm12[4:0], OP_STORE};
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
    mem_rdata = 32'hAAAA_5555;
    instr = 32'h0000_0013; // NOP
    rst = 1'b1;

    repeat (3) @(posedge clk);
    rst = 1'b0;
    @(negedge clk);

    // Build x1 = 0x4000_0000 (sensor MMIO base)
    instr = enc_lui(5'd1, 20'h40000);
    @(posedge clk);
    @(negedge clk);

    // Sensor MMIO read uses a synchronous stub response.
    // First LW primes the response path.
    instr = enc_lw(5'd3, 5'd1, 12'd0);
    #1;
    assert(dut.mmio_is_sensor) else $fatal(1, "sensor MMIO range not detected");
    assert(dut.mem_we == 1'b0) else $fatal(1, "MMIO load should not assert external mem_we");
    @(posedge clk);
    @(negedge clk);

    // Second LW should capture the updated stub response (1000 at sensor index 0).
    instr = enc_lw(5'd3, 5'd1, 12'd0);
    @(posedge clk);
    #1;
    assert(dut.rf.regs_out[3] == 32'd1000)
      else $fatal(1, "sensor MMIO load expected 1000, got %0d", dut.rf.regs_out[3]);
    @(negedge clk);

    // Sensor MMIO store should be blocked from external memory bus.
    instr = enc_addi(5'd2, 5'd0, 12'd7);
    @(posedge clk);
    @(negedge clk);
    instr = enc_sw(5'd2, 5'd1, 12'd0);
    #1;
    assert(dut.mmio_is_sensor) else $fatal(1, "sensor MMIO store range not detected");
    assert(dut.mem_we == 1'b0) else $fatal(1, "sensor MMIO store leaked to external mem_we");
    @(posedge clk);
    @(negedge clk);

    // Build x1 = 0x4000_0100 (DMA MMIO base)
    instr = enc_lui(5'd1, 20'h40000);
    @(posedge clk);
    @(negedge clk);
    instr = enc_addi(5'd1, 5'd1, 12'h100);
    @(posedge clk);
    @(negedge clk);

    // DMA MMIO store should also be blocked externally.
    instr = enc_sw(5'd2, 5'd1, 12'd0);
    #1;
    assert(dut.mmio_is_dma) else $fatal(1, "DMA MMIO range not detected");
    assert(dut.mem_we == 1'b0) else $fatal(1, "DMA MMIO store leaked to external mem_we");
    @(posedge clk);
    @(negedge clk);

    // Build x1 = 0x0000_0100 (normal memory address)
    instr = enc_addi(5'd1, 5'd0, 12'h100);
    @(posedge clk);
    @(negedge clk);

    // Normal store should assert external mem_we.
    instr = enc_sw(5'd2, 5'd1, 12'd0);
    #1;
    assert(!dut.mmio_is_sensor && !dut.mmio_is_dma) else $fatal(1, "normal memory misdetected as MMIO");
    assert(dut.mem_we == 1'b1) else $fatal(1, "normal store must assert external mem_we");

    $display("lx32_mmio_decode_tb: PASS");
    $finish;
  end

endmodule


