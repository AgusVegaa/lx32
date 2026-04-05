module branch_unit_spec #(
  parameter int WIDTH = 32
) (
  input  logic [WIDTH-1:0]                src_a,
  input  logic [WIDTH-1:0]                src_b,
  input  logic                            is_branch,
  input  lx32_branch_pkg::branch_op_e     branch_op,
  output logic                            branch_taken
);
  logic compare_result;

  always_comb begin
    compare_result = 1'b0;
    case (branch_op)
      lx32_branch_pkg::BR_EQ:  compare_result = (src_a == src_b);
      lx32_branch_pkg::BR_NE:  compare_result = (src_a != src_b);
      lx32_branch_pkg::BR_LT:  compare_result = ($signed(src_a) < $signed(src_b));
      lx32_branch_pkg::BR_GE:  compare_result = ($signed(src_a) >= $signed(src_b));
      lx32_branch_pkg::BR_LTU: compare_result = ($unsigned(src_a) < $unsigned(src_b));
      lx32_branch_pkg::BR_GEU: compare_result = ($unsigned(src_a) >= $unsigned(src_b));
      default: compare_result = 1'b0;
    endcase
  end

  assign branch_taken = is_branch & compare_result;
endmodule


