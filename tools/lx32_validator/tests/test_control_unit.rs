// tests/test_control_unit.rs
#[path = "common/mod.rs"]
mod common;
use common::*;
use rand::RngExt;

/// Control Unit Test Parameters - Allows parameterization of test behavior
pub struct ControlUnitTestParams {
    pub iterations: u32,
    pub reg_range: (u32, u32),
    pub imm_range: (i32, i32),
    pub enable_logging: bool,
}

impl Default for ControlUnitTestParams {
    fn default() -> Self {
        Self {
            iterations: 100,
            reg_range: (0, 32),
            imm_range: (-2048, 2047),
            enable_logging: true,
        }
    }
}

/// Captures the state after instruction execution for comparison
#[derive(Debug, Clone)]
struct ExecutionState {
    pc: u32,
    rd: u8,
    rd_value: u32,
    rs1: u8,
    rs1_value: u32,
    rs2: u8,
    rs2_value: u32,
    instr: u32,
    iteration: u32,
}

/// Helper to extract fields from instruction
fn extract_fields(instr: u32) -> (u8, u8, u8, u8) {
    let rd = ((instr >> 7) & 0x1F) as u8;
    let rs1 = ((instr >> 15) & 0x1F) as u8;
    let rs2 = ((instr >> 20) & 0x1F) as u8;
    let funct3 = ((instr >> 12) & 0x7) as u8;
    (rd, rs1, rs2, funct3)
}

/// Capture execution state from RTL and Golden model
fn capture_state(
    tb: &TestBench,
    instr: u32,
    iteration: u32,
    rd: u8,
    rs1: u8,
    rs2: u8,
) -> (ExecutionState, ExecutionState) {
    let rtl_pc = unsafe { get_pc(tb.rtl) };
    let rtl_rd_val = unsafe { get_reg(tb.rtl, rd) };
    let rtl_rs1_val = unsafe { get_reg(tb.rtl, rs1) };
    let rtl_rs2_val = unsafe { get_reg(tb.rtl, rs2) };

    let gold_pc = tb.gold.pc;
    let gold_rd_val = tb.gold.reg_file.read_rs1(rd);
    let gold_rs1_val = tb.gold.reg_file.read_rs1(rs1);
    let gold_rs2_val = tb.gold.reg_file.read_rs1(rs2);

    let rtl_state = ExecutionState {
        pc: rtl_pc,
        rd,
        rd_value: rtl_rd_val,
        rs1,
        rs1_value: rtl_rs1_val,
        rs2,
        rs2_value: rtl_rs2_val,
        instr,
        iteration,
    };

    let gold_state = ExecutionState {
        pc: gold_pc,
        rd,
        rd_value: gold_rd_val,
        rs1,
        rs1_value: gold_rs1_val,
        rs2,
        rs2_value: gold_rs2_val,
        instr,
        iteration,
    };

    (rtl_state, gold_state)
}

/// Validate that RTL and Golden model states match
fn validate_states(rtl_state: &ExecutionState, gold_state: &ExecutionState) -> bool {
    rtl_state.pc == gold_state.pc
        && rtl_state.rd_value == gold_state.rd_value
        && rtl_state.rs1_value == gold_state.rs1_value
        && rtl_state.rs2_value == gold_state.rs2_value
}

/// Log execution for debugging - Shows instruction decode and resulting state
fn log_execution(rtl_state: &ExecutionState, gold_state: &ExecutionState, matches: bool) {
    let status = if matches { "✓ MATCH" } else { "✗ MISMATCH" };

    println!(
        "[{:>5}] Instr: 0x{:08x} | PC: [R:0x{:04x} G:0x{:04x}] | x{:>2}(RD): [R:0x{:08x} G:0x{:08x}] | {}",
        rtl_state.iteration,
        rtl_state.instr,
        rtl_state.pc,
        gold_state.pc,
        rtl_state.rd,
        rtl_state.rd_value,
        gold_state.rd_value,
        status
    );

    // Additional detail for mismatches
    if !matches {
        if rtl_state.rs1_value != gold_state.rs1_value {
            println!(
                "       RS1 Mismatch: R:0x{:08x} vs G:0x{:08x}",
                rtl_state.rs1_value, gold_state.rs1_value
            );
        }
        if rtl_state.rs2_value != gold_state.rs2_value {
            println!(
                "       RS2 Mismatch: R:0x{:08x} vs G:0x{:08x}",
                rtl_state.rs2_value, gold_state.rs2_value
            );
        }
    }
}

