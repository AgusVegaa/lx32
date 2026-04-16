module sensor_controller (
	input  logic        clk,
	input  logic        rst,

	// Direct custom-instruction datapath interface
	input  logic [5:0]  sensor_idx,
	output logic [15:0] sensor_val,
	output logic [31:0] matrix_ptr,
	output logic [15:0] delta_val,
	input  logic [31:0] chord_mask,
	output logic        chord_match,

	// MMIO stub interface
	input  logic        mmio_req,
	input  logic        mmio_we,
	input  logic [5:0]  mmio_addr,   // word offset within 256-byte window (addr[7:2])
	output logic [31:0] mmio_rdata
);

  import lx32_mmio_pkg::SENSOR_DATA_BASE;

  logic [15:0] sensors      [0:63];
  logic [15:0] prev_sensors [0:63];
  logic [31:0] active_keys;

  always_comb begin
	for (int i = 0; i < 64; i++) begin
	  sensors[i] = 16'd1000 + i[15:0];
	  prev_sensors[i] = 16'd980 + i[15:0];
	end

	active_keys = 32'h0000_00FF;
  end

  assign sensor_val  = sensors[sensor_idx];
  assign delta_val   = sensors[sensor_idx] - prev_sensors[sensor_idx];
  assign matrix_ptr  = SENSOR_DATA_BASE;
  assign chord_match = ((active_keys & chord_mask) == chord_mask);

  always_ff @(posedge clk or posedge rst) begin
	if (rst) begin
	  mmio_rdata <= 32'h0;
	end else begin
	  if (mmio_req && !mmio_we) begin
		unique case (mmio_addr)
		  6'h00: mmio_rdata <= {16'h0, sensor_val};
		  6'h01: mmio_rdata <= matrix_ptr;
		  6'h02: mmio_rdata <= {16'h0, delta_val};
		  6'h03: mmio_rdata <= active_keys;
		  default: mmio_rdata <= 32'hDEAD_BEEF;
		endcase
	  end
	end
  end

endmodule
