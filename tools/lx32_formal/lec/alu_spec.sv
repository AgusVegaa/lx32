module alu_spec #(
  parameter int WIDTH = 32
) (
  input  logic [WIDTH-1:0]       src_a,
  input  logic [WIDTH-1:0]       src_b,
  input  lx32_alu_pkg::alu_op_e  alu_control,
  output logic [WIDTH-1:0]       alu_result
);
  logic [$clog2(WIDTH)-1:0] shamt;
  assign shamt = src_b[$clog2(WIDTH)-1:0];

  always_comb begin
    alu_result = '0;
    case (alu_control)
      lx32_alu_pkg::ALU_ADD:  alu_result = src_a + src_b;
      lx32_alu_pkg::ALU_SUB:  alu_result = src_a - src_b;
      lx32_alu_pkg::ALU_SLL:  alu_result = src_a << shamt;
      lx32_alu_pkg::ALU_SRL:  alu_result = src_a >> shamt;
      lx32_alu_pkg::ALU_SRA:  alu_result = $signed(src_a) >>> shamt;
      lx32_alu_pkg::ALU_SLT:  alu_result = {{(WIDTH-1){1'b0}}, ($signed(src_a) < $signed(src_b))};
      lx32_alu_pkg::ALU_SLTU: alu_result = {{(WIDTH-1){1'b0}}, (src_a < src_b)};
      lx32_alu_pkg::ALU_XOR:  alu_result = src_a ^ src_b;
      lx32_alu_pkg::ALU_OR:   alu_result = src_a | src_b;
      lx32_alu_pkg::ALU_AND:  alu_result = src_a & src_b;
      default:  alu_result = '0;
    endcase
  end
endmodule


