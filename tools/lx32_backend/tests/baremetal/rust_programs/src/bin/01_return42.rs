//! Minimal sanity test: return a known constant.
//! Expected exit code: 42.
#![no_std]
#![no_main]

#[no_mangle]
pub extern "C" fn main() -> i32 {
    42
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
