use clap::Parser;
use lx32_validator::*;
use std::ffi::c_void;
use std::fs;
use std::path::Path;

/// RISC-V ILP32 ABI register names, indexed by register number (x0–x31).
static ABI_NAMES: [&str; 32] = [
    "zero", "ra",  "sp",  "gp",  "tp",  "t0",  "t1",  "t2",
    "s0",   "s1",  "a0",  "a1",  "a2",  "a3",  "a4",  "a5",
    "a6",   "a7",  "s2",  "s3",  "s4",  "s5",  "s6",  "s7",
    "s8",   "s9",  "s10", "s11", "t3",  "t4",  "t5",  "t6",
];

#[derive(Parser, Debug)]
#[command(name = "lx32_runner")]
#[command(about = "Runs a raw LX32 binary on the RTL simulation")]
struct Args {
    /// Path to the raw LX32 binary file (.bin)
    #[arg(short, long)]
    binary: String,

    /// Maximum clock cycles to simulate before halting
    #[arg(short = 'm', long, default_value_t = 1_000_000)]
    max_cycles: u64,

    /// Verbose cycle-by-cycle logging (suppressed when --json is set)
    #[arg(short, long)]
    verbose: bool,

    /// Emit results as a single JSON object on stdout; all diagnostics go to stderr.
    /// Designed for use by `make bench-all` to build the JSON report array.
    #[arg(long)]
    json: bool,
}

// ── Instruction mix ──────────────────────────────────────────────────────────
//
// Classifies every dynamically-committed instruction (i.e. instructions where
// the PC advanced — stall cycles are excluded) by its RISC-V opcode field.
// This gives the dynamic instruction mix for the program run.

#[derive(Default, Debug)]
struct InstrMix {
    alu:       u64,   // 0x13 / 0x33  — ADDI, ADD, XOR, OR, AND, SLL, SRL, SLT, …
    load:      u64,   // 0x03         — LW, LH, LHU, LB, LBU
    store:     u64,   // 0x23         — SW, SH, SB
    branch:    u64,   // 0x63         — BEQ, BNE, BLT, BGE, BLTU, BGEU
    jump:      u64,   // 0x6F / 0x67  — JAL, JALR
    upper_imm: u64,   // 0x37 / 0x17  — LUI, AUIPC
    custom:    u64,   // 0x0B / 0x2B  — LX.SENSOR, LX.MATRIX, LX.DELTA, LX.CHORD, LX.WAIT, LX.REPORT
    other:     u64,   // SYSTEM, unrecognised
}

impl InstrMix {
    fn record(&mut self, instr: u32) {
        match instr & 0x7F {
            0x03        => self.load      += 1,
            0x23        => self.store     += 1,
            0x63        => self.branch    += 1,
            0x6F | 0x67 => self.jump      += 1,
            0x37 | 0x17 => self.upper_imm += 1,
            0x13 | 0x33 => self.alu       += 1,
            0x0B | 0x2B => self.custom    += 1,
            _           => self.other     += 1,
        }
    }
}

// ── Exit condition ───────────────────────────────────────────────────────────

#[derive(Debug)]
enum ExitCondition {
    /// Program wrote its exit code to an MMIO port and halted cleanly.
    Mmio { addr: u32, code: u32 },
    /// PC advanced outside the loaded memory image.
    PcOutOfBounds,
    /// Simulation reached the configured cycle limit without a clean exit.
    MaxCycles,
}

impl ExitCondition {
    fn status_str(&self) -> &'static str {
        match self {
            ExitCondition::Mmio { .. }      => "exited_mmio",
            ExitCondition::PcOutOfBounds    => "pc_out_of_bounds",
            ExitCondition::MaxCycles        => "max_cycles",
        }
    }
}

// ── Main ─────────────────────────────────────────────────────────────────────

