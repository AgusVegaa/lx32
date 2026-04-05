// src/program_generator.rs
//
// LX32 Program Generator - Generates long instruction sequences for comprehensive testing
//
// This module generates randomized instruction sequences (500-1000 instructions) to test:
// - Register dependencies
// - Memory operations
// - Control flow
// - PC correctness
//
// Author: LX32 Validation Team
// License: MIT

use rand::RngExt;
use rand::SeedableRng;
use rand::rngs::StdRng;

/// Represents a single instruction in a program sequence
#[derive(Debug, Clone)]
pub struct Instruction {
    pub encoding: u32,
    pub mnemonic: String,
    pub rd: Option<u8>,
    pub rs1: Option<u8>,
    pub rs2: Option<u8>,
    pub imm: Option<i32>,
}

/// Program sequence configuration
#[derive(Debug, Clone)]
pub struct ProgramConfig {
    pub length: usize,
    pub enable_branches: bool,
    pub enable_loads: bool,
    pub enable_stores: bool,
    pub enable_alu: bool,
    pub enable_jumps: bool,
    pub enable_upper_imm: bool,
}

impl Default for ProgramConfig {
    fn default() -> Self {
        Self {
            length: 500,
            enable_branches: true,
            enable_loads: true,
            enable_stores: true,
            enable_alu: true,
            enable_jumps: true,
            enable_upper_imm: true,
        }
    }
}

/// Generated program with full trace
#[derive(Debug, Clone)]
pub struct Program {
    pub instructions: Vec<Instruction>,
    pub config: ProgramConfig,
}

impl Program {
    /// Generate a new random program
    pub fn generate(config: ProgramConfig, seed: u64) -> Self {
        let mut rng = StdRng::seed_from_u64(seed);
        let mut instructions = Vec::with_capacity(config.length);

        for _ in 0..config.length {
            let instr = Self::generate_instruction(&config, &mut rng);
            instructions.push(instr);
        }

        Program {
            instructions,
            config,
        }
    }

    /// Generate a single random instruction based on config
    fn generate_instruction(config: &ProgramConfig, rng: &mut impl RngExt) -> Instruction {
        let mut categories = Vec::new();

        if config.enable_alu {
            categories.push("ALU");
        }
        if config.enable_loads {
            categories.push("LOAD");
        }
        if config.enable_stores {
            categories.push("STORE");
        }
        if config.enable_branches {
            categories.push("BRANCH");
        }
        if config.enable_jumps {
            categories.push("JUMP");
        }
        if config.enable_upper_imm {
            categories.push("UIMM");
        }

        if categories.is_empty() {
            categories.push("ALU"); // fallback
        }

        let category = categories[rng.random_range(0..categories.len())];

        match category {
            "ALU" => Self::generate_alu_instruction(rng),
            "LOAD" => Self::generate_load_instruction(rng),
            "STORE" => Self::generate_store_instruction(rng),
            "BRANCH" => Self::generate_branch_instruction(rng),
            "JUMP" => Self::generate_jump_instruction(rng),
            "UIMM" => Self::generate_upper_imm_instruction(rng),
            _ => Self::generate_alu_instruction(rng),
        }
    }

