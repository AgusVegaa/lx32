`timescale 1ns / 1ps

package lx32_decode_pkg;

  // XLEN is fixed at 32 for LX32; avoid `import` inside package body
  // because Yosys formal flow does not support that construct.
  localparam int XLEN = 32;

  // ============================================================
  // LX32 base Immediate Decode Package
  // ============================================================
  // This package centralizes all immediate extraction logic
  // for the base ISA formats.
  // ============================================================

  localparam int INSTR_WIDTH = 32;
  localparam int SIGN_BIT    = INSTR_WIDTH - 1;

  localparam int I_IMM_BITS = 12;
  localparam int S_IMM_BITS = 12;
  localparam int B_IMM_BITS = 13; 
  localparam int U_IMM_BITS = 20;
  localparam int J_IMM_BITS = 21; 

  localparam int U_LOW_BITS = INSTR_WIDTH - U_IMM_BITS;

  // -------------------------
  // I-Type Immediate
  // -------------------------
  function automatic logic [XLEN-1:0] get_i_imm(logic [31:0] instr);
    return {
      {(XLEN - I_IMM_BITS){instr[SIGN_BIT]}},
      instr[31:20]
    };
  endfunction

  // -------------------------
  // S-Type Immediate
  // -------------------------
  function automatic logic [XLEN-1:0] get_s_imm(logic [31:0] instr);
    return {
      {(XLEN - S_IMM_BITS){instr[SIGN_BIT]}},
      instr[31:25],
      instr[11:7]
    };
  endfunction

  // -------------------------
  // B-Type Immediate
  // -------------------------
  function automatic logic [XLEN-1:0] get_b_imm(logic [31:0] instr);
    return {
      {(XLEN - B_IMM_BITS){instr[SIGN_BIT]}},
      instr[31],
      instr[7],
      instr[30:25],
      instr[11:8],
      1'b0
    };
  endfunction

  // -------------------------
  // U-Type Immediate
  // -------------------------
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic [XLEN-1:0] get_u_imm(logic [31:0] instr);
    return {
      instr[31:12],
      {U_LOW_BITS{1'b0}}
    };
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  // -------------------------
  // J-Type Immediate
  // -------------------------
  function automatic logic [XLEN-1:0] get_j_imm(logic [31:0] instr);
    return {
      {(XLEN - J_IMM_BITS){instr[SIGN_BIT]}},
      instr[31],
      instr[19:12],
      instr[20],
      instr[30:21],
      1'b0
    };
  endfunction

endpackage
