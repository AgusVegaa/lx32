//! Multi-branch classification — exercises compare-and-branch chains (BLT/BGE).
//!
//! `classify` is marked `#[inline(never)]` to force a real call + branch sequence
//! for each of the three distinct code paths.
//!
//! Calculation: classify(500)=3.
//!
//! Expected exit code: 3.
#![no_std]
#![no_main]

#[inline(never)]
fn classify(x: i32) -> i32 {
    if x < 10 {
        1
    } else if x < 100 {
        2
    } else {
        3
    }
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    classify(500)
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
