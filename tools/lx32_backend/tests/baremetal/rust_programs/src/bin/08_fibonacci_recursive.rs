//! Recursive Fibonacci — stresses the stack (prologue/epilogue, callee-saved regs).
//! Expected exit code: 55  (fib(10) = 55).
#![no_std]
#![no_main]

#[inline(never)]
fn fib(n: i32) -> i32 {
    if n <= 1 { n } else { fib(n - 1) + fib(n - 2) }
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    fib(10)
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
