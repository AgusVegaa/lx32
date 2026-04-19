//! Safe interface to the PULSAR sensor subsystem.
//!
//! Wraps the four CUSTOM-0 instructions that read from the Hall-effect sensor
//! controller.  All operations are 1-cycle and never stall.
//!
//! # Example
//!
//! ```no_run
//! use pulsar::sensor;
//!
//! // Read raw Hall-effect sensor at index 3.
//! let value: i32 = sensor::read(3);
//!
//! // Check whether the sensor moved since the last frame.
//! let velocity: i32 = sensor::delta(3);
//!
//! // Test if keys 0, 2, and 5 are all pressed simultaneously.
//! let is_chord: bool = sensor::chord(0b00100101);
//!
//! // Access the full 64-key snapshot as a slice.
//! let snapshot: &[u16; 64] = sensor::snapshot();
//! ```

/// Read a 16-bit Hall-effect sensor value at `idx`, sign-extended to 32 bits.
///
/// `idx` must be in `[0, 63]`.  Out-of-range indices return unspecified values
/// (the hardware does not fault but the result is meaningless).
///
/// Compiles to a single `lx.sensor` instruction.
#[inline(always)]
pub fn read(idx: u32) -> i32 {
    // SAFETY: lx.sensor is a pure read; never stalls; never faults.
    unsafe { crate::raw::lx_sensor(idx) }
}

/// Compute the frame-to-frame velocity delta for sensor `idx`.
///
/// Returns `current_frame[idx] - previous_frame[idx]`.
/// Positive → key moving down; negative → key releasing.
///
/// Compiles to a single `lx.delta` instruction.
#[inline(always)]
pub fn delta(idx: u32) -> i32 {
    // SAFETY: lx.delta is a pure read; never stalls; never faults.
    unsafe { crate::raw::lx_delta(idx) }
}

/// Test whether all keys in `bitmask` are simultaneously active.
///
/// Returns `true` if every bit set in `bitmask` corresponds to an active key.
/// Bit N maps to key N (0–31 supported in v1 hardware).
///
/// Compiles to a single `lx.chord` instruction.
#[inline(always)]
pub fn chord(bitmask: u32) -> bool {
    // SAFETY: lx.chord is a pure read; never stalls; never faults.
    unsafe { crate::raw::lx_chord(bitmask) != 0 }
}

/// Return a reference to the complete 64-key sensor snapshot.
///
/// The sensor controller uses double-buffering; the reference always points to
/// the fully-settled, non-updating buffer.  The lifetime is `'static` because
/// the hardware buffer is a fixed MMIO region that exists for the lifetime of
/// the program.
///
/// Compiles to a single `lx.matrix` instruction.
#[inline(always)]
pub fn snapshot() -> &'static [u16; 64] {
    // SAFETY: lx.matrix returns a pointer to the sensor controller's internal
    // double-buffer, which is always valid and aligned.  The hardware guarantees
    // the buffer is fully settled (not being written) for the duration of the
    // read frame.
    unsafe {
        let ptr = crate::raw::lx_matrix(0);
        &*(ptr as *const [u16; 64])
    }
}