/// Execute a parametrizable Control Unit fuzzer
/// Tests various instruction types and validates instruction decoding
pub fn run_control_unit_fuzzer(params: ControlUnitTestParams) {
    println!("\n{:=^100}", " STARTING CONTROL UNIT FUZZER ");
    println!("Iterations: {}", params.iterations);
    println!("Registers: {:?}", params.reg_range);
    println!("Immediates: {:?}", params.imm_range);

    let mut tb = TestBench::new();
    let mut rng = rand::rng();

    for i in 0..params.iterations {
        // Randomly select instruction type (R, I, S, B, JAL, JALR, U)
        let instr_type = rng.random_range(0..7);

        let instr = match instr_type {
            0 => {
                // R-Type: ADD, SUB, SLL, SLT, XOR, SRL, SRA, OR, AND
                let rd = rng.random_range(1..32);
                let rs1 = rng.random_range(0..32);
                let rs2 = rng.random_range(0..32);
                let funct7 = if rng.random() { 0x20 } else { 0x00 };
                let funct3 = rng.random_range(0..8);
                let opcode = 0x33; // OP_OP

                (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
            }
            1 => {
                // I-Type: ADDI, SLTI, XORI, ORI, ANDI, SLLI, SRLI, SRAI
                let rd = rng.random_range(1..32);
                let rs1 = rng.random_range(0..32);
                let imm = rng.random_range(0..4096) as u32;
                let funct3 = rng.random_range(0..8);
                let opcode = 0x13; // OP_OP_IMM

                (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
            }
            2 => {
                // S-Type: SW
                let rs1 = rng.random_range(0..32);
                let rs2 = rng.random_range(0..32);
                let offset = rng.random_range(0..4096) as i32;
                let imm11_5 = ((offset >> 5) & 0x7F) as u32;
                let imm4_0 = (offset & 0x1F) as u32;
                let opcode = 0x23; // OP_STORE

                (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (imm4_0 << 7) | opcode
            }
            3 => {
                // B-Type: BEQ, BNE, BLT, BGE, BLTU, BGEU
                let rs1 = rng.random_range(0..32);
                let rs2 = rng.random_range(0..32);
                let offset: i32 = rng.random_range(-1024..1024) * 2;
                let imm12 = ((offset >> 12) & 0x1) as u32;
                let imm11 = ((offset >> 11) & 0x1) as u32;
                let imm10_5 = ((offset >> 5) & 0x3F) as u32;
                let imm4_1 = ((offset >> 1) & 0xF) as u32;
                let branch_funct3 = [0u32, 1, 4, 5, 6, 7];
                let funct3 = branch_funct3[rng.random_range(0..branch_funct3.len())];
                let opcode = 0x63; // OP_BRANCH

                (imm12 << 31)
                    | (imm10_5 << 25)
                    | (rs2 << 20)
                    | (rs1 << 15)
                    | (funct3 << 12)
                    | (imm4_1 << 8)
                    | (imm11 << 7)
                    | opcode
            }
            4 => {
                // J-Type: JAL
                let rd = rng.random_range(1..32);
                let offset: i32 = rng.random_range(-524288..524288) * 2;
                let imm20 = ((offset >> 20) & 0x1) as u32;
                let imm10_1 = ((offset >> 1) & 0x3FF) as u32;
                let imm11 = ((offset >> 11) & 0x1) as u32;
                let imm19_12 = ((offset >> 12) & 0xFF) as u32;
                (imm20 << 31)
                    | (imm19_12 << 12)
                    | (imm11 << 20)
                    | (imm10_1 << 21)
                    | (rd << 7)
                    | 0x6F
            }
            5 => {
                // I-Type: JALR
                let rd = rng.random_range(1..32);
                let rs1 = rng.random_range(0..32);
                let imm = rng.random_range(-2048..2048) as i32;
                let imm12 = (imm as u32) & 0xFFF;
                (imm12 << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x67
            }
            _ => {
                // U-Type: LUI/AUIPC
                let rd = rng.random_range(1..32);
                let imm20 = rng.random_range(0..(1 << 20));
                let opcode = if rng.random() { 0x37 } else { 0x17 };
                (imm20 << 12) | (rd << 7) | opcode
            }
        };

        let (rd, rs1, rs2, _funct3) = extract_fields(instr);

        // Execute instruction on both RTL and Golden Model
        unsafe { tick_core(tb.rtl, 0, instr, 0) };
        tb.gold.step(instr, 0, false);

        // Capture state AFTER execution
        let (post_rtl_state, post_gold_state) = capture_state(&tb, instr, i, rd, rs1, rs2);

        // Validate that states match
        let states_match = validate_states(&post_rtl_state, &post_gold_state);

        if params.enable_logging {
            log_execution(&post_rtl_state, &post_gold_state, states_match);
        }

        // Panic if mismatch detected
        if !states_match {
            println!("\n{:=^100}", " CONTROL UNIT MISMATCH DETECTED ");
            println!("Iteration: {}", i);
            println!("Instruction: 0x{:08x}", instr);
            println!("\nRTL State:");
            println!("  PC: 0x{:04x}", post_rtl_state.pc);
            println!("  x{:>2} (RD): 0x{:08x}", rd, post_rtl_state.rd_value);
            println!("  x{:>2} (RS1): 0x{:08x}", rs1, post_rtl_state.rs1_value);
            println!("  x{:>2} (RS2): 0x{:08x}", rs2, post_rtl_state.rs2_value);
            println!("\nGolden State:");
            println!("  PC: 0x{:04x}", post_gold_state.pc);
            println!("  x{:>2} (RD): 0x{:08x}", rd, post_gold_state.rd_value);
            println!("  x{:>2} (RS1): 0x{:08x}", rs1, post_gold_state.rs1_value);
            println!("  x{:>2} (RS2): 0x{:08x}", rs2, post_gold_state.rs2_value);
            panic!("🔥 CONTROL UNIT TEST FAILED AT ITERATION {}", i);
        }
    }
    println!("{:=^100}\n", " CONTROL UNIT FUZZER PASSED ");
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run_directed_jump_case(instr: u32, rd: u8) {
        let mut tb = TestBench::new();
        unsafe { tick_core(tb.rtl, 0, instr, 0) };
        tb.gold.step(instr, 0, false);

        let rtl_pc = unsafe { get_pc(tb.rtl) };
        let gold_pc = tb.gold.pc;
        let rtl_rd = unsafe { get_reg(tb.rtl, rd) };
        let gold_rd = tb.gold.reg_file.read_rs1(rd);

        assert_eq!(rtl_pc, gold_pc, "PC mismatch for directed jump case");
        assert_eq!(rtl_rd, gold_rd, "RD mismatch for directed jump case");
    }

    /// Default configuration test - 100 iterations, standard ranges
    #[test]
    fn test_control_unit_default() {
        run_control_unit_fuzzer(ControlUnitTestParams::default());
    }

    /// Extended test with more iterations
    #[test]
    fn test_control_unit_extended() {
        run_control_unit_fuzzer(ControlUnitTestParams {
            iterations: 500,
            ..Default::default()
        });
    }

    /// Test with extended register range
    #[test]
    fn test_control_unit_full_register_range() {
        run_control_unit_fuzzer(ControlUnitTestParams {
            iterations: 200,
            reg_range: (0, 32),
            ..Default::default()
        });
    }

    /// Stress test - many iterations, all ranges enabled
    #[test]
    fn test_control_unit_stress() {
        run_control_unit_fuzzer(ControlUnitTestParams {
            iterations: 1000,
            ..Default::default()
        });
    }

    #[test]
    fn test_control_unit_directed_jal() {
        // JAL x5, +8
        let rd = 5u8;
        let offset = 8i32;
        let imm20 = ((offset >> 20) & 0x1) as u32;
        let imm10_1 = ((offset >> 1) & 0x3FF) as u32;
        let imm11 = ((offset >> 11) & 0x1) as u32;
        let imm19_12 = ((offset >> 12) & 0xFF) as u32;
        let instr = (imm20 << 31)
            | (imm19_12 << 12)
            | (imm11 << 20)
            | (imm10_1 << 21)
            | ((rd as u32) << 7)
            | 0x6F;

        run_directed_jump_case(instr, rd);
    }

    #[test]
    fn test_control_unit_directed_jalr() {
        // JALR x6, 4(x0)
        let rd = 6u8;
        let rs1 = 0u32;
        let imm12 = 4u32;
        let instr = (imm12 << 20) | (rs1 << 15) | (0 << 12) | ((rd as u32) << 7) | 0x67;

        run_directed_jump_case(instr, rd);
    }
}

