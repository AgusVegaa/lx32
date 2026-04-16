// ============================================================
// LX32 Processor System (Single Cycle) — Golden Model
// ============================================================
//
// This module is the top-level integration of the LX32 golden model.
// It wires together the Control Unit, ALU, Branch Unit, LSU, Register File,
// and Immediate Generator into a single-cycle execution datapath, mirroring
// the structure of `rtl/core/lx32_system.sv`.
//
// Design contract
// ───────────────
// `step(instr, mem_rdata, rst)` advances the model by one clock cycle:
//   - `instr`     — the 32-bit instruction word fetched at the current PC.
//   - `mem_rdata` — data returned from the memory subsystem for load
//                   instructions (provided externally, mirroring RTL).
//   - `rst`       — synchronous active-high reset.
//
// Returns `(alu_result, rs2_data, mem_write_enable)` — the three signals
// that the differential fuzzer compares against the RTL simulation output.
//
// LX.WAIT stall model
// ───────────────────
// LX.WAIT is encoded as a standard I-type with NO write-back.
//
// ENCODING NOTE: The LX32 compiler places the cycle-count register at
// bits[11:7] (the rd field), not bits[19:15] (rs1 as per the ISA spec).
// Both this model and the RTL read from bits[11:7] to match the compiler.
//
// State machine (wait_counter):
//   0          → idle; normal decode path.
//   1..N (set) → first cycle of the stall; PC is frozen.
//   1..N (cnt) → pipeline holds; counter counts down every cycle.
//   reaches 0  → final stall cycle: PC advances past LX.WAIT.
//
// Observed latency for `lx.wait N` (N > 0):
//   1 committed cycle (wait_start fires) + N+1 stall cycles = N+2 clock cycles.
//   The extra stall arises because the IPC tracker reads PC before the tick that
//   advances it, so the expiry cycle where wait_counter → 0 appears as a stall.
// For N = 0, LX.WAIT is a NOP (wait_counter stays 0; PC advances in 1 cycle).
// ============================================================

use crate::models::arch::lx32_isa_pkg::opcode_t;
use crate::models::core::alu::alu_golden_model;
use crate::models::core::branch_unit::branch_unit_golden;
use crate::models::core::control_unit::control_unit_golden;
use crate::models::core::imm_gen::imm_gen_golden;
use crate::models::core::register_file::RegisterFile;

pub struct Lx32System {
    pub pc: u32,
    pub reg_file: RegisterFile,
    pub memory: Vec<u8>,

    /// Remaining stall cycles for an active LX.WAIT.
    /// Zero when idle.  Decremented each cycle; PC advances on the final
    /// decrement (when the value transitions 1 → 0).
    wait_counter: u32,

    /// Total clock cycles elapsed (including stall cycles).
    pub cycles_total: u64,

    /// Instructions retired (stall cycles excluded).
    /// IPC = instructions_committed / cycles_total.
    pub instructions_committed: u64,
}

impl Lx32System {
    /// Create a new LX32 golden model with 4 KiB of zeroed memory.
    pub fn new() -> Self {
        Self {
            pc: 0,
            reg_file: RegisterFile::new(),
            memory: vec![0; 4096],
            wait_counter: 0,
            cycles_total: 0,
            instructions_committed: 0,
        }
    }

    /// IPC computed from the lifetime counters.
    pub fn ipc(&self) -> f64 {
        if self.cycles_total == 0 {
            0.0
        } else {
            self.instructions_committed as f64 / self.cycles_total as f64
        }
    }

    /// Read a 32-bit little-endian word from the model's memory.
    ///
    /// Returns 0 for any out-of-bounds address (mirrors the RTL behaviour
    /// of returning 0 on unmapped reads in simulation).
    pub fn read_mem(&self, addr: u32) -> u32 {
        let base = addr as usize;
        // Use checked arithmetic to avoid silent overflow on near-max addresses.
        match base.checked_add(4) {
            Some(end) if end <= self.memory.len() => u32::from_le_bytes([
                self.memory[base],
                self.memory[base + 1],
                self.memory[base + 2],
                self.memory[base + 3],
            ]),
            _ => 0,
        }
    }