fn main() {
    let args = Args::parse();

    // Load binary into a 64 KiB flat address space (instruction + data, von
    // Neumann model matching the baremetal link.ld layout).
    let binary_data = match fs::read(&args.binary) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("error: failed to read '{}': {}", args.binary, e);
            std::process::exit(1);
        }
    };

    let mut memory = vec![0u8; 64 * 1024];
    let load_size = binary_data.len().min(memory.len());
    memory[..load_size].copy_from_slice(&binary_data[..load_size]);

    eprintln!("Loaded {} bytes from {}", load_size, args.binary);

    let core: *mut c_void = unsafe { create_core() };

    // Five synchronous reset cycles — initialises all pipeline registers.
    for _ in 0..5 {
        unsafe { tick_core(core, 1, 0, 0) };
    }

    eprintln!("Starting simulation (max cycles: {})...", args.max_cycles);

    // ── Metrics ──────────────────────────────────────────────────────────────
    let mut cycles: u64 = 0;
    let mut instructions_committed: u64 = 0;  // cycles where PC advanced
    let mut stall_cycles: u64 = 0;             // cycles where PC held (LX.WAIT)
    let mut mix = InstrMix::default();

    // Previous PC: used to detect PC advancement vs. stall.
    // Initialised to None so the very first cycle is always counted as committed.
    let mut prev_pc: Option<u32> = None;

    let mut exit_cond = ExitCondition::MaxCycles;

    'sim: loop {
        // ── Fetch ─────────────────────────────────────────────────────────
        let pc = unsafe { get_pc(core) };

        if pc as usize + 4 > memory.len() {
            eprintln!("Halted: PC 0x{:08X} out of bounds after {} cycles", pc, cycles);
            exit_cond = ExitCondition::PcOutOfBounds;
            break 'sim;
        }

        let instr = u32::from_le_bytes([
            memory[pc as usize],
            memory[pc as usize + 1],
            memory[pc as usize + 2],
            memory[pc as usize + 3],
        ]);

        // ── Combinational evaluation ───────────────────────────────────────
        // Drive inputs, settle combinational outputs (mem_addr/we/wdata)
        // before the clock edge.
        unsafe { eval_core(core, 0, instr, 0) };

        let mem_addr  = unsafe { get_mem_addr(core) };
        let mem_we    = unsafe { get_mem_we(core) };
        let mem_wdata = unsafe { get_mem_wdata(core) };

        // ── Memory write ───────────────────────────────────────────────────
        if mem_we != 0 {
            if args.verbose && !args.json {
                println!("Cycle {:05}: STORE [0x{:08X}] ← 0x{:08X}", cycles, mem_addr, mem_wdata);
            }

            // MMIO exit ports used by the baremetal crt0.S:
            //   0xFFFFF004 — primary exit port (lui x5, 0xFFFF; sw x10, 4(x5))
            //   0x80000000 — legacy port
            if mem_addr == 0x8000_0000 || mem_addr == 0xFFFF_F004 {
                eprintln!("Exited via MMIO 0x{:08X} (code: {}) at cycle {}",
                          mem_addr, mem_wdata, cycles);
                exit_cond = ExitCondition::Mmio { addr: mem_addr, code: mem_wdata };
                break 'sim;
            }

            let addr = mem_addr as usize;
            if addr + 4 <= memory.len() {
                memory[addr..addr + 4].copy_from_slice(&mem_wdata.to_le_bytes());
            } else {
                eprintln!("Warning: store to unmapped address 0x{:08X}", mem_addr);
            }
        }

        // ── Load data ──────────────────────────────────────────────────────
        let mem_rdata = {
            let aligned = (mem_addr as usize) & !3;
            if aligned + 4 <= memory.len() {
                u32::from_le_bytes([
                    memory[aligned],
                    memory[aligned + 1],
                    memory[aligned + 2],
                    memory[aligned + 3],
                ])
            } else {
                0
            }
        };

        // ── Clock edge ─────────────────────────────────────────────────────
        unsafe { tick_core(core, 0, instr, mem_rdata) };

        // ── IPC accounting ─────────────────────────────────────────────────
        // A cycle is "committed" when the PC advances.  Stall cycles (from
        // LX.WAIT) hold the PC constant and do not retire an instruction.
        let pc_advanced = prev_pc.map_or(true, |p| p != pc);
        if pc_advanced {
            instructions_committed += 1;
            mix.record(instr);
        } else {
            stall_cycles += 1;
        }

        if args.verbose && !args.json {
            let stall_tag = if pc_advanced { "" } else { " [STALL]" };
            println!("Cycle {:05}: PC=0x{:08X}  instr=0x{:08X}{}", cycles, pc, instr, stall_tag);
        }

        prev_pc = Some(pc);
        cycles += 1;

        if cycles >= args.max_cycles {
            eprintln!("Stopped: reached max cycles ({})", args.max_cycles);
            exit_cond = ExitCondition::MaxCycles;
            break 'sim;
        }
    }

    // ── Derived metrics ────────────────────────────────────────────────────
    let ipc = if cycles > 0 {
        instructions_committed as f64 / cycles as f64
    } else {
        0.0
    };

    // Number of 32-bit instruction words in the binary (static code size).
    let static_instr_count = load_size / 4;

    // ── Output ─────────────────────────────────────────────────────────────
    if args.json {
        emit_json(&args.binary, load_size, static_instr_count,
                  &exit_cond, cycles, instructions_committed, stall_cycles,
                  ipc, &mix, core);
    } else {
        emit_human(&exit_cond, cycles, instructions_committed, stall_cycles,
                   ipc, &mix, core);
    }
}

// ── JSON emitter ──────────────────────────────────────────────────────────────
//
// Writes a single JSON object to stdout.  No serde dependency — the schema is
// fixed and the values are all primitives or small arrays.
//
// Design contract: stdout carries ONLY the JSON object; all diagnostics were
// emitted on stderr earlier in the run.  This lets the Makefile `bench-run`
// target redirect stdout directly into the report array.

