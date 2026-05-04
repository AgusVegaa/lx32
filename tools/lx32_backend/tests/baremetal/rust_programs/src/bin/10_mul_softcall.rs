//! Integer multiply — exercises the __mulsi3 software-multiply libcall path.
//!
//! LX32 has no MUL instruction; multiplication is expanded to a compiler_builtins
//! routine.  This test verifies that the libcall dispatch, argument marshalling
//! (a0=6, a1=7 → __mulsi3), and return-value receipt (a0=42) all work correctly.
//!
//! Expected exit code: 42.
#![no_std]
#![no_main]

#[inline(never)]
fn mul(a: i32, b: i32) -> i32 {
    a * b
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    mul(6, 7)
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
