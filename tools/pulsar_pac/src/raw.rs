//! Raw unsafe wrappers around the six LX32K custom instructions.
// LX32 is a 32-bit architecture with no sub-registers; the `asm_sub_register`
// warning is a false positive from the host (AArch64/x86-64) checker.
#![allow(asm_sub_register)]
//!
//! Each function compiles to **exactly one instruction** when targeting
//! `lx32-unknown-elf` with the custom LLVM backend.
//!
//! # Safety
//!
//! These functions emit inline assembly.  The hardware guarantees are:
//!
//! - `lx_sensor`, `lx_matrix`, `lx_delta`, `lx_chord` — pure reads from the
//!   sensor controller's double-buffered snapshot; never stall; never fault.
//! - `lx_wait` — stalls the pipeline for exactly `cycles` cycles; idempotent.
//! - `lx_report` — hands a pointer to the DMA engine; the pointer **must**
//!   point to a valid, 8-byte-aligned `[u8; 8]` buffer for the duration of
//!   the DMA transfer (~8 USB micro-frames).  Undefined behaviour if the
//!   buffer is freed or mutated before the transfer completes.
//!
//! Prefer the safe wrappers in [`crate::sensor`], [`crate::dma`], and
//! [`crate::timing`] unless you need direct hardware access.

// ──────────────────────────────────────────────────────────────────────────────
// CUSTOM-0: sensor subsystem
// ──────────────────────────────────────────────────────────────────────────────

/// Read a 16-bit Hall-effect sensor value, sign-extended to 32 bits.
///
/// Compiles to: `lx.sensor rd, rs1`
/// Latency: 1 cycle. Never stalls.
#[inline(always)]
pub unsafe fn lx_sensor(idx: u32) -> i32 {
    let result: i32;
    core::arch::asm!(
        "lx.sensor {rd}, {rs1}",
        rd  = out(reg) result,
        rs1 = in(reg)  idx,
        options(nomem, nostack, pure),
    );
    result
}

/// Return a pointer to the 64-entry sensor snapshot buffer (`u16[64]`).
///
/// The sensor controller uses double-buffering; the returned pointer always
/// refers to the fully-settled, non-updating buffer.
///
/// Compiles to: `lx.matrix rd, rs1`  (rs1 is ignored by hardware; pass 0)
/// Latency: 1 cycle. Never stalls.
#[inline(always)]
pub unsafe fn lx_matrix(col: u32) -> *const u16 {
    let result: u32;
    core::arch::asm!(
        "lx.matrix {rd}, {rs1}",
        rd  = out(reg) result,
        rs1 = in(reg)  col,
        options(nomem, nostack, pure),
    );
    result as *const u16
}

/// Compute the frame-to-frame velocity delta for sensor `key_idx`.
///
/// Returns `current_frame[key_idx] - previous_frame[key_idx]`, sign-extended
/// to 32 bits.  Positive = key moving down; negative = release.
///
/// Compiles to: `lx.delta rd, rs1`
/// Latency: 1 cycle. Never stalls.
#[inline(always)]
pub unsafe fn lx_delta(key_idx: u32) -> i32 {
    let result: i32;
    core::arch::asm!(
        "lx.delta {rd}, {rs1}",
        rd  = out(reg) result,
        rs1 = in(reg)  key_idx,
        options(nomem, nostack, pure),
    );
    result
}

/// Test whether all keys in `bitmask` are simultaneously active.
///
/// Returns `1` if the chord matches, `0` otherwise.  Bit N of `bitmask`
/// corresponds to key N (keys 0–31 are supported in v1 hardware).
///
/// Compiles to: `lx.chord rd, rs1`
/// Latency: 1 cycle. Never stalls.
#[inline(always)]
pub unsafe fn lx_chord(bitmask: u32) -> u32 {
    let result: u32;
    core::arch::asm!(
        "lx.chord {rd}, {rs1}",
        rd  = out(reg) result,
        rs1 = in(reg)  bitmask,
        options(nomem, nostack, pure),
    );
    result
}

// ──────────────────────────────────────────────────────────────────────────────
// CUSTOM-1: pipeline control and DMA
// ──────────────────────────────────────────────────────────────────────────────

/// Stall the pipeline for exactly `cycles` clock cycles.
///
/// Useful for sub-microsecond timing control (debounce windows, hardware
/// synchronisation).  Passing `0` is a hardware no-op.
///
/// Compiles to: `lx.wait rs1`  (rd is hardcoded to x0)
/// Latency: 1 decode cycle + `cycles` stall cycles.
#[inline(always)]
pub unsafe fn lx_wait(cycles: u32) {
    core::arch::asm!(
        "lx.wait {rs1}",
        rs1 = in(reg) cycles,
        options(nostack),
    );
}

/// Initiate a DMA transfer of the 8-byte HID report buffer.
///
/// The CPU returns immediately (1 cycle) and the DMA engine transfers the
/// report to the USB endpoint in the background.  If the DMA engine is still
/// busy with a previous transfer, the pipeline stalls until it is ready.
///
/// # Safety
///
/// `report_ptr` must point to a valid, 8-byte-aligned `[u8; 8]` buffer that
/// remains live (not freed, not mutated) for the duration of the DMA transfer.
///
/// Compiles to: `lx.report rs1`  (rd is hardcoded to x0)
/// Latency: 1 cycle (or stall if DMA busy).
#[inline(always)]
pub unsafe fn lx_report(report_ptr: *const u8) {
    core::arch::asm!(
        "lx.report {rs1}",
        rs1 = in(reg) report_ptr,
        options(nostack),
    );
}
