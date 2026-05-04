//! Global static array access — exercises PseudoLA / GlobalAddress lowering.
//!
//! The static `DATA` lands in `.rodata` (linked into RAM by the linker script).
//! `sum_ends` receives a raw pointer from `DATA.as_ptr()` — the compiler must
//! emit a PseudoLA sequence (AUIPC + ADDI) to materialise the symbol address,
//! then two LW instructions to load the elements.
//!
//! Expected exit code: 50  (DATA[0] + DATA[3] = 10 + 40).
#![no_std]
#![no_main]

static DATA: [i32; 4] = [10, 20, 30, 40];

#[inline(never)]
fn sum_ends(ptr: *const i32) -> i32 {
    unsafe { *ptr + *ptr.add(3) }
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    sum_ends(DATA.as_ptr())
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
