//! Multiple function arguments — exercises the full a0–a4 argument register path.
//!
//! Verifies that five i32 arguments are correctly passed in a0-a4 (X10-X14)
//! and that the callee sums them to produce the expected result.
//!
//! Calculation: 1 + 2 + 4 + 8 + 16 = 31.
//!
//! Expected exit code: 31.
#![no_std]
#![no_main]

#[inline(never)]
fn sum5(a: i32, b: i32, c: i32, d: i32, e: i32) -> i32 {
    a + b + c + d + e
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    sum5(1, 2, 4, 8, 16)
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
