//! Pointer walking over a stack array using an iterator.
//! Expected exit code: 15  (1+2+3+4+5 = 15).
#![no_std]
#![no_main]

#[no_mangle]
pub extern "C" fn main() -> i32 {
    let arr = [1i32, 2, 3, 4, 5];
    let mut sum = 0i32;
    for &v in arr.iter() {
        sum += v;
    }
    sum
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
