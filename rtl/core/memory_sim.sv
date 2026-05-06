module memory_sim (

  // ------------------------------------------------------------
  // Clock
  // ------------------------------------------------------------
  input  logic        clk,

  // ------------------------------------------------------------
  // Instruction Port (Read-Only, IRAM — 32 KiB at 0x0000_0000)
  // ------------------------------------------------------------
  input  logic [31:0] i_addr,
  output logic [31:0] i_data,

  // ------------------------------------------------------------
  // Data Port (DRAM — 64 KiB at 0x0001_0000; test mode maps to
  // the same flat array for programs smaller than 4 KiB)
  // ------------------------------------------------------------
  input  logic [31:0] d_addr,
  input  logic [31:0] d_wdata,
  input  logic        d_we,
  output logic [31:0] d_rdata

);

  // ============================================================
  // LX32 Simulation Memory
  // ============================================================
  //
  // Two separate BRAM arrays model the real hardware memory map:
  //   iram: 8192 words × 32-bit = 32 KiB  (0x0000_0000–0x0000_7FFF)
  //   dram: 16384 words × 32-bit = 64 KiB  (0x0001_0000–0x0001_FFFF)
  //
  // Test-mode compatibility:
  //   The run_program simulator loads a flat binary at address 0 and
  //   uses only the lower 12 bits for both instruction and data accesses
  //   (programs fit in 4 KiB).  The simulation transparently falls back to
  //   the iram array for data accesses that hit the IRAM region so that
  //   the existing 4 KiB single-region programs continue to work without
  //   relinking.
  //
  // Address decode:
  //   Instruction port: always indexes iram (bits[14:2] for 32 KiB).
  //   Data port:
  //     addr[31:16] == 0x0000 → iram  (IRAM region or test-mode flat binary)
  //     addr[31:16] == 0x0001 → dram  (DRAM region)
  //     otherwise             → returns 0 (MMIO handled upstream)
  // ============================================================

  localparam IRAM_WORDS = 8192;   // 32 KiB / 4 bytes
  localparam DRAM_WORDS = 16384;  // 64 KiB / 4 bytes

  logic [31:0] iram [0:IRAM_WORDS-1];
  logic [31:0] dram [0:DRAM_WORDS-1];

  // ------------------------------------------------------------
  // Initialization
  // ------------------------------------------------------------
  initial begin
    integer fd;
    for (int i = 0; i < IRAM_WORDS; i++) iram[i] = 32'h0;
    for (int i = 0; i < DRAM_WORDS; i++) dram[i] = 32'h0;

    fd = $fopen("program.hex", "r");
    if (fd != 0) begin
      $fclose(fd);
      $readmemh("program.hex", iram);  // test binaries load into IRAM
    end
  end

  // ------------------------------------------------------------
  // Instruction Port — IRAM, word-aligned
  // ------------------------------------------------------------
  logic [12:0] i_index;
  assign i_index = i_addr[14:2];   // 13-bit word index into 32 KiB
  assign i_data  = iram[i_index];

  // ------------------------------------------------------------
  // Data Port — address-decoded, word-aligned
  // ------------------------------------------------------------
  logic        d_in_iram, d_in_dram;
  logic [12:0] d_iram_idx;
  logic [13:0] d_dram_idx;

  assign d_in_iram  = (d_addr[31:15] == 17'h0);          // 0x0000_0000–0x0000_7FFF
  assign d_in_dram  = (d_addr[31:16] == 16'h0001);        // 0x0001_0000–0x0001_FFFF
  assign d_iram_idx = d_addr[14:2];
  assign d_dram_idx = d_addr[15:2];

  // Asynchronous read.
  always_comb begin
    if      (d_in_iram) d_rdata = iram[d_iram_idx];
    else if (d_in_dram) d_rdata = dram[d_dram_idx];
    else                d_rdata = 32'h0;
  end

  // Synchronous write.
  always_ff @(posedge clk) begin
    if (d_we) begin
      if      (d_in_iram) iram[d_iram_idx] <= d_wdata;
      else if (d_in_dram) dram[d_dram_idx] <= d_wdata;
    end
  end

endmodule
