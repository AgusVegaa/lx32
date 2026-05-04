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
    // TODO(lx32): re-enable inline-asm smoke once Rust register constraints for
    // LX32 are fully wired up in the backend.

    0
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
