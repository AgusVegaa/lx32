//! keyboard.rs — complete PULSAR firmware example.
//!
//! Demonstrates the full scan-debounce-report loop in ~50 lines of safe Rust.
//! Every call to sensor/timing/dma compiles to exactly one LX32K instruction.
//!
//! Build:
//!   make build-firmware
//!
//! Binary size goal: < 256 bytes (comparable to the hand-written C equivalent).

#![no_std]
#![no_main] // _start is provided by pulsar::runtime (the `rt` feature)

use pulsar::{dma, sensor, timing};

// ── Constants ──────────────────────────────────────────────────────────────

/// Number of keys on the keyboard matrix.
const KEY_COUNT: u32 = 64;

/// Debounce window in cycles.
/// At 50 MHz: 2500 cycles ≈ 50 µs — enough to settle a mechanical switch.
const DEBOUNCE_CYCLES: u32 = 2_500;

/// Threshold: sensor delta above this value means a key is being pressed.
const PRESS_THRESHOLD: i32 = 200;

/// HID Usage ID base for alphanumeric keys (USB HID keyboard page).
const HID_KEY_BASE: u8 = 0x04; // 'A'

// ── Entry point ───────────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn main() -> i32 {
    loop {
        scan_and_report();
    }
}

// ── Scan loop ─────────────────────────────────────────────────────────────

#[inline(never)] // keep the loop body in its own symbol for easier disasm
fn scan_and_report() {
    // Sample the full 64-key snapshot in one shot.
    // lx.matrix returns a pointer to the settled double-buffer — no stall.
    let snapshot = sensor::snapshot();

    // Find the most-pressed key this frame.
    let mut best_key: Option<(u32, i32)> = None;
    for key in 0..KEY_COUNT {
        let delta = sensor::delta(key); // lx.delta — 1 cycle each
        if delta > PRESS_THRESHOLD {
            if best_key.map_or(true, |(_, d)| delta > d) {
                best_key = Some((key, delta));
            }
        }
    }

    let Some((key, _pressure)) = best_key else {
        return; // no key pressed — skip report and debounce
    };

    // Confirm the key is still active in the snapshot buffer.
    // snapshot[key] is the raw Hall-effect reading; > 0 means pressed.
    if snapshot[key as usize] == 0 {
        return;
    }

    // Debounce: wait before reporting so mechanical bounce settles.
    // lx.wait stalls the pipeline for exactly DEBOUNCE_CYCLES — not a loop.
    timing::wait(DEBOUNCE_CYCLES);

    // Re-check after debounce — discard if the key bounced off.
    if sensor::delta(key) <= 0 {
        return;
    }

    // Build an 8-byte USB HID keyboard report and send via DMA.
    // Format: [report_id, modifier, reserved, key1, key2, key3, key4, key5]
    let hid_usage = HID_KEY_BASE.wrapping_add((key % 26) as u8);
    let report: [u8; 8] = [0x01, 0x00, 0x00, hid_usage, 0x00, 0x00, 0x00, 0x00];

    // lx.report — hands the buffer to the DMA engine in 1 cycle.
    dma::report(&report);
}
