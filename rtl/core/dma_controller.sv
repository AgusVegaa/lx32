module dma_controller (
	input  logic        clk,
	input  logic        rst,

	// LX.REPORT datapath interface
	input  logic        report_req,
	input  logic [31:0] report_ptr,

	// MMIO stub interface
	input  logic        mmio_req,
	input  logic        mmio_we,
	input  logic [5:0]  mmio_addr,   // word offset within 256-byte window (addr[7:2])
	input  logic [31:0] mmio_wdata,
	output logic [31:0] mmio_rdata
);

  logic [31:0] last_report_ptr;

  always_ff @(posedge clk or posedge rst) begin
	if (rst) begin
	  last_report_ptr <= 32'h0;
	  mmio_rdata      <= 32'h0;
	end else begin
	  if (report_req)
		last_report_ptr <= report_ptr;

	  if (mmio_req) begin
		if (mmio_we) begin
		  // Stub accepts writes but does not execute real DMA transfer yet.
		  last_report_ptr <= mmio_wdata;
		end else begin
		  unique case (mmio_addr)
			6'h00: mmio_rdata <= 32'h0;           // busy — always idle in stub
			6'h01: mmio_rdata <= last_report_ptr;
			default: mmio_rdata <= 32'hBEEF_DEAD;
		  endcase
		end
	  end
	end
  end

endmodule
