//! Shift/logic mix — validates combined SHL/SHR/OR/XOR lowering.
//!
//! Expected exit code: 34.
#![no_std]
#![no_main]

#[inline(never)]
fn scramble(x: u32) -> i32 {
    let a = (x << 5) | (x >> 3);
    ((a ^ 0xA5) & 0xFF) as i32
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    scramble(0x3C)
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