    /// Advance the model by one clock cycle.
    ///
    /// # Arguments
    /// * `instr`     — 32-bit instruction word at the current PC.
    /// * `mem_rdata` — data word returned by the memory subsystem for loads.
    /// * `rst`       — active-high synchronous reset.
    ///
    /// # Returns
    /// `(alu_result, rs2_data, mem_write_enable)` for differential comparison
    /// against the RTL simulation output.
    pub fn step(&mut self, instr: u32, mem_rdata: u32, rst: bool) -> (u32, u32, bool) {
        // ── 1. Reset ─────────────────────────────────────────────────────────
        if rst {
            self.pc = 0;
            self.wait_counter = 0;
            self.reg_file.tick(true, 0, 0, false);
            // Reset does not advance the cycle counter (it's part of init).
            return (0, 0, false);
        }

        self.cycles_total += 1;

        // ── 2. LX.WAIT stall: hold the pipeline ──────────────────────────────
        // If a LX.WAIT stall is active, count down and hold PC.
        // PC does NOT advance inside this block; it advances naturally when
        // the caller presents the next (non-WAIT) instruction after the stall
        // expires and normal decode runs.
        if self.wait_counter > 0 {
            self.wait_counter -= 1;
            self.reg_file.tick(false, 0, 0, false);
            // Stall cycle: do NOT increment instructions_committed.
            return (0, 0, false);
        }

        // ── 3. Decode ─────────────────────────────────────────────────────────
        let opcode   = opcode_t::from_bits((instr & 0x7F) as u8);
        let funct3   = ((instr >> 12) & 0x7) as u8;
        let funct7_5 = ((instr >> 30) & 0x1) != 0;

        let ctrl    = control_unit_golden(opcode, funct3, funct7_5);
        let imm_ext = imm_gen_golden(instr);

        // ── 4. Register-file read ─────────────────────────────────────────────
        let rs1_addr = ((instr >> 15) & 0x1F) as u8;
        let rs2_addr = ((instr >> 20) & 0x1F) as u8;
        let rd_addr  = ((instr >>  7) & 0x1F) as u8;

        let rs1_data = self.reg_file.read_rs1(rs1_addr);
        let rs2_data = self.reg_file.read_rs2(rs2_addr);

        // ── 5. LX.WAIT — handle before the normal execute path ────────────────
        // ENCODING NOTE: The LX32 compiler encodes `lx.wait <reg>` with the
        // source register at bits[11:7] (the rd field), NOT at bits[19:15] (rs1).
        // rs1 is always x0 in the emitted binaries.  The RTL and this model both
        // read the cycle count from rd_addr / rd_field to match the compiler.
        let is_wait = ctrl.custom_1 && funct3 == 0b000;
        if is_wait {
            // rd_addr = instr[11:7] — the register containing the cycle count.
            let stall_cycles = self.reg_file.read_rs1(rd_addr); // rd field, not rs1
            self.reg_file.tick(false, 0, 0, false); // no write-back
            if stall_cycles > 0 {
                self.wait_counter = stall_cycles;
                // PC stays frozen; it advances inside the countdown block above.
            } else {
                // stall_cycles == 0: behaves as a NOP, advance PC immediately.
                self.pc = self.pc.wrapping_add(4);
            }
            return (0, 0, false);
        }

        // ── 6. Stub custom datapath values (mirrors RTL stubs) ────────────────
        // These are placeholder values returned by the stub sensor_controller
        // and dma_controller in simulation.  They must match the stubs in
        // `rtl/core/sensor_controller.sv` exactly for differential testing to
        // be meaningful.
        let sensor_idx  = (rs1_data & 0x3F) as u32;
        let sensor_val  = 1000u32 + sensor_idx;       // stub: index + 1000
        let delta_val   = 20u32;                       // stub: constant 20
        let matrix_ptr  = 0x5000_0000u32;              // stub: fixed snapshot base
        let active_keys = 0x0000_00FFu32;              // stub: keys 0-7 active
        let chord_match = u32::from((active_keys & rs1_data) == rs1_data);

        // ── 7. Execute ────────────────────────────────────────────────────────
        let alu_a = if ctrl.src_a_pc { self.pc } else { rs1_data };
        let alu_b = if ctrl.alu_src  { imm_ext } else { rs2_data };

        let alu_res     = alu_golden_model(alu_a, alu_b, ctrl.alu_control);
        // Branch evaluation always uses the raw register values, never the
        // MUXed alu_a/alu_b.
        let branch_taken = branch_unit_golden(rs1_data, rs2_data,
                                              ctrl.branch, ctrl.branch_op);

        // ── 8. Next-PC computation ────────────────────────────────────────────
        let next_pc = if ctrl.jump {
            if ctrl.jalr {
                rs1_data.wrapping_add(imm_ext) & 0xFFFF_FFFE
            } else {
                self.pc.wrapping_add(imm_ext)
            }
        } else if ctrl.branch && branch_taken {
            self.pc.wrapping_add(imm_ext)
        } else {
            self.pc.wrapping_add(4)
        };

        // ── 9. Write-back MUX ─────────────────────────────────────────────────
        // result_src encoding: 00=ALU, 01=Mem, 10=PC+4, 11=IMM
        let write_data = match ctrl.result_src {
            0b00 => {
                if ctrl.custom_0 {
                    match funct3 {
                        0b000 => sensor_val,
                        0b001 => matrix_ptr,
                        0b010 => delta_val,
                        0b011 => chord_match,
                        _     => 0,
                    }
                } else {
                    alu_res
                }
            }
            0b01 => mem_rdata,
            0b10 => self.pc.wrapping_add(4),
            0b11 => imm_ext,
            _    => alu_res,
        };

        // ── 10. Register-file write-back ──────────────────────────────────────
        self.reg_file.tick(false, rd_addr, write_data, ctrl.reg_write);

        // ── 11. Commit PC ─────────────────────────────────────────────────────
        self.pc = next_pc;
        self.instructions_committed += 1;

        // ── 12. Return LSU signals for differential validation ────────────────
        (alu_res, rs2_data, ctrl.mem_write)
    }
}
