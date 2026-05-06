// interrupt_controller.sv — Minimal interrupt controller for LX32K.
//
// Three MMIO registers (base INTC_BASE = 0x4000_0700):
//   0x00 (R/W): irq_enable  — bit N enables IRQ source N (8 sources)
//   0x04 (R/W): irq_pending — bit N is set when source N fires; write 1 to clear
//   0x08 (R):   irq_status  — bit N = irq_enable[N] & irq_pending[N]
//
// The single irq_out signal asserts when (irq_enable & irq_pending) != 0.
// Wire this to the CPU's irq_in port; the CPU stalls in LX.WAKE mode until
// irq_out asserts, then resumes execution and the firmware reads irq_status
// to identify the source.
//
// IRQ source assignments:
//   [0] USB SOF   (1-kHz pulse from USB core)
//   [1] DMA done  (transfer complete)
//   [2:7] reserved

module interrupt_controller (
  input  logic       clk,
  input  logic       rst,

  // Interrupt source inputs (level or pulse, all active-high)
  input  logic [7:0] irq_src,

  // Interrupt output to CPU
  output logic       irq_out,

  // MMIO interface
  input  logic       mmio_req,
  input  logic       mmio_we,
  input  logic [5:0] mmio_addr,
  input  logic [31:0] mmio_wdata,
  output logic [31:0] mmio_rdata
);

  logic [7:0] irq_enable;
  logic [7:0] irq_pending;

  assign irq_out = |(irq_enable & irq_pending);

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      irq_enable  <= 8'h0;
      irq_pending <= 8'h0;
      mmio_rdata  <= 32'h0;
    end else begin
      // Latch new interrupt sources into pending (set-only from hardware).
      irq_pending <= irq_pending | irq_src;

      if (mmio_req && mmio_we) begin
        unique case (mmio_addr)
          6'h00: irq_enable  <= mmio_wdata[7:0];
          6'h01: irq_pending <= irq_pending & ~mmio_wdata[7:0]; // write-1-to-clear
          default: ;
        endcase
      end

      if (mmio_req && !mmio_we) begin
        unique case (mmio_addr)
          6'h00: mmio_rdata <= {24'h0, irq_enable};
          6'h01: mmio_rdata <= {24'h0, irq_pending};
          6'h02: mmio_rdata <= {24'h0, irq_enable & irq_pending};
          default: mmio_rdata <= 32'h0;
        endcase
      end
    end
  end

endmodule
