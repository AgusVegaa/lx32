//! Nested loops — exercises register pressure and multi-level control flow.
//!
//! Inner loop runs 0..i iterations for each outer step i = 0..5, accumulating
//! partial sums into `sum`.  The double-loop structure forces the register
//! allocator to keep two counters live simultaneously.
//!
//! Calculation:
//!   i=0: inner runs 0 times  → sum += 0
//!   i=1: j=0                 → sum += 0       (total: 0)
//!   i=2: j=0,1               → sum += 0+1     (total: 1)
//!   i=3: j=0,1,2             → sum += 0+1+2   (total: 4)
//!   i=4: j=0,1,2,3           → sum += 0+1+2+3 (total: 10)
//!
//! Expected exit code: 10.
#![no_std]
#![no_main]

#[no_mangle]
pub extern "C" fn main() -> i32 {
    let mut sum = 0i32;
    let mut i = 0i32;
    while i < 5 {
        let mut j = 0i32;
        while j < i {
            sum += j;
            j += 1;
        }
        i += 1;
    }
    sum
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
