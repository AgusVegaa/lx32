//! Control flow: while loop with accumulator.
//! Expected exit code: 45  (0+1+2+…+9 = 45).
#![no_std]
#![no_main]

#[no_mangle]
pub extern "C" fn main() -> i32 {
    let mut sum = 0i32;
    let mut i   = 0i32;
    while i < 10 {
        sum += i;
        i   += 1;
    }
    sum
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
