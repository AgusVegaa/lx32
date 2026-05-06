package lx32_mmio_pkg;
  // ── Instruction and Data BRAM ──────────────────────────────────────────────
  localparam logic [31:0] IRAM_BASE        = 32'h0000_0000;
  localparam logic [31:0] IRAM_END         = 32'h0000_7FFF;  // 32 KiB
  localparam logic [31:0] DRAM_BASE        = 32'h0001_0000;
  localparam logic [31:0] DRAM_END         = 32'h0001_FFFF;  // 64 KiB

  // ── Peripheral control register windows (256 bytes each) ──────────────────
  localparam logic [31:0] SENSOR_CTRL_BASE = 32'h4000_0000;
  localparam logic [31:0] SENSOR_CTRL_END  = 32'h4000_00FF;
  localparam logic [31:0] DMA_CTRL_BASE    = 32'h4000_0100;
  localparam logic [31:0] DMA_CTRL_END     = 32'h4000_01FF;
  localparam logic [31:0] USB_CTRL_BASE    = 32'h4000_0200;
  localparam logic [31:0] USB_CTRL_END     = 32'h4000_02FF;
  localparam logic [31:0] OLED_CTRL_BASE   = 32'h4000_0300;
  localparam logic [31:0] OLED_CTRL_END    = 32'h4000_03FF;
  localparam logic [31:0] TIMER_BASE       = 32'h4000_0400;
  localparam logic [31:0] TIMER_END        = 32'h4000_04FF;
  localparam logic [31:0] RT_CTRL_BASE     = 32'h4000_0500;
  localparam logic [31:0] RT_CTRL_END      = 32'h4000_05FF;
  localparam logic [31:0] GPIO_BASE        = 32'h4000_0600;
  localparam logic [31:0] GPIO_END         = 32'h4000_06FF;
  localparam logic [31:0] INTC_BASE        = 32'h4000_0700;
  localparam logic [31:0] INTC_END         = 32'h4000_07FF;

  // ── Sensor data buffer (64 KiB, double-buffered) ──────────────────────────
  localparam logic [31:0] SENSOR_DATA_BASE = 32'h5000_0000;
  localparam logic [31:0] SENSOR_DATA_END  = 32'h5000_FFFF;
  // Each half of the double-buffer is 32 KiB.
  localparam logic [31:0] SENSOR_BUF_HALF  = 32'h0000_8000;
endpackage
