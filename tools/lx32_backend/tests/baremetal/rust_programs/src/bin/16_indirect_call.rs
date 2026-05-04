//! Conditional multi-call path — validates branching into distinct call targets.
//!
//! Expected exit code: 31.
#![no_std]
#![no_main]

#[inline(never)]
fn add3(x: i32) -> i32 {
    x + 3
}

#[inline(never)]
fn mul2(x: i32) -> i32 {
    x * 2
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    let selector = 1u32;
    let left = unsafe {
        if core::ptr::read_volatile(&selector) == 1 {
            add3(20)
        } else {
            mul2(20)
        }
    };
    left + mul2(4)
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
