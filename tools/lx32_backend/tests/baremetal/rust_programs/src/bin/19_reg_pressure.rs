//! Register-pressure test — many live values across loop iterations.
//!
//! Expected exit code: 102.
#![no_std]
#![no_main]

#[inline(never)]
fn mix(a: i32, b: i32, c: i32, d: i32, e: i32, f: i32, g: i32, h: i32) -> i32 {
    a + b - c + d - e + f - g + h
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    let mut acc = 0i32;
    let mut i = 0i32;
    while i < 4 {
        acc += mix(i, 10, 3, 8, 2, 7, 1, 5);
        i += 1;
    }
    acc
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