    /// Generate JAL/JALR instructions
    fn generate_jump_instruction(rng: &mut impl RngExt) -> Instruction {
        let jal = rng.random();
        let rd = rng.random_range(1..32) as u8;
        if jal {
            let offset = (rng.random_range(-524288..524287) as i32) & !1;
            let imm20 = ((offset >> 20) & 0x1) as u32;
            let imm10_1 = ((offset >> 1) & 0x3FF) as u32;
            let imm11 = ((offset >> 11) & 0x1) as u32;
            let imm19_12 = ((offset >> 12) & 0xFF) as u32;
            let encoding = (imm20 << 31)
                | (imm19_12 << 12)
                | (imm11 << 20)
                | (imm10_1 << 21)
                | ((rd as u32) << 7)
                | 0x6F;
            Instruction {
                encoding,
                mnemonic: format!("JAL x{}, {}", rd, offset),
                rd: Some(rd),
                rs1: None,
                rs2: None,
                imm: Some(offset),
            }
        } else {
            let rs1 = rng.random_range(0..32) as u8;
            let imm = rng.random_range(-2048..2047) as i32;
            let encoding = ((imm as u32) << 20)
                | ((rs1 as u32) << 15)
                | (0x0 << 12)
                | ((rd as u32) << 7)
                | 0x67;
            Instruction {
                encoding,
                mnemonic: format!("JALR x{}, {}(x{})", rd, imm, rs1),
                rd: Some(rd),
                rs1: Some(rs1),
                rs2: None,
                imm: Some(imm),
            }
        }
    }

    /// Generate LUI/AUIPC instructions
    fn generate_upper_imm_instruction(rng: &mut impl RngExt) -> Instruction {
        let rd = rng.random_range(1..32) as u8;
        let imm20 = rng.random_range(0..(1 << 20)) as u32;
        let lui = rng.random();
        let opcode = if lui { 0x37 } else { 0x17 };
        let encoding = (imm20 << 12) | ((rd as u32) << 7) | opcode;
        Instruction {
            encoding,
            mnemonic: if lui {
                format!("LUI x{}, 0x{:x}", rd, imm20)
            } else {
                format!("AUIPC x{}, 0x{:x}", rd, imm20)
            },
            rd: Some(rd),
            rs1: None,
            rs2: None,
            imm: Some((imm20 << 12) as i32),
        }
    }

    /// Generate ALU instruction (ADD, XOR, OR, AND, SLT, SLTU)
    fn generate_alu_instruction(rng: &mut impl RngExt) -> Instruction {
        let rd = rng.random_range(1..32) as u8;
        let rs1 = rng.random_range(0..32) as u8;
        let imm = rng.random_range(0..4096) as i32;
        let funct3_set = [0x0, 0x2, 0x4, 0x6, 0x7]; // ADDI, SLTI, XORI, ORI, ANDI
        let funct3 = funct3_set[rng.random_range(0..funct3_set.len())];

        let encoding = ((imm as u32) << 20) | ((rs1 as u32) << 15) | (funct3 << 12) | ((rd as u32) << 7) | 0x13;

        let mnemonic = match funct3 {
            0x0 => format!("ADDI x{}, x{}, {}", rd, rs1, imm),
            0x2 => format!("SLTI x{}, x{}, {}", rd, rs1, imm),
            0x4 => format!("XORI x{}, x{}, {}", rd, rs1, imm),
            0x6 => format!("ORI x{}, x{}, {}", rd, rs1, imm),
            0x7 => format!("ANDI x{}, x{}, {}", rd, rs1, imm),
            _ => format!("ALU x{}, x{}, {}", rd, rs1, imm),
        };

        Instruction {
            encoding,
            mnemonic,
            rd: Some(rd),
            rs1: Some(rs1),
            rs2: None,
            imm: Some(imm),
        }
    }

    /// Generate LOAD instruction
    fn generate_load_instruction(rng: &mut impl RngExt) -> Instruction {
        let rd = rng.random_range(1..32) as u8;
        let rs1 = rng.random_range(0..32) as u8;
        let imm = rng.random_range(-2048..2047) as i32;
        let funct3 = 0x2; // LW

        let encoding = ((imm as u32) << 20) | ((rs1 as u32) << 15) | (funct3 << 12) | ((rd as u32) << 7) | 0x03;

        Instruction {
            encoding,
            mnemonic: format!("LW x{}, {}(x{})", rd, imm, rs1),
            rd: Some(rd),
            rs1: Some(rs1),
            rs2: None,
            imm: Some(imm),
        }
    }

