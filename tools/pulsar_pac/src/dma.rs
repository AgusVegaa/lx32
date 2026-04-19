//! Safe interface to the PULSAR DMA engine (HID report transfer).
//!
//! Wraps the `LX.REPORT` (CUSTOM-1 funct3=001) instruction, which hands an
//! 8-byte HID report buffer to the DMA engine for transfer to the USB
//! endpoint.
//!
//! # Timing
//!
//! - If the DMA engine is idle: returns in 1 cycle, transfer proceeds in
//!   the background.
//! - If the DMA engine is busy (previous transfer in progress): the pipeline
//!   stalls until the engine is ready, then initiates the new transfer.
//!
//! # Example
//!
//! ```no_run
//! use pulsar::dma;
//!
//! let report: [u8; 8] = [0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00];
//! dma::report(&report);
//! ```

/// Initiate a DMA transfer of the 8-byte HID `report` buffer.
///
/// The CPU returns after at most a short stall (if the DMA is busy); the
/// actual USB transfer proceeds in hardware.  The caller does **not** need to
/// wait for the transfer to complete before modifying `report` — the DMA
/// engine latches the pointer atomically at call time.
///
/// # Note on buffer lifetime
///
/// The DMA engine holds a reference to the buffer's memory for the duration
/// of the transfer (~8 USB micro-frames at full speed).  In practice, a stack
/// buffer is safe here because `report` is a fixed-size `[u8; 8]` that lives
/// long enough — but callers operating at very high rates should use a static
/// double-buffer to avoid corruption.
///
/// Compiles to a single `lx.report` instruction.
#[inline(always)]
pub fn report(report: &[u8; 8]) {
    // SAFETY: `report` is a valid, well-aligned reference to an 8-byte buffer.
    // The hardware reads this memory asynchronously; Rust's borrow checker
    // ensures the slice is live for the duration of this call, which is
    // sufficient because the DMA engine latches the data within 1–2 cycles.
    unsafe { crate::raw::lx_report(report.as_ptr()) }
}
