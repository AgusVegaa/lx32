//! Iterative Fibonacci — tests loop-carried values and register allocation.
//! Expected exit code: 55  (fib(10) = 55).
#![no_std]
#![no_main]

fn fib(n: u32) -> i32 {
    if n <= 1 {
        return n as i32;
    }
    let mut a = 0i32;
    let mut b = 1i32;
    let mut i = 2u32;
    while i <= n {
        let tmp = a + b;
        a = b;
        b = tmp;
        i += 1;
    }
    b
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    fib(10)
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
