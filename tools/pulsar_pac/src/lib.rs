//! `pulsar` — Peripheral Access Crate for the PULSAR LX32K keyboard processor.
//!
//! Safe, idiomatic Rust access to the six custom hardware instructions.
//! Each high-level function compiles to **exactly one machine instruction**
//! when targeting `lx32-unknown-none-elf`.
//!
//! # Modules
//!
//! | Module | Instructions | Purpose |
//! |--------|-------------|---------|
//! | [`sensor`] | `lx.sensor`, `lx.matrix`, `lx.delta`, `lx.chord` | Hall-effect sensor reads |
//! | [`dma`] | `lx.report` | USB HID report transfer |
//! | [`timing`] | `lx.wait` | Cycle-accurate pipeline stalls |
//! | [`raw`] | all six | Unsafe `asm!` primitives |
//!
//! Enable the `rt` feature for the Rust runtime (`_start` + panic handler),
//! which replaces `crt0.S` and makes Rust the full entry point.
//!
//! # Quick start
//!
//! ```no_run
//! let val = pulsar::sensor::read(3);
//! pulsar::timing::wait(500);
//! pulsar::dma::report(&[0x01, 0x00, val as u8, 0, 0, 0, 0, 0]);
//! ```

#![no_std]

pub mod dma;
pub mod raw;
pub mod sensor;
pub mod timing;

// Runtime: _start entry point + panic handler.
// Only compiled when the `rt` feature is enabled AND targeting LX32.
#[cfg(feature = "rt")]
pub mod runtime;
