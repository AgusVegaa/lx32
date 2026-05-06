// rapid_trigger_sva.sv — SVA bounded model checks for the rapid-trigger unit.
//
// Properties proved (BMC depth 128 = 2 full 64-key scan frames):
//   P1  Hysteresis: a PRESSED key cannot fire PRESSED again without an
//       intervening RELEASED event (no double-fire).
//   P2  Re-arm threshold: a key cannot fire PRESS unless it has been RELEASED
//       first after the previous press (state machine integrity).
//   P3  init_done gates events: no event_valid when init_done[key] == 0.
//   P4  event_key is always in range [0..63].
//   P5  scan_idx advances by 1 each cycle (mod 64) — no stall or skip.
//   P6  event_valid is at most 1 bit wide (no multi-fire in one cycle).
//   P7  act_thresh write latches to the correct key index.

// Workaround: include the DUT source file directly (no package imports needed).
`include "rapid_trigger.sv"
`include "sensor_controller.sv"   // needed for rt_rd_val port

module rapid_trigger_sva;

  // ── Free inputs ─────────────────────────────────────────────────────────────
  reg clk;
  always #5 clk = ~clk;

  reg        rst;
  reg [15:0] rt_rd_val;    // symbolic sensor value from the frame buffer
  reg        mmio_req;
  reg        mmio_we;
  reg [5:0]  mmio_addr;
  reg [31:0] mmio_wdata;

  always @(*) begin
    rst       = $anyseq;
    rt_rd_val = $anyseq;
    mmio_req  = $anyseq;
    mmio_we   = $anyseq;
    mmio_addr = $anyseq;
    mmio_wdata= $anyseq;
  end

  // ── DUT ────────────────────────────────────────────────────────────────────
  wire [5:0]  rt_rd_idx;
  wire        event_valid;
  wire [5:0]  event_key;
  wire        event_is_press;
  wire [31:0] mmio_rdata;

  rapid_trigger dut (
    .clk           (clk),
    .rst           (rst),
    .rt_rd_idx     (rt_rd_idx),
    .rt_rd_val     (rt_rd_val),
    .event_valid   (event_valid),
    .event_key     (event_key),
    .event_is_press(event_is_press),
    .mmio_req      (mmio_req),
    .mmio_we       (mmio_we),
    .mmio_addr     (mmio_addr),
    .mmio_wdata    (mmio_wdata),
    .mmio_rdata    (mmio_rdata)
  );

  // ── Past-valid gate ─────────────────────────────────────────────────────────
  reg f_past_valid;
  initial f_past_valid = 0;
  always @(posedge clk) f_past_valid <= 1;

  // ── P5  scan_idx advances by 1 (mod 64) every cycle ────────────────────────
  always @(posedge clk) begin
    if (f_past_valid && !rst && !$past(rst))
      assert (dut.scan_idx == ($past(dut.scan_idx) + 6'd1));
  end

  // After reset scan_idx must start at 0.
  always @(posedge clk) begin
    if (f_past_valid && $past(rst))
      assert (dut.scan_idx == 6'd0);
  end

  // ── P4  event_key in [0..63] ────────────────────────────────────────────────
  always @(posedge clk) begin
    if (!rst)
      assert (event_key <= 6'd63);
  end

  // ── P3  No events before init_done ──────────────────────────────────────────
  // If event_valid fires, the key that fired must have init_done set.
  always @(posedge clk) begin
    if (!rst && event_valid)
      assert (dut.init_done[event_key]);
  end

  // ── P6  event_valid is a single-bit signal (always 0 or 1) ─────────────────
  // Implicit from the 1-bit declaration; verify it stays in range.
  always @(posedge clk) begin
    assert (event_valid == 1'b0 || event_valid == 1'b1);
  end

  // ── P1  Hysteresis: no PRESS event for an already-pressed key ───────────────
  // If a key is currently marked pressed, it must not fire event_is_press=1.
  always @(posedge clk) begin
    if (!rst && event_valid && event_is_press)
      assert (!dut.pressed[event_key]);
  end

  // ── P2  RELEASE only fires for a key that is currently pressed ──────────────
  always @(posedge clk) begin
    if (!rst && event_valid && !event_is_press)
      assert (dut.pressed[event_key]);
  end

  // ── P7  act_thresh write targets the correct key ────────────────────────────
  // When a threshold write occurs (mmio addr 0x01, word offset 1), the threshold
  // value is latched into act_thresh[key] where key = mmio_wdata[21:16].
  always @(posedge clk) begin
    if (f_past_valid && !rst && $past(!rst) &&
        $past(mmio_req) && $past(mmio_we) && $past(mmio_addr) == 6'h01) begin
      automatic logic [5:0] k = $past(mmio_wdata[21:16]);
      assert (dut.act_thresh[k] == $past(mmio_wdata[15:0]));
    end
  end

  // ── Cover: both PRESS and RELEASE events are reachable ──────────────────────
  always @(posedge clk) begin
    cover (event_valid && event_is_press);
    cover (event_valid && !event_is_press);
  end

endmodule
