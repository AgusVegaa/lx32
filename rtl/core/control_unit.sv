module control_unit (

    // ------------------------------------------------------------
    // Instruction Decode Inputs
    // ------------------------------------------------------------
    input lx32_isa_pkg::opcode_t       opcode,
    input logic                  [2:0] funct3,
    input logic                        funct7_5,

    // ------------------------------------------------------------
    // Main Control Outputs
    // ------------------------------------------------------------
    output logic                              reg_write,
    output logic                              alu_src,
    output logic                              mem_write,
    output logic                        [1:0] result_src,
    output logic                              branch,
    output logic                              jump,
    output logic                              jalr,
    output logic                              src_a_pc,
    output lx32_branch_pkg::branch_op_e       branch_op,

    // ------------------------------------------------------------
    // ALU Control
    // ------------------------------------------------------------
    output lx32_alu_pkg::alu_op_e alu_control

);

  // ============================================================
  // LX32 Control Unit
  // ============================================================
  // Performs two-level decode:
  //   1) Main control (instruction class)
  //   2) ALU operation refinement (funct3/funct7)
  //
  // Design Goals:
  //   - Type-safe opcode usage
  //   - No implicit latches (Default assignments + Default cases)
  //   - Full RV32I ALU coverage
  // ============================================================

  // ------------------------------------------------------------
  // ALU Main Control Encoding
  // ------------------------------------------------------------
  typedef enum logic [1:0] {
    ALU_MAIN_ADD  = 2'b00,  // Default arithmetic (e.g. load/store)
    ALU_MAIN_SUB  = 2'b01,  // Branch compare
    ALU_MAIN_FUNC = 2'b10,  // Use funct3/funct7 refinement
    ALU_MAIN_RSVD = 2'b11   // Reserved/unused
  } alu_main_e;

  alu_main_e alu_op_main;


  // ============================================================
  // Main Instruction Decode
  // ============================================================
  always_comb begin

    // -------------------------
    // Safe Defaults
    // -------------------------
    reg_write   = 1'b0;
    alu_src     = 1'b0;
    mem_write   = 1'b0;
    result_src  = 2'b00;
    branch      = 1'b0;
    jump        = 1'b0;
    jalr        = 1'b0;
    src_a_pc    = 1'b0;
    branch_op   = lx32_branch_pkg::BR_EQ;
    alu_op_main = ALU_MAIN_ADD;

    case (opcode)

      // -------------------------
      // Load
      // -------------------------
      lx32_isa_pkg::OP_LOAD: begin
        reg_write  = 1'b1;
        alu_src    = 1'b1;
        result_src = 2'b01;
      end

      // -------------------------
      // Store
      // -------------------------
      lx32_isa_pkg::OP_STORE: begin
        alu_src   = 1'b1;
        mem_write = 1'b1;
      end

      // -------------------------
      // LUI
      // -------------------------
      lx32_isa_pkg::OP_LUI: begin
        reg_write  = 1'b1;
        alu_src    = 1'b1;
        result_src = 2'b11; // Immediate
      end

      // -------------------------
      // AUIPC
      // -------------------------
      lx32_isa_pkg::OP_AUIPC: begin
        reg_write   = 1'b1;
        alu_src     = 1'b1;
        src_a_pc    = 1'b1;
        alu_op_main = ALU_MAIN_ADD;
      end

      // -------------------------
      // JAL
      // -------------------------
      lx32_isa_pkg::OP_JAL: begin
        reg_write  = 1'b1;
        result_src = 2'b10; // PC+4
        jump       = 1'b1;
      end

      // -------------------------
      // JALR
      // -------------------------
      lx32_isa_pkg::OP_JALR: begin
        reg_write  = 1'b1;
        result_src = 2'b10; // PC+4
        jump       = 1'b1;
        jalr       = 1'b1;
        alu_src    = 1'b1;
      end

      // -------------------------
      // Register-Register ALU
      // -------------------------
      lx32_isa_pkg::OP_OP: begin
        reg_write   = 1'b1;
        alu_op_main = ALU_MAIN_FUNC;
      end

      // -------------------------
      // Immediate ALU
      // -------------------------
      lx32_isa_pkg::OP_OP_IMM: begin
        reg_write   = 1'b1;
        alu_src     = 1'b1;
        alu_op_main = ALU_MAIN_FUNC;
      end

      // -------------------------
      // Branch
      // -------------------------
      lx32_isa_pkg::OP_BRANCH: begin
        branch      = 1'b1;
        alu_op_main = ALU_MAIN_SUB;

        // Decode specific branch condition from funct3
        case (funct3)
          3'b000:  branch_op = lx32_branch_pkg::BR_EQ;
          3'b001:  branch_op = lx32_branch_pkg::BR_NE;
          3'b100:  branch_op = lx32_branch_pkg::BR_LT;
          3'b101:  branch_op = lx32_branch_pkg::BR_GE;
          3'b110:  branch_op = lx32_branch_pkg::BR_LTU;
          3'b111:  branch_op = lx32_branch_pkg::BR_GEU;
          default: branch_op = lx32_branch_pkg::BR_EQ;
        endcase
      end

      // -------------------------
      // Default case (fixes CASEINCOMPLETE)
      // -------------------------
      default: ;

    endcase
  end


  // ============================================================
  // ALU Control Decode
  // ============================================================
  always_comb begin

    // Default ALU operation
    alu_control = lx32_alu_pkg::ALU_ADD;

    case (alu_op_main)

      // -------------------------
      // Simple ADD (loads/stores)
      // -------------------------
      ALU_MAIN_ADD: alu_control = lx32_alu_pkg::ALU_ADD;

      // -------------------------
      // Branch compare (SUB)
      // -------------------------
      ALU_MAIN_SUB: alu_control = lx32_alu_pkg::ALU_SUB;

      // -------------------------
      // Funct3/Funct7 refinement
      // -------------------------
      ALU_MAIN_FUNC: begin

        case (funct3)

          3'b000: alu_control = (opcode == lx32_isa_pkg::OP_OP && funct7_5) ? lx32_alu_pkg::ALU_SUB : lx32_alu_pkg::ALU_ADD;

          3'b001: alu_control = lx32_alu_pkg::ALU_SLL;
          3'b010: alu_control = lx32_alu_pkg::ALU_SLT;
          3'b011: alu_control = lx32_alu_pkg::ALU_SLTU;
          3'b100: alu_control = lx32_alu_pkg::ALU_XOR;
          3'b101: alu_control = funct7_5 ? lx32_alu_pkg::ALU_SRA : lx32_alu_pkg::ALU_SRL;
          3'b110: alu_control = lx32_alu_pkg::ALU_OR;
          3'b111: alu_control = lx32_alu_pkg::ALU_AND;

          // Default case for funct3 (fixes CASEINCOMPLETE)
          default: alu_control = lx32_alu_pkg::ALU_ADD;

        endcase
      end

      // -------------------------
      // Default case for alu_op_main (fixes CASEINCOMPLETE)
      // -------------------------
      default: alu_control = lx32_alu_pkg::ALU_ADD;

    endcase
  end

endmodule

