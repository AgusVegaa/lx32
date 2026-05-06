// rapid_trigger.sv — Hardware rapid-trigger key comparator.
//
// Autonomously scans all 64 sensor keys (one per clock cycle) and fires
// press/release events without any firmware scan loop.
//
// Algorithm per key:
//   Not pressed: track local_min. Fire PRESS  when val - local_min > act_thresh.
//   Pressed:     track local_max. Fire RELEASE when local_max - val > rst_thresh.
//
// An init_done flag gates events until each key has been seen at least once,
// preventing spurious events at power-on.
//
// MMIO register map (base RT_CTRL_BASE = 0x4000_0500):
//   0x00 (R):    event — {valid[31], 23'd0, key[7:2], 1'd0, is_press[0]}
//                        Reading clears the valid bit on the next posedge.
//   0x04 (W):    actuation threshold: {key[23:16], threshold[15:0]}
//   0x08 (W):    reset threshold:     {key[23:16], threshold[15:0]}
//   0x0C (W):    control: bit[0]=1 clears all key state + event
//   0x10 (R):    status: {26'd0, scan_idx[5:0]}

module rapid_trigger (
  input  logic        clk,
  input  logic        rst,

  // Combinatorial read port into the stable sensor frame buffer.
  output logic [5:0]  rt_rd_idx,
  input  logic [15:0] rt_rd_val,

  // Event outputs (mirrored to MMIO word 0).
  output logic        event_valid,
  output logic [5:0]  event_key,
  output logic        event_is_press,

  // MMIO interface
  input  logic        mmio_req,
  input  logic        mmio_we,
  input  logic [5:0]  mmio_addr,
  input  logic [31:0] mmio_wdata,
  output logic [31:0] mmio_rdata
);

  localparam logic [15:0] DEFAULT_ACT = 16'd120;
  localparam logic [15:0] DEFAULT_RST = 16'd80;

  // Per-key state
  logic [15:0] act_thresh [0:63];
  logic [15:0] rst_thresh [0:63];
  logic [15:0] local_min  [0:63];
  logic [15:0] local_max  [0:63];
  logic        pressed     [0:63];
  logic        init_done   [0:63];   // gating flag: true after first sample

  logic [5:0] scan_idx;
  assign rt_rd_idx = scan_idx;

  // Combinatorial signals for the current scan key.
  wire [15:0] s_val  = rt_rd_val;
  wire        s_init = init_done[scan_idx];
  wire        s_pre  = pressed[scan_idx];

  // Extended subtraction detects unsigned underflow via the borrow bit [16].
  wire [16:0] rise_ext = {1'b0, s_val}             - {1'b0, local_min[scan_idx]};
  wire [16:0] fall_ext = {1'b0, local_max[scan_idx]} - {1'b0, s_val};
  wire [15:0] s_rise   = rise_ext[15:0];
  wire [15:0] s_fall   = fall_ext[15:0];
  wire        rise_ok  = !rise_ext[16];
  wire        fall_ok  = !fall_ext[16];

  wire do_press   = s_init && !s_pre && rise_ok && (s_rise > act_thresh[scan_idx]);
  wire do_release = s_init &&  s_pre && fall_ok && (s_fall > rst_thresh[scan_idx]);

  // Reading the event register (word 0) clears event_valid next posedge.
  wire event_rd_ack = mmio_req && !mmio_we && (mmio_addr == 6'h00);

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      scan_idx       <= 6'd0;
      event_valid    <= 1'b0;
      event_key      <= 6'd0;
      event_is_press <= 1'b0;
      for (int i = 0; i < 64; i++) begin
        act_thresh[i] <= DEFAULT_ACT;
        rst_thresh[i] <= DEFAULT_RST;
        local_min[i]  <= 16'h0;
        local_max[i]  <= 16'h0;
        pressed[i]    <= 1'b0;
        init_done[i]  <= 1'b0;
      end
    end else begin
      scan_idx <= scan_idx + 6'd1;

      // First sample: seed both extremes so deltas start from a known state.
      if (!s_init) begin
        local_min[scan_idx] <= s_val;
        local_max[scan_idx] <= s_val;
        init_done[scan_idx] <= 1'b1;
      end else if (!s_pre) begin
        if (s_val < local_min[scan_idx]) local_min[scan_idx] <= s_val;
      end else begin
        if (s_val > local_max[scan_idx]) local_max[scan_idx] <= s_val;
      end

      // Key state transitions.
      if (do_press) begin
        pressed[scan_idx]   <= 1'b1;
        local_max[scan_idx] <= s_val;   // start max tracking from actuation point
      end else if (do_release) begin
        pressed[scan_idx]   <= 1'b0;
        local_min[scan_idx] <= s_val;   // start min tracking from release point
      end

      // Event register: new event wins over read-ack; read-ack wins over idle.
      if (do_press || do_release) begin
        event_valid    <= 1'b1;
        event_key      <= scan_idx;
        event_is_press <= do_press;
      end else if (event_rd_ack) begin
        event_valid <= 1'b0;
      end

      // MMIO write handlers.
      if (mmio_req && mmio_we) begin
        case (mmio_addr)
          6'h01: act_thresh[mmio_wdata[21:16]] <= mmio_wdata[15:0];
          6'h02: rst_thresh[mmio_wdata[21:16]] <= mmio_wdata[15:0];
          6'h03: if (mmio_wdata[0]) begin
            event_valid <= 1'b0;
            for (int i = 0; i < 64; i++) begin
              pressed[i]   <= 1'b0;
              init_done[i] <= 1'b0;
            end
          end
          default: ;
        endcase
      end
    end
  end

  // MMIO read path (combinatorial — no extra latency on event register).
  always_comb begin
    mmio_rdata = 32'h0;
    if (mmio_req && !mmio_we) begin
      case (mmio_addr)
        6'h00:   mmio_rdata = {event_valid, 23'h0, event_key, 1'b0, event_is_press};
        6'h04:   mmio_rdata = {26'h0, scan_idx};
        default: mmio_rdata = 32'h0;
      endcase
    end
  end

