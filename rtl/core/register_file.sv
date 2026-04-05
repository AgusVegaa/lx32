module register_file (
  // ------------------------------------------------------------
  // Clock & Reset
  // ------------------------------------------------------------
  input  logic        clk,
  input  logic        rst,

  // ------------------------------------------------------------
  // Read Addresses
  // ------------------------------------------------------------
  input  logic [4:0]  addr_rs1,
  input  logic [4:0]  addr_rs2,

  // ------------------------------------------------------------
  // Write Port
  // ------------------------------------------------------------
  input  logic [4:0]  addr_rd,
  input  logic [31:0] data_rd,
  input  logic        we,

  // ------------------------------------------------------------
  // Read Data Outputs
  // ------------------------------------------------------------
  output logic [31:0] data_rs1,
  output logic [31:0] data_rs2
);

  // ============================================================
  // LX32 Register File (RV32I)
  // ============================================================
  // - 32 registers (x0–x31), 32-bit wide.
  // - x0 is hardwired to zero (read-only).
  // - Dual asynchronous read ports for combinational decode.
  // - Single synchronous write port.
  // ============================================================

  // ------------------------------------------------------------
  // Internal Register Storage (x0-x31)
  // ------------------------------------------------------------
  logic [31:0] regs_out [31:0];

  // x0 is always hardwired to zero
  assign regs_out[0] = 32'h0;

  // ------------------------------------------------------------
  // One-Hot Write Decoder
  // ------------------------------------------------------------
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] write_en;
  /* verilator lint_on UNUSEDSIGNAL */

  assign write_en = (we && (addr_rd != 5'd0)) ? (32'b1 << addr_rd) : 32'b0;

  // ------------------------------------------------------------
  // Register Generation (x1 to x31)
  // ------------------------------------------------------------
  genvar i;
  generate
    for (i = 1; i < 32; i++) begin : gen_registers
      reg_generic #(
        .WIDTH(32)
      ) reg_inst (
        .clk      (clk),
        .rst      (rst),
        .en       (write_en[i]),
        .data_in  (data_rd),
        .data_out (regs_out[i])
      );
    end
  endgenerate

  // ------------------------------------------------------------
  // Asynchronous Read Ports
  // ------------------------------------------------------------
  assign data_rs1 = regs_out[addr_rs1];
  assign data_rs2 = regs_out[addr_rs2];

endmodule
