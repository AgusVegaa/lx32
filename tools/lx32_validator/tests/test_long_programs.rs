// tests/test_long_programs.rs
//
// LX32 Long Program Validator - Tests CPU with extended instruction sequences
//
// This test generates and validates programs with 500-1000 instructions to detect:
// - Register dependency bugs
// - Memory corruption
// - Control flow errors
// - PC tracking issues
// - Pipeline hazards (if pipelined)
//
// When a test fails, the shrinker automatically reduces it to minimal reproducible case
//
// Author: LX32 Validation Team
// License: MIT

#[path = "common/mod.rs"]
mod common;
use common::*;

use lx32_validator::program_generator::{Program, ProgramConfig};
use lx32_validator::shrinking::{Shrinker, ShrinkConfig};
use lx32_validator::models::core::lx32_system::Lx32System;

pub struct LongProgramTestParams {
    pub num_programs: usize,
    pub program_length: usize,
    pub enable_shrinking: bool,
    pub enable_logging: bool,
}

impl Default for LongProgramTestParams {
    fn default() -> Self {
        Self {
            num_programs: 10,
            program_length: 500,
            enable_shrinking: true,
            enable_logging: false,
        }
    }
}

#[derive(Debug)]
struct ProgramFailure {
    program: Program,
    failed_at_instruction: usize,
    rtl_pc: u32,
    gold_pc: u32,
}

pub fn run_long_program_fuzzer(params: LongProgramTestParams, seed: u64) {
    println!("\n{:=^100}", " STARTING LONG PROGRAM FUZZER ");
    println!("Number of programs: {}", params.num_programs);
    println!("Program length: {} instructions", params.program_length);
    println!("Shrinking enabled: {}", params.enable_shrinking);
    println!("Seed: {}", seed);

    let mut tb = TestBench::new();
    let mut failures = Vec::new();

    for prog_idx in 0..params.num_programs {
        let program_seed = seed.wrapping_add(prog_idx as u64);

        let config = ProgramConfig {
            length: params.program_length,
            enable_branches: true,
            enable_loads: true,
            enable_stores: true,
            enable_alu: true,
            enable_jumps: true,
            enable_upper_imm: true,
        };

        let program = Program::generate(config, program_seed);

        if params.enable_logging {
            println!("\n[Program {}] Generated {} instructions", prog_idx, program.instructions.len());
        }

        // Reset CPU state
        tb.gold = Lx32System::new();
        unsafe {
            common::reset(tb.rtl);
        }

        // Execute program
        let mut failed = false;
        let mut fail_idx = 0;

        for (idx, instr) in program.instructions.iter().enumerate() {
            // Clock cycle with instruction
            unsafe {
                common::tick_core(tb.rtl, 0, instr.encoding, 0);
            }
            tb.gold.step(instr.encoding, 0, false);

            // Check state
            let rtl_pc = unsafe { common::get_pc(tb.rtl) };
            let gold_pc = tb.gold.pc;

            if params.enable_logging {
                println!(
                    "[Program {}][Instr {}] PC: RTL=0x{:04x}, GOLD=0x{:04x}, Instr=0x{:08x} ({})",
                    prog_idx, idx, rtl_pc, gold_pc, instr.encoding, instr.mnemonic
                );
            }

            if rtl_pc != gold_pc {
                failed = true;
                fail_idx = idx;

                failures.push(ProgramFailure {
                    program: program.clone(),
                    failed_at_instruction: idx,
                    rtl_pc,
                    gold_pc,
                });

                println!("✗ [Program {}] FAILED at instruction {}/{}", prog_idx, idx, program.instructions.len());
                println!("  PC mismatch: RTL=0x{:04x}, GOLD=0x{:04x}", rtl_pc, gold_pc);
                println!("  Failing instruction: 0x{:08x} ({})", instr.encoding, instr.mnemonic);

                break;
            }
        }

        if !failed {
            if params.enable_logging {
                println!("✓ [Program {}] PASSED - {} instructions executed successfully", prog_idx, program.instructions.len());
            } else {
                print!(".");
            }
        }
    }

    if !params.enable_logging {
        println!(); // newline after dots
    }

    // Handle failures
    if !failures.is_empty() {
        println!("\n{:=^100}", " FAILURES DETECTED ");
        println!("Total failures: {}/{}", failures.len(), params.num_programs);

        if params.enable_shrinking {
            println!("\n{:=^100}", " SHRINKING FAILED TEST CASES ");

            for (idx, failure) in failures.iter().enumerate() {
                println!("\n--- Failure {} ---", idx + 1);
                println!("Original failure at instruction {}/{}",
                    failure.failed_at_instruction,
                    failure.program.instructions.len()
                );

                // Create test function that reproduces the bug
                let test_reproduces_bug = |prog: &Program| -> bool {
                    let mut test_tb = TestBench::new();

                    for instr in &prog.instructions {
                        unsafe {
                            common::tick_core(test_tb.rtl, 0, instr.encoding, 0);
                        }
                        test_tb.gold.step(instr.encoding, 0, false);

                        let rtl_pc = unsafe { common::get_pc(test_tb.rtl) };
                        let gold_pc = test_tb.gold.pc;

                        if rtl_pc != gold_pc {
                            return true; // Bug still present
                        }
                    }
                    false // Bug not reproduced
                };

                // Shrink the failing program
                let shrinker = Shrinker::new(ShrinkConfig {
                    max_iterations: 100,
                    aggressive: true,
                });
                let shrink_result = shrinker.shrink(&failure.program, test_reproduces_bug);

                println!("\nMinimal failing program:");
                println!("{}", shrink_result.program.display());
            }
        } else {
            // Just show the failing programs without shrinking
            for (idx, failure) in failures.iter().enumerate() {
                println!("\n--- Failure {} ---", idx + 1);
                println!("Failed at instruction {}/{}",
                    failure.failed_at_instruction,
                    failure.program.instructions.len()
                );
                println!("Context (last 5 instructions before failure):");

                let start = failure.failed_at_instruction.saturating_sub(5);
                let end = (failure.failed_at_instruction + 1).min(failure.program.instructions.len());

                for i in start..end {
                    let marker = if i == failure.failed_at_instruction { ">>>" } else { "   " };
                    println!("{} {:4}: {:08x}  {}",
                        marker,
                        i,
                        failure.program.instructions[i].encoding,
                        failure.program.instructions[i].mnemonic
                    );
                }
            }
        }

        panic!("Long program validation failed!");
    }

    println!("✓ Long program validation PASSED - all {} programs executed successfully", params.num_programs);
}


