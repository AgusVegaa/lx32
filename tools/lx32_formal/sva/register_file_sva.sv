module register_file_sva (
  input logic clk
);
  logic rst;

  logic [4:0] addr_rd;
  logic [31:0] data_rd;
  logic we;

  logic [31:0] data_rs1;
  logic [31:0] data_rs2;

  always_comb begin
    rst = $anyseq;
    addr_rd = $anyseq;
    data_rd = $anyseq;
    we = $anyseq;
  end

  register_file dut (
    .clk(clk),
    .rst(rst),
    .addr_rs1(5'd0),
    .addr_rs2(5'd0),
    .addr_rd(addr_rd),
    .data_rd(data_rd),
    .we(we),
    .data_rs1(data_rs1),
    .data_rs2(data_rs2)
  );

  reg f_past_valid;
  initial f_past_valid = 1'b0;

  always @(posedge clk) begin
    f_past_valid <= 1'b1;

    // Keep reset high on cycle 0 to avoid undefined temporal base.
    if (!f_past_valid) begin
      assume(rst);
    end

    // x0 must read as zero on both read ports at every cycle.
    assert(data_rs1 == 32'h0);
    assert(data_rs2 == 32'h0);

    // Even if a write is attempted to x0, x0 stays zero on the next cycle.
    if (f_past_valid && $past(!rst) && $past(we) && ($past(addr_rd) == 5'd0)) begin
      assert(data_rs1 == 32'h0);
      assert(data_rs2 == 32'h0);
    end
  end
endmodule