    /// Generate STORE instruction
    fn generate_store_instruction(rng: &mut impl RngExt) -> Instruction {
        let rs1 = rng.random_range(0..32) as u8;
        let rs2 = rng.random_range(0..32) as u8;
        let imm = rng.random_range(-2048..2047) as i32;
        let funct3 = 0x2; // SW

        let imm_11_5 = ((imm >> 5) & 0x7F) as u32;
        let imm_4_0 = (imm & 0x1F) as u32;
        let encoding = (imm_11_5 << 25) | ((rs2 as u32) << 20) | ((rs1 as u32) << 15) | (funct3 << 12) | (imm_4_0 << 7) | 0x23;

        Instruction {
            encoding,
            mnemonic: format!("SW x{}, {}(x{})", rs2, imm, rs1),
            rd: None,
            rs1: Some(rs1),
            rs2: Some(rs2),
            imm: Some(imm),
        }
    }

    /// Generate BRANCH instruction
    fn generate_branch_instruction(rng: &mut impl RngExt) -> Instruction {
        let rs1 = rng.random_range(0..32) as u8;
        let rs2 = rng.random_range(0..32) as u8;
        let offset = (rng.random_range(-128..128) as i32) * 4;
        let funct3_set = [0x0, 0x1, 0x4, 0x5, 0x6, 0x7]; // BEQ, BNE, BLT, BGE, BLTU, BGEU
        let funct3 = funct3_set[rng.random_range(0..funct3_set.len())];

        let imm_12 = ((offset >> 12) & 0x1) as u32;
        let imm_10_5 = ((offset >> 5) & 0x3F) as u32;
        let imm_4_1 = ((offset >> 1) & 0xF) as u32;
        let imm_11 = ((offset >> 11) & 0x1) as u32;

        let encoding = (imm_12 << 31) | (imm_10_5 << 25) | ((rs2 as u32) << 20) | ((rs1 as u32) << 15) | (funct3 << 12) | (imm_4_1 << 8) | (imm_11 << 7) | 0x63;

        let mnemonic = match funct3 {
            0x0 => format!("BEQ x{}, x{}, {}", rs1, rs2, offset),
            0x1 => format!("BNE x{}, x{}, {}", rs1, rs2, offset),
            0x4 => format!("BLT x{}, x{}, {}", rs1, rs2, offset),
            0x5 => format!("BGE x{}, x{}, {}", rs1, rs2, offset),
            0x6 => format!("BLTU x{}, x{}, {}", rs1, rs2, offset),
            0x7 => format!("BGEU x{}, x{}, {}", rs1, rs2, offset),
            _ => format!("BRANCH x{}, x{}, {}", rs1, rs2, offset),
        };

        Instruction {
            encoding,
            mnemonic,
            rd: None,
            rs1: Some(rs1),
            rs2: Some(rs2),
            imm: Some(offset),
        }
    }

    /// Try to shrink the program to minimal failing case
    pub fn shrink<F>(&self, test_fn: F) -> Option<Program>
    where
        F: Fn(&Program) -> bool,
    {
        let mut current = self.clone();
        let mut improved = true;

        while improved {
            improved = false;

            // Try to remove instructions
            for i in (0..current.instructions.len()).rev() {
                let mut candidate = current.clone();
                candidate.instructions.remove(i);

                if !candidate.instructions.is_empty() && test_fn(&candidate) {
                    current = candidate;
                    improved = true;
                    break;
                }
            }
        }

        if current.instructions.len() < self.instructions.len() {
            Some(current)
        } else {
            None
        }
    }

    /// Display program in readable format
    pub fn display(&self) -> String {
        let mut output = format!("Program ({} instructions):\n", self.instructions.len());
        for (idx, instr) in self.instructions.iter().enumerate() {
            output.push_str(&format!("{:4}: {:08x}  {}\n", idx, instr.encoding, instr.mnemonic));
        }
        output
    }
}


