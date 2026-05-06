//! LX32K custom instruction smoke test — free register allocation.
//!
//! Uses named template arguments (`{rd}`, `{rs1}`) so the compiler's register
//! allocator assigns operand registers freely instead of forcing x10/x11.
//! Each `asm!` block compiles to exactly one custom instruction.
//!
//! Expected exit code: 0.
#![no_std]
#![no_main]

#[no_mangle]
pub extern "C" fn main() -> i32 {
    unsafe {
        // lx.sensor rd, rs1  — read Hall-effect sensor 0.
        let _sensor: i32;
        core::arch::asm!(
            "lx.sensor {rd}, {rs1}",
            rd  = lateout(reg) _sensor,
            rs1 = in(reg) 0u32,
            options(nomem, nostack),
        );

        // lx.matrix rd, rs1  — get base address of the sensor snapshot buffer.
        let _matrix_ptr: u32;
        core::arch::asm!(
            "lx.matrix {rd}, {rs1}",
            rd  = lateout(reg) _matrix_ptr,
            rs1 = in(reg) 0u32,
            options(nomem, nostack),
        );

        // lx.delta rd, rs1  — frame-to-frame velocity for key 0.
        let _delta: i32;
        core::arch::asm!(
            "lx.delta {rd}, {rs1}",
            rd  = lateout(reg) _delta,
            rs1 = in(reg) 0u32,
            options(nomem, nostack),
        );

        // lx.chord rd, rs1  — test bitmask for keys 0 and 1 simultaneously.
        let _chord: u32;
        core::arch::asm!(
            "lx.chord {rd}, {rs1}",
            rd  = lateout(reg) _chord,
            rs1 = in(reg) 0b11u32,
            options(nomem, nostack),
        );

        // lx.wait rs1  — stall pipeline for 0 cycles (hardware no-op).
        core::arch::asm!(
            "lx.wait {rs1}",
            rs1 = in(reg) 0u32,
            options(nostack),
        );

        // lx.report rs1  — DMA transfer of an 8-byte HID report.
        let report_buf = [0u8; 8];
        core::arch::asm!(
            "lx.report {rs1}",
            rs1 = in(reg) report_buf.as_ptr() as u32,
            options(nostack),
        );
    }

    0
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
