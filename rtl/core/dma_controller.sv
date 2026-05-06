// dma_controller.sv — HID report DMA engine.
//
// Replaces the earlier stub with a real FSM-based transfer engine.
//
// Operation:
//   1. LX.REPORT asserts report_req with the source address in report_ptr.
//   2. The FSM moves to DMA_FETCH to read two 32-bit words (8 bytes total)
//      from the data bus (word 0 at ptr, word 1 at ptr+4).
//   3. The fetched bytes are driven to the USB endpoint write port one byte
//      per cycle in DMA_WRITE.
//   4. On completion the FSM returns to IDLE and dma_busy deasserts.
//
// Pipeline stall:
//   dma_busy is HIGH from the moment report_req is accepted until the
//   transfer is done.  lx32_system stalls the pipeline while dma_busy is
//   asserted AND a new LX.REPORT is in the EX stage, preventing report
//   corruption when back-to-back reports are issued.
//
// Bus master interface (data read path):
//   When bus_req is asserted the memory subsystem must provide bus_rdata on
//   the next cycle bus_ack is HIGH.  For the current simulation model the
//   bridge immediately acknowledges every request (single-cycle latency).

module dma_controller (
    input  logic        clk,
    input  logic        rst,

    // ── LX.REPORT datapath ────────────────────────────────────────────────
    input  logic        report_req,
    input  logic [31:0] report_ptr,
    output logic        dma_busy,

    // ── Bus master (DRAM read) ─────────────────────────────────────────────
    output logic        bus_req,
    output logic [31:0] bus_addr,
    input  logic [31:0] bus_rdata,
    input  logic        bus_ack,

    // ── USB endpoint byte-write stream ────────────────────────────────────
    output logic        usb_wr,
    output logic [2:0]  usb_byte_idx,
    output logic [7:0]  usb_wdata,

    // ── MMIO status / control registers ──────────────────────────────────
    input  logic        mmio_req,
    input  logic        mmio_we,
    input  logic [5:0]  mmio_addr,
    input  logic [31:0] mmio_wdata,
    output logic [31:0] mmio_rdata
);

  typedef enum logic [2:0] {
    DMA_IDLE   = 3'd0,
    DMA_FETCH0 = 3'd1,   // Read bytes 0–3 from DRAM
    DMA_FETCH1 = 3'd2,   // Read bytes 4–7 from DRAM
    DMA_WRITE  = 3'd3,   // Stream bytes to USB endpoint
    DMA_DONE   = 3'd4    // Notify and return to IDLE
  } dma_state_e;

  dma_state_e   state;
  logic [31:0]  word0, word1;
  logic [31:0]  xfer_addr;
  logic [2:0]   write_idx;

  assign dma_busy = (state != DMA_IDLE);

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state        <= DMA_IDLE;
      word0        <= 32'h0;
      word1        <= 32'h0;
      xfer_addr    <= 32'h0;
      write_idx    <= 3'd0;
      bus_req      <= 1'b0;
      bus_addr     <= 32'h0;
      usb_wr       <= 1'b0;
      usb_byte_idx <= 3'd0;
      usb_wdata    <= 8'h0;
      mmio_rdata   <= 32'h0;
    end else begin
      // Default de-assert.
      bus_req <= 1'b0;
      usb_wr  <= 1'b0;

      case (state)
        // ── IDLE ─────────────────────────────────────────────────────────
        DMA_IDLE: begin
          if (report_req) begin
            xfer_addr <= report_ptr;
            state     <= DMA_FETCH0;
          end
          // MMIO-triggered transfer (e.g. firmware polling write).
          if (mmio_req && mmio_we && mmio_addr == 6'h01) begin
            xfer_addr <= mmio_wdata;
            state     <= DMA_FETCH0;
          end
        end

        // ── Fetch word 0 (bytes 0–3) ─────────────────────────────────────
        DMA_FETCH0: begin
          bus_req  <= 1'b1;
          bus_addr <= xfer_addr;
          if (bus_ack) begin
            word0 <= bus_rdata;
            state <= DMA_FETCH1;
          end
        end

        // ── Fetch word 1 (bytes 4–7) ─────────────────────────────────────
        DMA_FETCH1: begin
          bus_req  <= 1'b1;
          bus_addr <= xfer_addr + 32'd4;
          if (bus_ack) begin
            word1     <= bus_rdata;
            write_idx <= 3'd0;
            state     <= DMA_WRITE;
          end
        end

        // ── Write 8 bytes to USB endpoint ─────────────────────────────────
        DMA_WRITE: begin
          usb_wr       <= 1'b1;
          usb_byte_idx <= write_idx;
          case (write_idx)
            3'd0: usb_wdata <= word0[7:0];
            3'd1: usb_wdata <= word0[15:8];
            3'd2: usb_wdata <= word0[23:16];
            3'd3: usb_wdata <= word0[31:24];
            3'd4: usb_wdata <= word1[7:0];
            3'd5: usb_wdata <= word1[15:8];
            3'd6: usb_wdata <= word1[23:16];
            3'd7: usb_wdata <= word1[31:24];
          endcase
          write_idx <= write_idx + 3'd1;
          if (write_idx == 3'd7)
            state <= DMA_DONE;
        end

        // ── Done — one-cycle pulse then back to IDLE ───────────────────────
        DMA_DONE: state <= DMA_IDLE;

        default: state <= DMA_IDLE;
      endcase

      // ── MMIO read ──────────────────────────────────────────────────────
      if (mmio_req && !mmio_we) begin
        unique case (mmio_addr)
          6'h00: mmio_rdata <= {31'h0, dma_busy};
          6'h01: mmio_rdata <= xfer_addr;
          default: mmio_rdata <= 32'hBEEF_DEAD;
        endcase
      end
    end
  end

// ── Formal / simulation assertions ────────────────────────────────────────────
//
// Checked by Verilator (--assert) and SymbiYosys.  Each property is disabled
// during reset so the solver does not have to reason about reset transients.
//
// Registered-output note: bus_req and usb_wr are set in the always_ff block
// based on the CURRENT state, so at any posedge their value reflects the
// previous cycle's state.  $past is used accordingly.

/* verilator lint_off SYNCASYNCNET */
`ifndef SYNTHESIS

  // dma_busy is defined as (state != DMA_IDLE); these must always agree.
  ap_busy_iff_not_idle: assert property (
    @(posedge clk) disable iff (rst)
    dma_busy == (state != DMA_IDLE)
  );

  // bus_req may only be high when we were in a fetch state last cycle.
  ap_bus_req_only_from_fetch: assert property (
    @(posedge clk) disable iff (rst)
    bus_req |-> $past(state == DMA_FETCH0 || state == DMA_FETCH1)
  );

  // usb_wr may only be high when we were in the write state last cycle.
  ap_usb_wr_only_from_write: assert property (
    @(posedge clk) disable iff (rst)
    usb_wr |-> $past(state == DMA_WRITE)
  );

  // DMA_DONE is a single-cycle state; it unconditionally returns to IDLE.
  ap_done_to_idle: assert property (
    @(posedge clk) disable iff (rst)
    (state == DMA_DONE) |=> (state == DMA_IDLE)
  );

  // Accepting report_req in IDLE must trigger FETCH0 on the very next cycle.
  ap_req_starts_fetch0: assert property (
    @(posedge clk) disable iff (rst)
    (state == DMA_IDLE && report_req && !mmio_req) |=> (state == DMA_FETCH0)
  );

  // write_idx is reset to 0 when transitioning from FETCH1 into WRITE.
  // (registered-output: both state and write_idx are committed by the same always_ff)
  ap_write_idx_starts_zero: assert property (
    @(posedge clk) disable iff (rst)
    ($past(state) == DMA_FETCH1 && state == DMA_WRITE) |-> (write_idx == 3'd0)
  );

  // Last byte written transitions directly to DONE.
  ap_last_byte_then_done: assert property (
    @(posedge clk) disable iff (rst)
    (state == DMA_WRITE && write_idx == 3'd7) |=> (state == DMA_DONE)
  );

`endif
/* verilator lint_on SYNCASYNCNET */

endmodule
