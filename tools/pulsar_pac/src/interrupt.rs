//! Interrupt controller PAC module.
//!
//! MMIO base: 0x4000_0700
//!
//! | Offset | Access | Register    | Description                     |
//! |--------|--------|-------------|---------------------------------|
//! | 0x00   | R/W    | irq_enable  | Bit N enables IRQ source N      |
//! | 0x04   | R/W    | irq_pending | Bit N pending; write-1 to clear |
//! | 0x08   | R      | irq_status  | irq_enable & irq_pending        |
//!
//! # IRQ sources
//! - Bit 0: USB SOF (1 kHz)
//! - Bit 1: DMA transfer complete
//! - Bits 2–7: reserved

use crate::raw::lx_wait;

const INTC_BASE: u32 = 0x4000_0700;

const OFF_ENABLE:  u32 = 0x00;
const OFF_PENDING: u32 = 0x04;
const OFF_STATUS:  u32 = 0x08;

/// IRQ source bit positions.
pub mod src {
    pub const USB_SOF:  u8 = 0;
    pub const DMA_DONE: u8 = 1;
}

#[inline(always)]
fn read(offset: u32) -> u32 {
    unsafe { core::ptr::read_volatile((INTC_BASE + offset) as *const u32) }
}

#[inline(always)]
fn write(offset: u32, val: u32) {
    unsafe { core::ptr::write_volatile((INTC_BASE + offset) as *mut u32, val) }
}

/// Enable one or more IRQ sources (bitmask of `src::*` bits).
#[inline(always)]
pub fn enable(mask: u8) {
    write(OFF_ENABLE, read(OFF_ENABLE) | mask as u32);
}

/// Disable one or more IRQ sources.
#[inline(always)]
pub fn disable(mask: u8) {
    write(OFF_ENABLE, read(OFF_ENABLE) & !(mask as u32));
}

/// Read the raw pending register.
#[inline(always)]
pub fn pending() -> u8 {
    read(OFF_PENDING) as u8
}

/// Clear pending bits (write-1-to-clear semantics).
#[inline(always)]
pub fn clear(mask: u8) {
    write(OFF_PENDING, mask as u32);
}

/// Read the masked status (enable & pending).
#[inline(always)]
pub fn status() -> u8 {
    read(OFF_STATUS) as u8
}

/// Enter WFI (Wait For Interrupt) — stalls the pipeline until any enabled IRQ fires.
///
/// Compiles to: `lx.wait rs1`  where rs1 holds 0xFFFF_FFFF (the WFI sentinel).
/// Returns immediately once `irq_out` asserts from the interrupt controller.
/// Call `status()` afterwards to identify the source.
#[inline(always)]
pub fn wait_for_interrupt() {
    unsafe { lx_wait(0xFFFF_FFFF) };
}
