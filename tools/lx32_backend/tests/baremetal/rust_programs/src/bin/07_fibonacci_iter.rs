//! Iterative Fibonacci — tests loop-carried values and register allocation.
//! Expected exit code: 55  (fib(10) = 55).
#![no_std]
#![no_main]

fn fib(n: u32) -> i32 {
    if n <= 1 {
        return n as i32;
    }
    let (mut a, mut b) = (0i32, 1i32);
    for _ in 2..=n {
        let tmp = a + b;
        a = b;
        b = tmp;
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
