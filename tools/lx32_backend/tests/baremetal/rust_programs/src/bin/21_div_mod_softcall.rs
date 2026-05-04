//! Unsigned div/mod libcall test — validates compiler_builtins division helpers.
//!
//! Expected exit code: 12.
#![no_std]
#![no_main]

#[inline(never)]
fn div_mod(a: u32, b: u32) -> i32 {
    ((a / b) + (a % b)) as i32
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    div_mod(100, 9)
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
