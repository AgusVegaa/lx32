module memory_sim (

  // ------------------------------------------------------------
  // Clock
  // ------------------------------------------------------------
  input  logic        clk,

  // ------------------------------------------------------------
  // Instruction Port (Read-Only)
  // ------------------------------------------------------------
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [31:0] i_addr,
  output logic [31:0] i_data,

  // ------------------------------------------------------------
  // Data Port
  // ------------------------------------------------------------
  input  logic [31:0] d_addr,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic [31:0] d_wdata,
  input  logic        d_we,
  output logic [31:0] d_rdata

);

  // ============================================================
  // LX32 Simulation Memory
  // ============================================================
  // Dual-port memory model for RV32I core simulation.
  //
  // Features:
  //   - 4 KB total memory (1024 x 32-bit words)
  //   - Word-aligned addressing
  //   - Asynchronous read
  //   - Synchronous write
  //   - Program preload via $readmemh
  //
  // Design Principles:
  //   - Tool-friendly (no latches)
  //   - Deterministic behavior
  //   - ISA-aligned word indexing
  //   - Clean separation of instruction/data ports
  // ============================================================


  // ------------------------------------------------------------
  // Memory Array
  // ------------------------------------------------------------
  logic [31:0] ram [0:1023];


  // ------------------------------------------------------------
  // Initialization
  // ------------------------------------------------------------
  initial begin
    integer i;
    integer program_fd;

    for (i = 0; i < 1024; i++)
      ram[i] = 32'b0;

    // Load an external image only when available; otherwise keep zeroed memory.
    program_fd = $fopen("program.hex", "r");
    if (program_fd != 0) begin
      $fclose(program_fd);
      $readmemh("program.hex", ram);
    end
  end


  // ------------------------------------------------------------
  // Word-Aligned Address Decode
  // ------------------------------------------------------------
  // RV32I instructions are 32-bit aligned.
  // Bits [1:0] are ignored.
  // ------------------------------------------------------------
  logic [9:0] i_index;
  logic [9:0] d_index;

  assign i_index = i_addr[11:2];
  assign d_index = d_addr[11:2];


  // ------------------------------------------------------------
  // Asynchronous Read
  // ------------------------------------------------------------
  assign i_data  = ram[i_index];
  assign d_rdata = ram[d_index];


  // ------------------------------------------------------------
  // Synchronous Write
  // ------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (d_we)
      ram[d_index] <= d_wdata;
  end

endmodule
