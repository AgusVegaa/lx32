//! calibration.rs — ADC baseline calibration for the 64 Hall-effect sensors.
//!
//! Records a per-key baseline reading at start-up and converts subsequent raw
//! ADC values into signed deltas relative to that baseline.  Everything is
//! stack-allocated — no heap is required.
//!
//! # Example
//!
//! ```no_run
//! use pulsar::calibration::Calibration;
//! use pulsar::sensor;
//!
//! // Settle for 50 000 cycles (≈ 1 ms at 50 MHz) then snapshot all sensors.
//! let cal = Calibration::measure(50_000);
//!
//! // Sanity-check — all ADC readings should be in the plausible range.
//! assert!(cal.is_plausible());
//!
//! // In the scan loop:
//! let raw = sensor::read(3) as u16;
//! let delta: i32 = cal.apply(raw, 3);
//! ```

/// Per-key ADC baseline readings captured at calibration time.
pub struct Calibration {
    /// Baseline ADC reading for each of the 64 keys.
    pub baseline: [u16; 64],
}

impl Calibration {
    /// Capture baseline readings for all 64 sensors.
    ///
    /// Waits `settle_cycles` cycles via [`crate::timing::wait`] to allow the
    /// Hall-effect sensors to reach their rest-position output voltage before
    /// sampling.
    ///
    /// At 50 MHz, `settle_cycles = 50_000` corresponds to ≈ 1 ms.
    pub fn measure(settle_cycles: u32) -> Calibration {
        crate::timing::wait(settle_cycles);

        let mut baseline = [0u16; 64];
        let mut idx = 0u32;
        while idx < 64 {
            baseline[idx as usize] = crate::sensor::read(idx) as u16;
            idx += 1;
        }

        Calibration { baseline }
    }

    /// Return the signed delta of `raw` above the stored baseline for `key_idx`.
    ///
    /// Positive values mean the key has moved below its rest position (pressed);
    /// negative values indicate noise or upward movement.
    #[inline(always)]
    pub fn apply(&self, raw: u16, key_idx: usize) -> i32 {
        raw as i32 - self.baseline[key_idx] as i32
    }

    /// Returns `true` if every baseline reading is in the range `500..=3000`.
    ///
    /// Values outside this range suggest a disconnected sensor, a stuck key,
    /// or a hardware fault.  Callers should spin or halt if this returns
    /// `false` rather than proceeding with a bogus calibration.
    pub fn is_plausible(&self) -> bool {
        let mut i = 0usize;
        while i < 64 {
            let v = self.baseline[i];
            if v < 500 || v > 3000 {
                return false;
            }
            i += 1;
        }
        true
    }
}