fn emit_json(
    binary_path: &str,
    binary_bytes: usize,
    static_instructions: usize,
    exit: &ExitCondition,
    cycles: u64,
    committed: u64,
    stalls: u64,
    ipc: f64,
    mix: &InstrMix,
    core: *mut c_void,
) {
    let prog_name = Path::new(binary_path)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("unknown");

    let (exit_code_field, exit_addr_field) = match exit {
        ExitCondition::Mmio { addr, code } => {
            (code.to_string(), format!("\"0x{:08X}\"", addr))
        }
        _ => ("null".to_string(), "null".to_string()),
    };

    // Build register array [x0, x1, ..., x31]
    let regs: Vec<u32> = (0..32u8).map(|i| unsafe { get_reg(core, i) }).collect();
    let regs_json = regs.iter()
        .map(|r| r.to_string())
        .collect::<Vec<_>>()
        .join(", ");

    println!("{{");
    println!("  \"program\": \"{}\",",          prog_name);
    println!("  \"binary_path\": \"{}\",",      binary_path.replace('\\', "/"));
    println!("  \"binary_bytes\": {},",         binary_bytes);
    println!("  \"static_instructions\": {},",  static_instructions);
    println!("  \"status\": \"{}\",",           exit.status_str());
    println!("  \"exit_code\": {},",            exit_code_field);
    println!("  \"exit_mmio_addr\": {},",       exit_addr_field);
    println!("  \"cycles_total\": {},",         cycles);
    println!("  \"instructions_committed\": {},", committed);
    println!("  \"stall_cycles\": {},",         stalls);
    println!("  \"ipc\": {:.4},",              ipc);
    println!("  \"instruction_mix\": {{");
    println!("    \"alu\": {},",       mix.alu);
    println!("    \"load\": {},",      mix.load);
    println!("    \"store\": {},",     mix.store);
    println!("    \"branch\": {},",    mix.branch);
    println!("    \"jump\": {},",      mix.jump);
    println!("    \"upper_imm\": {},", mix.upper_imm);
    println!("    \"custom\": {},",    mix.custom);
    println!("    \"other\": {}",      mix.other);
    println!("  }},");
    print!(  "  \"registers\": [{}]",  regs_json);
    println!("\n}}");
}

// ── Human-readable emitter ────────────────────────────────────────────────────

fn emit_human(
    exit: &ExitCondition,
    cycles: u64,
    committed: u64,
    stalls: u64,
    ipc: f64,
    mix: &InstrMix,
    core: *mut c_void,
) {
    println!("\n{:=<60}", "");
    println!("Exit condition : {}", exit.status_str());
    if let ExitCondition::Mmio { addr, code } = exit {
        println!("Exit code      : {} (via 0x{:08X})", code, addr);
    }

    println!("\nPerformance");
    println!("  Total cycles         : {}", cycles);
    println!("  Instructions committed: {}", committed);
    println!("  Stall cycles (LX.WAIT): {}", stalls);
    println!("  IPC                  : {:.4}", ipc);

    let total_mix = mix.alu + mix.load + mix.store + mix.branch
                  + mix.jump + mix.upper_imm + mix.custom + mix.other;
    println!("\nInstruction mix (dynamic, {} committed):", total_mix);
    println!("  ALU       {:5}  ({:5.1}%)", mix.alu,
        pct(mix.alu, total_mix));
    println!("  Load      {:5}  ({:5.1}%)", mix.load,
        pct(mix.load, total_mix));
    println!("  Store     {:5}  ({:5.1}%)", mix.store,
        pct(mix.store, total_mix));
    println!("  Branch    {:5}  ({:5.1}%)", mix.branch,
        pct(mix.branch, total_mix));
    println!("  Jump      {:5}  ({:5.1}%)", mix.jump,
        pct(mix.jump, total_mix));
    println!("  Upper-imm {:5}  ({:5.1}%)", mix.upper_imm,
        pct(mix.upper_imm, total_mix));
    println!("  Custom    {:5}  ({:5.1}%)", mix.custom,
        pct(mix.custom, total_mix));
    println!("  Other     {:5}  ({:5.1}%)", mix.other,
        pct(mix.other, total_mix));

    println!("\nFinal register state");
    println!("{:-<56}", "");
    for i in 0..32usize {
        let val = unsafe { get_reg(core, i as u8) };
        print!("  x{:<2} ({:<4}): 0x{:08X}", i, ABI_NAMES[i], val);
        if i % 2 == 1 { println!(); }
    }
    if 32 % 2 != 0 { println!(); }
    println!("{:=<60}", "");
}

fn pct(part: u64, total: u64) -> f64 {
    if total == 0 { 0.0 } else { part as f64 / total as f64 * 100.0 }
}
