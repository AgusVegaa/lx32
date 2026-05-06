// usb_hid_bridge.sv — RTL stub for the USB HID controller MMIO interface.
//
// In simulation this module absorbs MMIO writes and returns zeros on reads.
// On FPGA, replace this stub with a proper bridge to the LUNA USB core
// (tools/luna_usb/pulsar_hid.py).
//
// MMIO register map (base USB_CTRL_BASE = 0x4000_0200):
//   0x00 (R):  status — bit[0]=busy (IN transfer in progress), bit[1]=sof_pending
//   0x04 (W):  report_lo — report bytes [3:0] (LSB first)
//   0x08 (W):  report_hi — report bytes [7:4] (LSB first)
//   0x0C (W):  trigger — write 1 to submit the buffered report as an IN packet
//
// The LX32K DMA engine drives report_lo + report_hi then pulses trigger.
// The USB core serialises the 8-byte report on the next available IN token.

module usb_hid_bridge (
  input  logic        clk,
  input  logic        rst,

  // MMIO interface
  input  logic        mmio_req,
  input  logic        mmio_we,
  input  logic [5:0]  mmio_addr,
  input  logic [31:0] mmio_wdata,
  output logic [31:0] mmio_rdata,

  // USB status outputs (driven by real USB core on FPGA)
  output logic        sof_irq,       // one-cycle pulse per USB SOF
  output logic        usb_busy,      // IN transfer in progress

  // Buffered 8-byte HID report (readable by external USB core)
  output logic [63:0] hid_report,    // bytes [7:0], byte 0 in bits [7:0]
  output logic        hid_report_valid  // pulsed for one cycle when trigger fires
);

  // ── Internal state ────────────────────────────────────────────────────────
  logic [63:0] report_buf;
  logic        trigger;
  logic        sof_counter_en;   // stub: no real SOF; tie sof_irq to 0
  logic        busy_reg;

  // ── SOF stub: always deasserted in simulation ─────────────────────────────
  assign sof_irq  = 1'b0;
  assign usb_busy = busy_reg;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      report_buf      <= 64'h0;
      busy_reg        <= 1'b0;
      hid_report_valid <= 1'b0;
    end else begin
      hid_report_valid <= 1'b0;   // default: deassert each cycle

      if (mmio_req && mmio_we) begin
        case (mmio_addr)
          6'h01: report_buf[31: 0] <= mmio_wdata;   // bytes 0-3
          6'h02: report_buf[63:32] <= mmio_wdata;   // bytes 4-7
          6'h03: if (mmio_wdata[0]) begin
            // Trigger: latch report and signal the USB core.
            hid_report       <= report_buf;
            hid_report_valid <= 1'b1;
            busy_reg         <= 1'b1;
          end
          default: ;
        endcase
      end

      // In simulation, busy clears immediately (no real USB transfer).
      if (hid_report_valid)
        busy_reg <= 1'b0;
    end
  end

  // ── MMIO read path ────────────────────────────────────────────────────────
  always_ff @(posedge clk or posedge rst) begin
    if (rst)
      mmio_rdata <= 32'h0;
    else if (mmio_req && !mmio_we) begin
      case (mmio_addr)
        6'h00:   mmio_rdata <= {30'h0, 1'b0 /*sof_pending*/, busy_reg};
        default: mmio_rdata <= 32'h0;
      endcase
    end
  end

endmodule
