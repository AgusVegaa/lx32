//! LX32K bare-metal Rust runtime (`rt` feature).
//!
//! Provides two things that every bare-metal binary needs:
//!
//! 1. **`_start`** — the reset entry point at `0x00000000`.
//! 2. **`#[panic_handler]`** — loops forever; no heap, no formatting.
//!
//! # Entry point contract
//!
//! `_start` mirrors the C `crt0.S` it replaces:
//!
//! ```text
//! _start:
//!     lui  sp, 1          # sp = 0x1000 (top of 4 KB RAM)
//!     jal  ra, main       # call user main()
//!     lui  t0, 0xFFFFF    # t0 = 0xFFFFF000
//!     sw   a0, 4(t0)      # *(0xFFFFF004) = exit code  ← simulator halt
//! _halt:
//!     jal  x0, _halt      # spin forever
//! ```
//!
//! # Firmware entry point
//!
//! Your firmware crate must export `main` with the C ABI:
//!
//! ```no_run
//! #![no_std]
//! #![no_main]
//!
//! #[no_mangle]
//! pub extern "C" fn main() -> i32 {
//!     loop { /* scan keys, send reports */ }
//! }
//! ```
//!
//! Do **not** link `crt0.o` alongside this feature.

// Only meaningful on LX32 — skipped by `cargo check` on the host so the
// assembly template is never handed to the host assembler.
#[cfg(target_arch = "lx32")]
core::arch::global_asm!(
    ".section .text.startup",
    ".globl _start",
    ".type  _start, @function",
    "_start:",
    // Set up the stack.  The linker script places _stack_top at 0x1000.
    // lui encodes bits[31:12], so `lui sp, 1` → sp = 0x00001000.
    "    lui  sp, 1",
    // Call user main().  JAL writes the return address to ra (x1).
    // Within 4 KB the JAL ±1 MB range is always sufficient.
    "    jal  ra, main",
    // Halt: write main's return value (a0) to the simulator exit register.
    "    lui  t0, 0xFFFFF",     // t0 = 0xFFFFF000
    "    sw   a0, 4(t0)",       // *(0xFFFFF004) = exit code
    "_lx32_halt:",
    "    jal  x0, _lx32_halt",  // spin — USB stays alive, debugger can attach
    ".size _start, . - _start",
);

/// Panic handler — spin forever.
///
/// On a keyboard controller, a panic is always a firmware bug.  We spin
/// rather than resetting so that:
///
/// - USB stays enumerated (the host sees no disconnect).
/// - A debugger can attach and read the call stack.
/// - The simulator watchdog times out and flags a hung program rather than
///   a clean exit, which is much easier to spot in test output.
///
/// Zero overhead: no formatting, no heap, no syscall.
#[cfg(target_arch = "lx32")]
#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {
        core::hint::spin_loop();
    }
}
