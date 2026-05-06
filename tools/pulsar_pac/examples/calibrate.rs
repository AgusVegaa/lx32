//! calibrate.rs — PULSAR firmware with ADC calibration + rapid-trigger scan.
//!
//! Boot sequence:
//!   1. Measure a 64-key ADC baseline (1 ms settle at 50 MHz).
//!   2. Validate plausibility — infinite spin on failure (hardware fault).
//!   3. Main loop: compute per-key signed deltas, build 6KRO HID report, DMA.

#![no_std]
#![no_main]

use pulsar::{calibration::Calibration, dma, sensor};

/// Actuation threshold: keys with delta > 120 ADC counts are considered pressed.
const ACTUATION_DELTA: i32 = 120;

/// Maximum simultaneous keys in the HID boot-protocol report (6KRO).
const MAX_KEYS: usize = 6;

/// Total number of Hall-effect sensors / keys.
const KEY_COUNT: usize = 64;

/// HID Usage ID base for the main alphanumeric block (USB HID keyboard page).
/// Usage 0x04 = 'A'.
const HID_KEY_BASE: u8 = 0x04;

#[no_mangle]
pub extern "C" fn main() -> i32 {
    // ── Step 1: calibrate ────────────────────────────────────────────────────
    // Settle for 50 000 cycles (≈ 1 ms at 50 MHz) then snapshot all 64 sensors.
    let calibration = Calibration::measure(50_000);

    // ── Step 2: plausibility check ───────────────────────────────────────────
    // If any baseline is outside 500–3000 ADC counts, something is wrong.
    // Spin forever — the host can detect the stall via a watchdog.
    if !calibration.is_plausible() {
        loop {
            core::hint::spin_loop();
        }
    }

    // ── Step 3: main scan loop ───────────────────────────────────────────────
    loop {
        let mut report_keys = [0u8; MAX_KEYS];
        let mut count = 0usize;

        let mut idx = 0usize;
        while idx < KEY_COUNT {
            let raw = sensor::read(idx as u32) as u16;
            let delta = calibration.apply(raw, idx);

            if delta > ACTUATION_DELTA && count < MAX_KEYS {
                // Simple linear mapping: key index → HID usage ID (wrapping).
                let usage = HID_KEY_BASE.wrapping_add((idx % 26) as u8);
                report_keys[count] = usage;
                count += 1;
            }

            idx += 1;
        }

        // Assemble 8-byte HID boot-protocol keyboard report.
        let report: [u8; 8] = [
            0x00,           // modifier byte (no modifiers)
            0x00,           // reserved
            report_keys[0],
            report_keys[1],
            report_keys[2],
            report_keys[3],
            report_keys[4],
            report_keys[5],
        ];

        dma::report(&report);
    }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {
        core::hint::spin_loop();
    }
}