// ── Formal / simulation assertions ────────────────────────────────────────────
//
// All assertions are over the CURRENT scan slot (scan_idx).  Because the
// scanner visits each key exactly once per 64 cycles, properties on per-key
// arrays are written in terms of the combinatorial signals that the always_ff
// block uses to update the slot being processed this cycle.

/* verilator lint_off SYNCASYNCNET */
`ifndef SYNTHESIS

  // do_press and do_release are strictly mutually exclusive.
  ap_no_simultaneous_event: assert property (
    @(posedge clk) disable iff (rst)
    !(do_press && do_release)
  );

  // A press event can only fire when the key was idle.
  ap_press_requires_idle: assert property (
    @(posedge clk) disable iff (rst)
    do_press |-> !s_pre
  );

  // A release event can only fire when the key was pressed.
  ap_release_requires_pressed: assert property (
    @(posedge clk) disable iff (rst)
    do_release |-> s_pre
  );

  // Neither event fires before the key has been initialised.
  ap_no_event_before_init: assert property (
    @(posedge clk) disable iff (rst)
    !s_init |-> (!do_press && !do_release)
  );

  // After a press, local_max for that key is seeded from the actuation value.
  // $past(scan_idx) identifies the key that fired in the previous cycle.
  ap_press_seeds_local_max: assert property (
    @(posedge clk) disable iff (rst)
    do_press |=> (local_max[$past(scan_idx)] == $past(s_val))
  );

  // After a release, local_min for that key is seeded from the release value.
  ap_release_seeds_local_min: assert property (
    @(posedge clk) disable iff (rst)
    do_release |=> (local_min[$past(scan_idx)] == $past(s_val))
  );

  // A press requires the rise to exceed the actuation threshold (hysteresis).
  ap_press_above_act_thresh: assert property (
    @(posedge clk) disable iff (rst)
    do_press |-> (s_rise > act_thresh[scan_idx])
  );

  // A release requires the fall to exceed the reset threshold (hysteresis).
  ap_release_above_rst_thresh: assert property (
    @(posedge clk) disable iff (rst)
    do_release |-> (s_fall > rst_thresh[scan_idx])
  );

`endif
/* verilator lint_on SYNCASYNCNET */

endmodule
