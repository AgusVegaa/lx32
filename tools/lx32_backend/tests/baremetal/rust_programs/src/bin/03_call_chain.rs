//! Multi-level function call chain: validates JAL/JALR round-trips.
//! Expected exit code: 8  (chain(3) = (3+1)*2 = 8).
#![no_std]
#![no_main]

fn add(a: i32, b: i32) -> i32 {
    a + b
}

fn double(x: i32) -> i32 {
    add(x, x)
}

fn chain(x: i32) -> i32 {
    double(add(x, 1))
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    chain(3)
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
