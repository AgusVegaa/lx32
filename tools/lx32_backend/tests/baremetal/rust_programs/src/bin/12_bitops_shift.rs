//! Bit operations and shifts — exercises SRL, SRLI, AND, OR, XOR patterns.
//!
//! Uses `#[inline(never)]` to prevent constant folding across call boundaries,
//! ensuring the backend actually emits the shift and bitwise instructions.
//!
//! Computation (x = 100 = 0b01100100):
//!   high3  = 100 >> 3  = 12   (SRLI: upper bits)
//!   low3   = 100 & 7   =  4   (ANDI: lower 3 bits)
//!   result = high3 | low3 = 12 | 4 = 12  (0b1100 | 0b0100 = 0b1100)
//!
//! Expected exit code: 12.
#![no_std]
#![no_main]

#[inline(never)]
fn bit_crunch(x: u32) -> i32 {
    let high = x >> 3;     // SRLI  100 >> 3 = 12
    let low  = x & 7;      // ANDI  100 &  7 =  4
    (high | low) as i32    // OR    12  |  4 = 12 (low bits already subset)
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    bit_crunch(100)
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
