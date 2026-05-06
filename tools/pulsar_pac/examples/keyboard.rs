//! keyboard.rs — PULSAR firmware with rapid-trigger key processing.
//!
//! Key processing pipeline per frame:
//!   1. LX.DELTA per key — hardware-computed frame-to-frame velocity.
//!   2. Per-key state machine (rapid trigger) — tracks the actuation point and
//!      reset point in real time, not a fixed threshold.
//!   3. HID report assembly and LX.REPORT DMA.
//!
//! Rapid trigger removes the fixed actuation point: a key actuates as soon as
//! it moves down by ACTUATION_DELTA ADC counts from its local minimum, and
//! deactuates as soon as it moves up by RESET_DELTA ADC counts from its local
//! maximum (while actuated).  This enables sub-0.1mm effective travel while
//! still ignoring noise below the hysteresis window.

#![no_std]
#![no_main]

use pulsar::{dma, sensor, timing};

// ── Constants ──────────────────────────────────────────────────────────────

const KEY_COUNT: usize = 64;

/// Rapid trigger: a key actuates when its delta exceeds this value (pressing).
const ACTUATION_DELTA: i32 = 120;

/// Rapid trigger: a key deactuates when its delta falls below this (releasing).
const RESET_DELTA: i32 = 80;

/// Hysteresis guard: ignore direction reversals smaller than this many counts.
const NOISE_FLOOR: i32 = 20;

/// HID Usage ID base for the main alphanumeric block (USB HID keyboard page).
const HID_KEY_BASE: u8 = 0x04; // Usage 0x04 = 'A'

/// Maximum simultaneous keys reported (6KRO HID boot protocol).
const MAX_KEYS: usize = 6;

// ── Per-key state machine ──────────────────────────────────────────────────

#[derive(Copy, Clone, PartialEq)]
enum KeyState {
    /// Key is above its rest position — tracking local minimum.
    Idle,
    /// Key moved down by at least ACTUATION_DELTA — logically pressed.
    Actuated,
}

struct KeyTracker {
    state:     KeyState,
    local_min: i32,   // lowest sensor reading seen while Idle
    local_max: i32,   // highest sensor reading seen while Actuated
}

impl KeyTracker {
    const fn new() -> Self {
        KeyTracker {
            state:     KeyState::Idle,
            local_min: i32::MAX,
            local_max: i32::MIN,
        }
    }

    /// Feed the current raw sensor value and return whether the key is pressed.
    #[inline(always)]
    fn update(&mut self, val: i32) -> bool {
        match self.state {
            KeyState::Idle => {
                // Track the local minimum (lowest resting point).
                if val < self.local_min {
                    self.local_min = val;
                }
                // Actuate if the key has moved down by at least ACTUATION_DELTA
                // from the local minimum.
                if val - self.local_min >= ACTUATION_DELTA {
                    self.state     = KeyState::Actuated;
                    self.local_max = val;
                }
                false
            }
            KeyState::Actuated => {
                // Track the local maximum (highest pressed reading).
                if val > self.local_max {
                    self.local_max = val;
                }
                // Deactuate if the key has moved up by at least RESET_DELTA
                // from the local maximum — key is being released.
                if self.local_max - val >= RESET_DELTA {
                    self.state     = KeyState::Idle;
                    self.local_min = val;
                }
                true
            }
        }
    }
}

// ── Global key tracker array ───────────────────────────────────────────────
// Static allocation — no heap on bare metal.
static mut KEYS: [KeyTracker; KEY_COUNT] = {
    // Can't use `[KeyTracker::new(); N]` because KeyTracker isn't Copy.
    // Use a const block so the compiler zero-initialises each element.
    let mut arr: [KeyTracker; KEY_COUNT] = unsafe {
        // SAFETY: KeyTracker fields are all valid at their zero-bit pattern
        // (Idle = 0, i32::MAX/MIN are handled by update() on first call).
        core::mem::zeroed()
    };
    // Explicitly initialise each tracker to the correct sentinel values.
    let mut i = 0;
    while i < KEY_COUNT {
        arr[i] = KeyTracker::new();
        i += 1;
    }
    arr
};

// ── Entry point ────────────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn main() -> i32 {
    loop {
        scan_and_report();
    }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {
        core::hint::spin_loop();
    }
}

// ── Scan / rapid-trigger / report loop ────────────────────────────────────

#[inline(never)]
fn scan_and_report() {
    // SAFETY: single-threaded bare metal; no concurrent access.
    let keys = unsafe { &mut KEYS };

    // --- Step 1: read the full snapshot pointer once (1 lx.matrix instruction).
    // The snapshot is double-buffered; the returned pointer is always stable.
    let snapshot = sensor::snapshot();

    // --- Step 2: run rapid-trigger logic for every key.
    //
    // Collect up to MAX_KEYS actuated HID usage codes.
    let mut report_keys = [0u8; MAX_KEYS];
    let mut count = 0usize;

    for idx in 0..KEY_COUNT {
        // lx.delta returns the frame-to-frame velocity (signed, 16-bit in 32-bit).
        // Using the snapshot as a cross-check: sensor below noise floor means rest.
        let raw_val = snapshot[idx] as i32;

        if raw_val < NOISE_FLOOR {
            // Force-reset the tracker when the sensor reads near zero.
            if keys[idx].state == KeyState::Actuated {
                keys[idx].state     = KeyState::Idle;
                keys[idx].local_min = 0;
            }
            continue;
        }

        let pressed = keys[idx].update(raw_val);

        if pressed && count < MAX_KEYS {
            // Map key index to a HID Usage ID.
            // Keys 0–25: 'A'–'Z'.  Keys 26–63: wrap-around (demo mapping).
            let usage = HID_KEY_BASE.wrapping_add((idx % 26) as u8);
            report_keys[count] = usage;
            count += 1;
        }
    }

    // --- Step 3: assemble and send the 8-byte HID keyboard report.
    //
    // Format (HID boot-protocol keyboard report):
    //   [0] modifier byte (0x00 = no modifiers)
    //   [1] reserved
    //   [2..7] key usage IDs (up to 6 simultaneous keys; 0x00 = no key)
    let report: [u8; 8] = [
        0x00,
        0x00,
        report_keys[0],
        report_keys[1],
        report_keys[2],
        report_keys[3],
        report_keys[4],
        report_keys[5],
    ];

    // lx.report — hand the buffer to the DMA engine in 1 cycle.
    // The hardware stalls the pipeline if the previous transfer is still in
    // flight, so this is safe to call every frame.
    dma::report(&report);

    // Optional: wait a brief period to align the scan rate with the USB SOF.
    // At 50 MHz: 6250 cycles ≈ 125 µs = exactly one USB high-speed microframe.
    // Remove or reduce this once SOF-based wakeup is wired up.
    timing::wait(6_250);
}
