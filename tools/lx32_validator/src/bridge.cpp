#include "Vlx32_system.h"
#include "Vlx32_system___024root.h"
#include "verilated.h"
#include <cstdint>

double sc_time_stamp() { return 0; }

extern "C" {
    void* create_core() {
        return static_cast<void*>(new Vlx32_system);
    }

    void eval_core(void* core, uint8_t reset, uint32_t instr, uint32_t mem_rdata) {
        Vlx32_system* top = static_cast<Vlx32_system*>(core);

        // Apply inputs from Rust to Verilog
        top->rst = reset;
        top->instr = instr;
        top->mem_rdata = mem_rdata;

        // Combinatorial eval only
        top->eval();
    }

    void tick_core(void* core, uint8_t reset, uint32_t instr, uint32_t mem_rdata) {
        Vlx32_system* top = static_cast<Vlx32_system*>(core);

        // Apply inputs from Rust to Verilog
        top->rst = reset;
        top->instr = instr;
        top->mem_rdata = mem_rdata;

        // Pulse Clock
        top->clk = 0;
        top->eval();
        top->clk = 1;
        top->eval();
    }

    uint32_t get_pc(void* core) {
        Vlx32_system* top = static_cast<Vlx32_system*>(core);
        return top->pc_out;
    }

    uint32_t get_mem_addr(void* core) {
        Vlx32_system* top = static_cast<Vlx32_system*>(core);
        return top->mem_addr;
    }

    uint32_t get_mem_wdata(void* core) {
        Vlx32_system* top = static_cast<Vlx32_system*>(core);
        return top->mem_wdata;
    }

    uint8_t get_mem_we(void* core) {
        Vlx32_system* top = static_cast<Vlx32_system*>(core);
        return top->mem_we;
    }

    uint32_t get_reg(void* core, uint8_t index) {
        Vlx32_system* top = static_cast<Vlx32_system*>(core);
        if (index >= 32) return 0;
        // Updated from 'regs' to 'regs_out'
        return top->rootp->lx32_system__DOT__rf__DOT__regs_out[index];
    }
}
