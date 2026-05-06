// lx32_soc.sv — Complete LX32K System-on-Chip top module.
//
// Instantiates and wires all SoC components:
//   lx32_system  — 2-stage pipelined CPU core
//   memory_sim   — IRAM (32 KiB) + DRAM (64 KiB) simulation BRAM model
//
// Address map (mirrors docs/lx32k/memory_map.md):
//   0x0000_0000–0x0000_7FFF  IRAM  (instruction + data)
//   0x0001_0000–0x0001_FFFF  DRAM  (data only)
//   0x4000_0000–0x4000_00FF  sensor_controller MMIO
//   0x4000_0100–0x4000_01FF  dma_controller MMIO
//   0x4000_0200–0x4000_02FF  USB HID controller MMIO (stub)
//   0x4000_0300–0x4000_03FF  OLED SPI controller MMIO (stub)
//   0x4000_0400–0x4000_04FF  Timer MMIO (stub)
//   0x5000_0000–0x5000_FFFF  Sensor data buffer (sensor_controller owned)
//
// The sensor controller, DMA controller, and USB/OLED/timer stubs are
// instantiated inside lx32_system via its internal MMIO decode.  This
// top module only connects the CPU to its instruction and data memories.

module lx32_soc (
  input  logic clk,
  input  logic rst
);

  import lx32_mmio_pkg::*;

  // ── Instruction bus ────────────────────────────────────────────────────────
  logic [31:0] pc;
  logic [31:0] instr;

  // ── Data bus ───────────────────────────────────────────────────────────────
  logic [31:0] mem_addr;
  logic [31:0] mem_wdata;
  logic [31:0] mem_rdata;
  logic        mem_we;

  // ── CPU core ───────────────────────────────────────────────────────────────
  lx32_system cpu (
    .clk         (clk),
    .rst         (rst),
    .pc_out      (pc),
    .instr       (instr),
    .mem_addr    (mem_addr),
    .mem_wdata   (mem_wdata),
    .mem_rdata   (mem_rdata),
    .mem_we      (mem_we),
    .debug_stall (1'b0),   // not needed in production hardware
    .gpio_out    ()        // unconnected in sim; route to FPGA pins in synthesis
  );

  // ── Memory subsystem ───────────────────────────────────────────────────────
  // The simulation memory model routes data accesses based on address range.
  // MMIO accesses (0x4000_0000+) return 0 from the memory model; the CPU's
  // internal MMIO decoder provides the real response.
  memory_sim mem (
    .clk     (clk),
    .i_addr  (pc),
    .i_data  (instr),
    .d_addr  (mem_addr),
    .d_wdata (mem_wdata),
    .d_we    (mem_we),
    .d_rdata (mem_rdata)
  );

endmodule
