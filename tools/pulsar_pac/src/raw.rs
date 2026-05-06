//! Raw unsafe wrappers around the six LX32K custom instructions.
// On host (aarch64/x86-64), `reg` maps to 64-bit native registers and the
// host checker fires `asm_sub_register` on LX32 mnemonics that use 32-bit
// `w`/`e` sub-registers. LX32 is 32-bit-only, so there are no sub-registers;
// the warning is a false positive from the host toolchain.
#![allow(asm_sub_register)]
//!
//! Each function compiles to **exactly one instruction** when targeting
//! `lx32-unknown-none-elf` with the custom LLVM backend.
//!
//! Register allocation is now free: the compiler assigns `rd`/`rs1` to
//! whichever GPRs suit the surrounding code, eliminating the forced moves
//! that the earlier `"lx.sensor x10, x11"` pin-name syntax required.
//!
//! # Safety
//!
//! - `lx_sensor`, `lx_matrix`, `lx_delta`, `lx_chord` — pure reads from the
//!   sensor controller's double-buffered snapshot; never stall; never fault.
//! - `lx_wait` — stalls the pipeline for exactly `cycles` cycles; idempotent.
//! - `lx_report` — hands a pointer to the DMA engine; the pointer **must**
//!   point to a valid, 8-byte-aligned `[u8; 8]` buffer for the duration of
//!   the DMA transfer (~8 USB micro-frames).

// ──────────────────────────────────────────────────────────────────────────────
// CUSTOM-0: sensor subsystem
// ──────────────────────────────────────────────────────────────────────────────

/// Read a 16-bit Hall-effect sensor value, sign-extended to 32 bits.
///
/// Compiles to: `lx.sensor rd, rs1`
#[inline(always)]
pub unsafe fn lx_sensor(idx: u32) -> i32 {
    let result: i32;
    core::arch::asm!(
        "lx.sensor {rd}, {rs1}",
        rd  = lateout(reg) result,
        rs1 = in(reg) idx,
        options(nomem, nostack),
    );
    result
}

/// Return a pointer to the 64-entry sensor snapshot buffer (`*const u16`).
///
/// Compiles to: `lx.matrix rd, rs1`
#[inline(always)]
pub unsafe fn lx_matrix(col: u32) -> *const u16 {
    let result: u32;
    core::arch::asm!(
        "lx.matrix {rd}, {rs1}",
        rd  = lateout(reg) result,
        rs1 = in(reg) col,
        options(nomem, nostack),
    );
    result as *const u16
}

/// Compute the frame-to-frame velocity delta for sensor `key_idx`.
///
/// Compiles to: `lx.delta rd, rs1`
#[inline(always)]
pub unsafe fn lx_delta(key_idx: u32) -> i32 {
    let result: i32;
    core::arch::asm!(
        "lx.delta {rd}, {rs1}",
        rd  = lateout(reg) result,
        rs1 = in(reg) key_idx,
        options(nomem, nostack),
    );
    result
}

/// Test whether all keys in `bitmask` are simultaneously active.
///
/// Compiles to: `lx.chord rd, rs1`
#[inline(always)]
pub unsafe fn lx_chord(bitmask: u32) -> u32 {
    let result: u32;
    core::arch::asm!(
        "lx.chord {rd}, {rs1}",
        rd  = lateout(reg) result,
        rs1 = in(reg) bitmask,
        options(nomem, nostack),
    );
    result
}

// ──────────────────────────────────────────────────────────────────────────────
// CUSTOM-1: pipeline control and DMA
// ──────────────────────────────────────────────────────────────────────────────

/// Stall the pipeline for exactly `cycles` clock cycles.
///
/// Compiles to: `lx.wait rs1`
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
/// # Safety
///
/// `report_ptr` must point to a valid, 8-byte-aligned `[u8; 8]` buffer that
/// remains live for the duration of the DMA transfer.
///
/// Compiles to: `lx.report rs1`
#[inline(always)]
pub unsafe fn lx_report(report_ptr: *const u8) {
    core::arch::asm!(
        "lx.report {rs1}",
        rs1 = in(reg) report_ptr,
        options(nostack),
    );
}
