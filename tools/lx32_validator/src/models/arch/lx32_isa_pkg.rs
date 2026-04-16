// ============================================================
// LX32 base ISA – Opcode Definitions
// ============================================================
// All opcodes are 7-bit wide as defined by the LX32 spec.
// This package defines the architectural contract between
// the decoder and the rest of the core.
// ============================================================

#![allow(non_camel_case_types)]
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum opcode_t {
    // -------------------------
    // U-Type
    // -------------------------
    OP_LUI = 0b0110111,
    OP_AUIPC = 0b0010111,

    // -------------------------
    // J-Type
    // -------------------------
    OP_JAL = 0b1101111,
    OP_JALR = 0b1100111,

    // -------------------------
    // B-Type
    // -------------------------
    OP_BRANCH = 0b1100011,

    // -------------------------
    // Load / Store
    // -------------------------
    OP_LOAD = 0b0000011,
    OP_STORE = 0b0100011,

    // -------------------------
    // ALU Operations
    // -------------------------
    OP_OP_IMM = 0b0010011, // I-type ALU
    OP_OP = 0b0110011,     // R-type ALU

    // -------------------------
    // PULSAR Custom ISA
    // -------------------------
    OP_CUSTOM_0 = 0b0001011,
    OP_CUSTOM_1 = 0b0101011,

    // -------------------------
    // Reserved / Fallback
    // -------------------------
    OP_INVALID = 0b0000000,
}
impl opcode_t {
    pub fn from_bits(bits: u8) -> Self {
        match bits {
            0b0110111 => Self::OP_LUI,
            0b0010111 => Self::OP_AUIPC,
            0b1101111 => Self::OP_JAL,
            0b1100111 => Self::OP_JALR,
            0b1100011 => Self::OP_BRANCH,
            0b0000011 => Self::OP_LOAD,
            0b0100011 => Self::OP_STORE,
            0b0010011 => Self::OP_OP_IMM,
            0b0110011 => Self::OP_OP,
            0b0001011 => Self::OP_CUSTOM_0,
            0b0101011 => Self::OP_CUSTOM_1,
            _ => Self::OP_INVALID,
        }
    }
}
