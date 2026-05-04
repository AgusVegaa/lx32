//! Signed-extension regression — checks i8 to i32 sign propagation.
//!
//! Expected exit code: 27.
#![no_std]
#![no_main]

#[inline(never)]
fn mix(x: i8, y: u8) -> i32 {
    let sx = x as i32;
    let uy = y as i32;
    if sx < 0 {
        (-sx) + uy
    } else {
        sx - uy
    }
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    mix(-7, 20)
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
