use clap::Parser;
use std::fs;
use lx32_validator::*;
use std::ffi::c_void;

#[derive(Parser, Debug)]
#[command(name = "lx32_runner")]
#[command(about = "Runs a raw binary on the LX32 RTL Simulation", long_about = None)]
struct Args {
    /// Path to the raw LX32 binary file
    #[arg(short, long)]
    binary: String,

    /// Maximum clock cycles to simulate
    #[arg(short = 'm', long, default_value_t = 1000000)]
    max_cycles: u64,

    /// Verbose cycle-by-cycle logging
    #[arg(short, long)]
    verbose: bool,
}

fn main() {
    let args = Args::parse();

    // Load binary file
    let binary_data = fs::read(&args.binary).expect("Failed to read binary file");

    // The instruction memory and data memory will be shared for simplicity (von Neumann)
    // Initialize 64KB memory space
    let mut memory = vec![0u8; 64 * 1024];

    // Copy program to memory (starting at address 0x0000_0000)
    let load_size = std::cmp::min(binary_data.len(), memory.len());
    memory[0..load_size].copy_from_slice(&binary_data[0..load_size]);

    println!("Loaded {} bytes from {}", load_size, args.binary);

    // Initialize the RTL core
    let core: *mut c_void = unsafe { create_core() };

    // Reset sequence
    for _ in 0..5 {
        unsafe { tick_core(core, 1 /* reset=true */, 0 /* instr=0 */, 0 /* mem_rdata=0 */) };
    }

    println!("Starting simulation (Max cycles: {})...", args.max_cycles);

    let mut cycles = 0;

    loop {
        // Fetch instruction (PC points to byte address)
        let pc = unsafe { get_pc(core) };
        if pc as usize >= memory.len() {
            println!("Execution halted: PC out of bounds (0x{:08X})", pc);
            break;
        }

        // LX32 is 4-byte aligned instructions (read little-endian)
        let instr = u32::from_le_bytes([
            memory[pc as usize],
            memory[(pc + 1) as usize],
            memory[(pc + 2) as usize],
            memory[(pc + 3) as usize],
        ]);

        // Capture last memory address RTL wanted to read
        // For a single-cycle, combinatorial memory read address is exposed during the cycle,
        // but we're mimicking asynchronous read by looking at the previous addr, or
        // we can fetch the read address here. Since memory interface might be purely combinational,
        // let's read the current memory address.
        // Apply instr and evaluatable memory state completely
        unsafe { eval_core(core, 0, instr, 0) }; // let model compute memory addresses

        let mem_addr = unsafe { get_mem_addr(core) };
        let mut mem_rdata = 0;

        if mem_addr < memory.len() as u32 {
            let addr = mem_addr as usize & !3; // word align
            if addr + 3 < memory.len() {
                 mem_rdata = u32::from_le_bytes([
                     memory[addr],
                     memory[addr + 1],
                     memory[addr + 2],
                     memory[addr + 3],
                 ]);
            }
        }

        // Tick the core one clock cycle (applies rdata, evaluates, then pulses clock to commit to registers/PC)
        unsafe { tick_core(core, 0, instr, mem_rdata) };

        // Post-tick, the writes would have been commanded in the combinational phase of the SAME cycle!
        // Wait, writes actually happen on the rising edge of the clock inside the RTL's memory module, OR external memory.
        // The `mem_we`, `mem_wdata`, `mem_addr` signals were stable correctly BEFORE we pulsed the clock.
        // So we should capture them evaluating before `tick_core`!


        // Handle memory write
        let mem_we = unsafe { get_mem_we(core) };
        if mem_we != 0 {
            let write_addr = unsafe { get_mem_addr(core) };
            let write_data = unsafe { get_mem_wdata(core) };

            if args.verbose {
                println!("Cycle {}: Memory Write 0x{:08X} -> [0x{:08X}]", cycles, write_data, write_addr);
            }

            // Simple MMIO for exiting the simulation loop
            if write_addr == 0x8000_0000 {
                println!("Simulation exited via MMIO (code: {}) at cycle {}", write_data, cycles);
                break;
            }

            if write_addr < memory.len() as u32 {
                let bytes = write_data.to_le_bytes();
                memory[write_addr as usize] = bytes[0];
                memory[(write_addr + 1) as usize] = bytes[1];
                memory[(write_addr + 2) as usize] = bytes[2];
                memory[(write_addr + 3) as usize] = bytes[3];
            } else {
                println!("Warning: Out of bounds write at 0x{:08X}", write_addr);
            }
        }

        if args.verbose {
            println!("Cycle {:05}: PC=0x{:08X}, Instr=0x{:08X}", cycles, pc, instr);
        }

        cycles += 1;
        if cycles >= args.max_cycles {
            println!("Simulation stopped: Reached max cycles ({})", args.max_cycles);
            break;
        }
    }

    // Dump final registers for verification
    println!("\nFinal Register State:");
    for i in 0..32 {
        let val = unsafe { get_reg(core, i as u8) };
        print!("x{:<2}: 0x{:08X}    ", i, val);
        if (i + 1) % 4 == 0 {
            println!();
        }
    }
}


