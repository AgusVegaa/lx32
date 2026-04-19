//! Cycle-accurate timing utilities.
//!
//! Wraps the `LX.WAIT` (CUSTOM-1 funct3=000) instruction, which stalls the
//! pipeline for a precise number of clock cycles.
//!
//! # Example
//!
//! ```no_run
//! use pulsar::timing;
//!
//! // Wait 1000 cycles (e.g., for a debounce window at 50 MHz ≈ 20 µs).
//! timing::wait(1000);
//! ```

/// Stall the pipeline for exactly `cycles` clock cycles.
///
/// This is the only way to introduce a deterministic delay on the LX32K
/// without a software counter loop (which would be non-deterministic due to
/// instruction cache effects).
///
/// Total wall-clock impact: 1 decode cycle + `cycles` stall cycles.
/// Passing `0` is a hardware no-op.
///
/// Compiles to a single `lx.wait` instruction.
#[inline(always)]
pub fn wait(cycles: u32) {
    // SAFETY: lx.wait is a pure pipeline stall; no memory is touched.
    unsafe { crate::raw::lx_wait(cycles) }
}
