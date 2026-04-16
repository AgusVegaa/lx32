package lx32_mmio_pkg;
  // Peripheral control register windows (256 bytes each)
  localparam logic [31:0] SENSOR_CTRL_BASE = 32'h4000_0000;
  localparam logic [31:0] SENSOR_CTRL_END  = 32'h4000_00FF;
  localparam logic [31:0] DMA_CTRL_BASE    = 32'h4000_0100;
  localparam logic [31:0] DMA_CTRL_END     = 32'h4000_01FF;
  // Sensor data buffer base address (64 KiB read window)
  localparam logic [31:0] SENSOR_DATA_BASE = 32'h5000_0000;
endpackage
