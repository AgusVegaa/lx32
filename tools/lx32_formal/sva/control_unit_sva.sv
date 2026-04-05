module control_unit_sva;
  (* anyseq *) logic [6:0] opcode_bits;
  (* anyseq *) logic [2:0] funct3;
  (* anyseq *) logic       funct7_5;

  logic reg_write;
  logic alu_src;
  logic mem_write;
  logic [1:0] result_src;
  logic branch;
  logic jump;
  logic jalr;
  logic src_a_pc;
  lx32_branch_pkg::branch_op_e branch_op;
  lx32_alu_pkg::alu_op_e alu_control;

  control_unit dut (
    .opcode(opcode_bits),
    .funct3(funct3),
    .funct7_5(funct7_5),
    .reg_write(reg_write),
    .alu_src(alu_src),
    .mem_write(mem_write),
    .result_src(result_src),
    .branch(branch),
    .jump(jump),
    .jalr(jalr),
    .src_a_pc(src_a_pc),
    .branch_op(branch_op),
    .alu_control(alu_control)
  );

  always_comb begin
    // Safety coherence: decode must not write register file and data memory in same cycle.
    assert (!(reg_write && mem_write));

    // Jumps in LX32 are writeback instructions (link register path).
    assert (!jump || reg_write);

    // jalr is a strict subset of jump.
    assert (!jalr || jump);

    // Only AUIPC selects PC as ALU source A.
    if (src_a_pc) assert (opcode_bits == lx32_isa_pkg::OP_AUIPC);

    // Branch and jump are disjoint decode classes.
    assert (!(branch && jump));
  end
endmodule



