//! frame_budget.rs — One-frame scan-loop cycle budget measurement.
//!
//! Executes exactly one complete keyboard scan frame and exits cleanly so
//! the bench runner can report precise cycle counts.
//!
//! Frame pipeline:
//!   1. LX.SENSOR ×64 — read all Hall-effect sensors (1 cycle each)
//!   2. Per-key rapid-trigger state machine — track local min/max, detect
//!      actuation and deactuation events
//!   3. HID boot-protocol report assembly (6KRO)
//!   4. LX.REPORT — DMA the 8-byte report to the USB endpoint (1 cycle)
//!
//! No LX.WAIT at the end — this measures computation only, not idle time.
//!
//! # Budget reference (50 MHz clock)
//!
//!   USB microframe period : 125 µs  = 6 250 cycles
//!   This program's cycles : see bench output (should be well under 6 250)
//!
//! Sensor values in simulation:
//!   LX.SENSOR(idx < 8 ) → 1200   (above NOISE_FLOOR → exercises update())
//!   LX.SENSOR(idx ≥ 8 ) → 800+idx (also above NOISE_FLOOR)
//!   First-frame behaviour: local_min ← sensor_val; no key actuates
//!   (actuation requires val - local_min ≥ ACTUATION_DELTA = 120)

#![no_std]
#![no_main]

use pulsar::{dma, sensor};

// ── Constants ──────────────────────────────────────────────────────────────

const KEY_COUNT: usize = 64;

const ACTUATION_DELTA: i32 = 120;
const RESET_DELTA:     i32 = 80;
const NOISE_FLOOR:     i32 = 20;

const HID_KEY_BASE: u8  = 0x04;
const MAX_KEYS:     usize = 6;

// ── Rapid-trigger state machine ────────────────────────────────────────────

#[derive(Copy, Clone, PartialEq)]
enum KeyState {
    Idle,
    Actuated,
}

struct KeyTracker {
    state:     KeyState,
    local_min: i32,
    local_max: i32,
}

impl KeyTracker {
    const fn new() -> Self {
        KeyTracker {
            state:     KeyState::Idle,
            local_min: i32::MAX,
            local_max: i32::MIN,
        }
    }

    #[inline(always)]
    fn update(&mut self, val: i32) -> bool {
        match self.state {
            KeyState::Idle => {
                if val < self.local_min {
                    self.local_min = val;
                }
                if val - self.local_min >= ACTUATION_DELTA {
                    self.state     = KeyState::Actuated;
                    self.local_max = val;
                }
                false
            }
            KeyState::Actuated => {
                if val > self.local_max {
                    self.local_max = val;
                }
                if self.local_max - val >= RESET_DELTA {
                    self.state     = KeyState::Idle;
                    self.local_min = val;
                }
                true
            }
        }
    }
}

// ── Static allocation ──────────────────────────────────────────────────────

static mut KEYS: [KeyTracker; KEY_COUNT] = {
    let mut arr: [KeyTracker; KEY_COUNT] = unsafe { core::mem::zeroed() };
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
    scan_frame();
    0
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {
        core::hint::spin_loop();
    }
}

// ── Single scan frame ──────────────────────────────────────────────────────

#[inline(never)]
fn scan_frame() {
    // SAFETY: single-threaded bare metal; no concurrent access.
    let keys = core::ptr::addr_of_mut!(KEYS) as *mut KeyTracker;

    let mut report_keys = [0u8; MAX_KEYS];
    let mut count = 0usize;

    // Read all 64 sensors via LX.SENSOR (64 custom instructions).
    // Using per-key reads rather than snapshot() so each key contributes
    // one LX.SENSOR instruction to the dynamic instruction mix.
    for idx in 0..KEY_COUNT {
        let raw_val = sensor::read(idx as u32);

        if raw_val < NOISE_FLOOR {
            let key = unsafe { &mut *keys.add(idx) };
            if key.state == KeyState::Actuated {
                key.state     = KeyState::Idle;
                key.local_min = 0;
            }
            continue;
        }

        let pressed = unsafe { (&mut *keys.add(idx)).update(raw_val) };

        if pressed && count < MAX_KEYS {
            report_keys[count] = HID_KEY_BASE.wrapping_add((idx % 26) as u8);
            count += 1;
        }
    }

    // Assemble and DMA the 8-byte HID boot-protocol report.
    dma::report(&[
        0x00,
        0x00,
        report_keys[0],
        report_keys[1],
        report_keys[2],
        report_keys[3],
        report_keys[4],
        report_keys[5],
    ]);
}
