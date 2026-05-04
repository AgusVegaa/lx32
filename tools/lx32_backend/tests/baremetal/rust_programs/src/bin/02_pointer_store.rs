//! Pointer and LOAD/STORE operations on a stack-allocated array.
//! Expected exit code: 30.
#![no_std]
#![no_main]

#[no_mangle]
pub extern "C" fn main() -> i32 {
    let mut buf = [0i32; 4];
    buf[0] = 10;
    buf[1] = 20;
    buf[2] = buf[0] + buf[1];
    buf[2]
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
