//! gpio — GPIO output register for latency measurement and general use.
//!
//! A single 32-bit write-only register at GPIO_BASE (0x4000_0600).
//! On FPGA, the 32 bits are routed to physical output pins.
//! In simulation, writes are absorbed by the RTL GPIO stub.
//!
//! # Example
//!
//! ```no_run
//! pulsar::gpio::set(1 << 0);    // assert pin 0
//! // do work ...
//! pulsar::gpio::clear(1 << 0);  // deassert pin 0
//! ```

const GPIO_BASE: u32 = 0x4000_0600;

#[inline(always)]
fn read() -> u32 {
    unsafe { core::ptr::read_volatile(GPIO_BASE as *const u32) }
}

#[inline(always)]
fn raw_write(val: u32) {
    unsafe { core::ptr::write_volatile(GPIO_BASE as *mut u32, val) }
}

/// Assert (set to 1) the GPIO bits indicated by `mask`.
#[inline(always)]
pub fn set(mask: u32) {
    raw_write(read() | mask);
}

/// Deassert (set to 0) the GPIO bits indicated by `mask`.
#[inline(always)]
pub fn clear(mask: u32) {
    raw_write(read() & !mask);
}

/// Invert the GPIO bits indicated by `mask`.
#[inline(always)]
pub fn toggle(mask: u32) {
    raw_write(read() ^ mask);
}

/// Write the entire 32-bit GPIO output word.
#[inline(always)]
pub fn write(val: u32) {
    raw_write(val);
}

/// Read back the current GPIO output word.
#[inline(always)]
pub fn read_out() -> u32 {
    read()
}
