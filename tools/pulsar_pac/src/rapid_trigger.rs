//! rapid_trigger — Interface to the hardware rapid-trigger comparator.
//!
//! The hardware module (rtl/core/rapid_trigger.sv) scans all 64 keys
//! autonomously and fires press/release events without any firmware scan loop.
//!
//! # Usage
//!
//! ```no_run
//! if let Some(ev) = pulsar::rapid_trigger::poll() {
//!     if ev.is_press {
//!         // key ev.key was just actuated
//!     }
//! }
//! ```

const RT_CTRL_BASE: u32 = 0x4000_0500;

/// Hardware event as returned by [`poll`].
pub struct Event {
    /// Zero-based key index (0–63).
    pub key: u8,
    /// `true` for a press event, `false` for a release.
    pub is_press: bool,
}

/// Poll for a pending hardware rapid-trigger event.
///
/// Reading the event register clears the hardware valid bit on the next
/// clock edge, so this function is safe to call in a tight loop.
/// Returns `None` when no event is pending.
#[inline(always)]
pub fn poll() -> Option<Event> {
    let word = unsafe { core::ptr::read_volatile(RT_CTRL_BASE as *const u32) };
    if word >> 31 != 0 {
        Some(Event {
            key: ((word >> 2) & 0x3F) as u8,
            is_press: (word & 1) != 0,
        })
    } else {
        None
    }
}

/// Set the actuation threshold for `key` (ADC counts, default 120).
///
/// The hardware fires a PRESS event when the sensor rises by more than
/// `threshold` counts from its local minimum.
/// `key` must be in range 0–63; only bits [5:0] are used by the hardware.
#[inline(always)]
pub fn set_actuation(key: u8, threshold: u16) {
    let word = (((key & 0x3F) as u32) << 16) | (threshold as u32);
    unsafe { core::ptr::write_volatile((RT_CTRL_BASE + 0x04) as *mut u32, word) };
}

/// Set the reset threshold for `key` (ADC counts, default 80).
///
/// The hardware fires a RELEASE event when the sensor falls by more than
/// `threshold` counts from its local maximum while the key is pressed.
/// `key` must be in range 0–63; only bits [5:0] are used by the hardware.
#[inline(always)]
pub fn set_reset(key: u8, threshold: u16) {
    let word = (((key & 0x3F) as u32) << 16) | (threshold as u32);
    unsafe { core::ptr::write_volatile((RT_CTRL_BASE + 0x08) as *mut u32, word) };
}

/// Reset all hardware key state (local min/max, pressed flags, pending event).
///
/// Call this after changing thresholds or at system init to start with a
/// clean slate.
#[inline(always)]
pub fn reset_state() {
    unsafe { core::ptr::write_volatile((RT_CTRL_BASE + 0x0C) as *mut u32, 1) };
}
