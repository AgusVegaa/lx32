`timescale 1ns / 1ps
package lx32_isa_pkg;

  // ============================================================
  // LX32 base ISA – Opcode Definitions
  // ============================================================
  // All opcodes are 7-bit wide as defined by the LX32 spec.
  // This package defines the architectural contract between
  // the decoder and the rest of the core.
  // ============================================================

  typedef enum logic [6:0] {

    // -------------------------
    // U-Type
    // -------------------------
    OP_LUI       = 7'b0110111,
    OP_AUIPC     = 7'b0010111,

    // -------------------------
    // J-Type
    // -------------------------
    OP_JAL       = 7'b1101111,
    OP_JALR      = 7'b1100111,

    // -------------------------
    // B-Type
    // -------------------------
    OP_BRANCH    = 7'b1100011,

    // -------------------------
    // Load / Store
    // -------------------------
    OP_LOAD      = 7'b0000011,
    OP_STORE     = 7'b0100011,

    // -------------------------
    // ALU Operations
    // -------------------------
    OP_OP_IMM    = 7'b0010011, // I-type ALU
    OP_OP        = 7'b0110011, // R-type ALU

    // -------------------------
    // PULSAR Custom ISA (LX.SENSOR, etc)
    // -------------------------
    OP_CUSTOM_0  = 7'b0001011,
    OP_CUSTOM_1  = 7'b0101011,

    // -------------------------
    // Reserved / Fallback
    // -------------------------
    OP_INVALID   = 7'b0000000

  } opcode_t;

endpackage
