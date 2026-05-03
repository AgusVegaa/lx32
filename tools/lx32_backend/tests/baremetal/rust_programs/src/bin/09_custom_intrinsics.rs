//! LX32K custom instruction smoke test via inline assembly.
//!
//! Exercises all six hardware instructions:
//!   lx.sensor  — read Hall-effect sensor at index 0
//!   lx.matrix  — get pointer to 64-key snapshot buffer
//!   lx.delta   — frame-to-frame velocity for key 0
//!   lx.chord   — test bitmask 0b11 (keys 0 and 1)
//!   lx.wait    — precise 100-cycle pipeline stall
//!   lx.report  — initiate DMA transfer of an 8-byte HID report
//!
//! Expected exit code: 0.
#![no_std]
#![no_main]
#![allow(asm_sub_register)]

#[no_mangle]
pub extern "C" fn main() -> i32 {
    #[cfg(target_arch = "lx32")]
    // SAFETY: Each LX32K instruction is a pure read or idempotent side effect.
    unsafe {
        let _sensor: i32;
        core::arch::asm!(
            "lx.sensor {rd}, {rs1}",
            rd  = out(reg) _sensor,
            rs1 = in(reg)  0u32,
            options(nomem, nostack, pure),
        );

        let _matrix_ptr: u32;
        core::arch::asm!(
            "lx.matrix {rd}, {rs1}",
            rd  = out(reg) _matrix_ptr,
            rs1 = in(reg)  0u32,
            options(nomem, nostack, pure),
        );

        let _delta: i32;
        core::arch::asm!(
            "lx.delta {rd}, {rs1}",
            rd  = out(reg) _delta,
            rs1 = in(reg)  0u32,
            options(nomem, nostack, pure),
        );

        let _chord: u32;
        core::arch::asm!(
            "lx.chord {rd}, {rs1}",
            rd  = out(reg) _chord,
            rs1 = in(reg)  3u32,
            options(nomem, nostack, pure),
        );

        core::arch::asm!(
            "lx.wait {rs1}",
            rs1 = in(reg) 100u32,
            options(nostack),
        );

        let report: [u8; 8] = [0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00];
        core::arch::asm!(
            "lx.report {rs1}",
            rs1 = in(reg) report.as_ptr(),
            options(nostack),
        );
    }

    0
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
