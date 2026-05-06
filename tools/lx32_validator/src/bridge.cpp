#include "Vlx32_system.h"
#include "Vlx32_system___024root.h"
#include "verilated.h"
#include <cstdint>

double sc_time_stamp() { return 0; }

// ── Pipeline-drain bridge ────────────────────────────────────────────────────
//
// lx32_system is a 2-stage pipeline (IF | EX).  Each tick_core call does two
// internal clock pulses to present single-cycle-equivalent semantics to the
// Rust test framework:
//
//   Pulse 1 (debug_stall=0):  instruction clocked into IF/EX register; PC
//                              advances by 4.
//   Pulse 2 (debug_stall=1):  EX commits the instruction (register write,
//                              branch target, mem write); IF/EX flushed to
//                              NOP; PC frozen unless a branch/jump resolved.
//
// Memory-write signals (mem_we, mem_addr, mem_wdata) are snapshotted at the
// negedge of pulse 2 — while if_ex still holds the real instruction — and
// returned by get_mem_we / get_mem_addr / get_mem_wdata.  This is required
// because the posedge of pulse 2 flushes if_ex to NOP, driving those
// combinatorial outputs to 0 afterward.
// ─────────────────────────────────────────────────────────────────────────────

static uint8_t  s_mem_we    = 0;
static uint32_t s_mem_addr  = 0;
static uint32_t s_mem_wdata = 0;

extern "C" {
    void* create_core() {
        return static_cast<void*>(new Vlx32_system);
    }

    void eval_core(void* core, uint8_t reset, uint32_t instr, uint32_t mem_rdata) {
        Vlx32_system* top = static_cast<Vlx32_system*>(core);
        top->rst       = reset;
        top->instr     = instr;
        top->mem_rdata = mem_rdata;
        top->eval();
    }

    void tick_core(void* core, uint8_t reset, uint32_t instr, uint32_t mem_rdata) {
        Vlx32_system* top = static_cast<Vlx32_system*>(core);

        // ── Pulse 1: load instruction into IF/EX ──────────────────────────────
        top->rst         = reset;
        top->instr       = instr;
        top->mem_rdata   = mem_rdata;
        top->debug_stall = 0;
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();

        // ── Pulse 2: EX commits; PC frozen (unless branch/jump) ──────────────
        top->debug_stall = 1;
        top->clk = 0; top->eval();
        // Snapshot memory signals NOW — if_ex still holds the real instruction.
        // After the posedge, if_ex is flushed to NOP and these go to 0.
        s_mem_we    = top->mem_we;
        s_mem_addr  = top->mem_addr;
        s_mem_wdata = top->mem_wdata;
        top->clk = 1; top->eval();

        // Restore debug_stall so combinatorial paths settle in idle state.
        top->debug_stall = 0;
        top->eval();
    }

    uint32_t get_pc(void* core) {
        Vlx32_system* top = static_cast<Vlx32_system*>(core);
        return top->pc_out;
    }

    uint32_t get_mem_addr(void* core)  { return s_mem_addr;  }
    uint32_t get_mem_wdata(void* core) { return s_mem_wdata; }
    uint8_t  get_mem_we(void* core)    { return s_mem_we;    }

    uint32_t get_reg(void* core, uint8_t index) {
        Vlx32_system* top = static_cast<Vlx32_system*>(core);
        if (index >= 32) return 0;
        return top->rootp->lx32_system__DOT__rf__DOT__regs_out[index];
    }
}
