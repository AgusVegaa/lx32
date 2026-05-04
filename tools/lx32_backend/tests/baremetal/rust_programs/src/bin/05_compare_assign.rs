//! Comparison and conditional assignment.
//! Expected exit code: 10  (|20 - 10| = 10).
#![no_std]
#![no_main]

#[no_mangle]
pub extern "C" fn main() -> i32 {
    let a = 10i32;
    let b = 20i32;
    if a < b { b - a } else { a - b }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
