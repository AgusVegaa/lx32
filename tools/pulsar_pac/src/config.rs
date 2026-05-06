//! config.rs — Per-key configuration block in DRAM.
//!
//! Layout at DRAM_BASE (0x0001_0000):
//!   +0x000  MAGIC          u32   = 0x504C_5358 ("PLSX")
//!   +0x004  VERSION        u32   = 1
//!   +0x008  actuation[64]  u16   actuation delta per key (default 120)
//!   +0x088  reset[64]      u16   reset delta per key (default 80)
//!   +0x108  noise[64]      u16   noise floor per key (default 20)
//!   +0x188  layer[256]     u8    HID usage code per (layer, key) — 4 layers × 64 keys
//!   +0x288  END

/// Base address of the configuration block in DRAM.
pub const DRAM_BASE: u32 = 0x0001_0000;

const CONFIG_MAGIC: u32 = 0x504C_5358;

/// Per-key configuration block.
///
/// The layout is fixed at [`DRAM_BASE`] and must match the table in the
/// module-level documentation exactly.  Use [`config()`] / [`config_mut()`]
/// to obtain a reference rather than constructing this struct directly.
#[repr(C)]
pub struct Config {
    /// Magic marker — must equal `0x504C_5358` ("PLSX") for a valid config.
    pub magic: u32,
    /// Config format version (currently 1).
    pub version: u32,
    /// Per-key actuation delta (ADC counts).  Default: 120.
    pub actuation: [u16; 64],
    /// Per-key reset delta (ADC counts).  Default: 80.
    pub reset: [u16; 64],
    /// Per-key noise floor (ADC counts).  Default: 20.
    pub noise: [u16; 64],
    /// HID usage code table: `layer[layer_idx * 64 + key_idx]`.
    /// 4 layers × 64 keys = 256 bytes.
    pub layer: [u8; 256],
}

/// Return a shared reference to the [`Config`] block in DRAM.
///
/// # Safety
///
/// The caller must ensure that no mutable reference to the config block
/// exists at the same time (i.e. [`config_mut()`] must not be called
/// concurrently on bare-metal single-threaded firmware this is trivially
/// satisfied).
#[inline(always)]
pub unsafe fn config() -> &'static Config {
    &*(DRAM_BASE as *const Config)
}

/// Return a mutable reference to the [`Config`] block in DRAM.
///
/// # Safety
///
/// No other reference to the config block may exist while this reference
/// is live.
#[inline(always)]
pub unsafe fn config_mut() -> &'static mut Config {
    &mut *(DRAM_BASE as *mut Config)
}

/// Returns `true` if the MAGIC field equals `0x504C_5358` ("PLSX").
///
/// Use this to decide whether to call [`init_defaults()`] on first boot.
pub fn is_valid() -> bool {
    // SAFETY: We read a single u32 from a known, aligned DRAM address using
    // volatile semantics.  No mutable reference is created.
    let magic = unsafe { core::ptr::read_volatile(DRAM_BASE as *const u32) };
    magic == CONFIG_MAGIC
}

/// Write the default configuration into DRAM.
///
/// After this call [`is_valid()`] returns `true` and all per-key thresholds
/// are set to their hardware defaults.
///
/// # Layer mapping
///
/// Layer 0 (the only layer written) maps:
/// - Keys 0–55: HID usage `key_idx % 58 + 4`
/// - Keys 56–63: HID usage `0` (unassigned)
///
/// All other layers are zeroed.
///
/// # Safety
///
/// The caller must ensure no other code accesses the config block while
/// this function is running.
pub unsafe fn init_defaults() {
    let base = DRAM_BASE as *mut u32;

    // magic
    core::ptr::write_volatile(base, CONFIG_MAGIC);
    // version
    core::ptr::write_volatile(base.add(1), 1u32);

    // actuation[64] — 64 × u16 = 128 bytes = 32 u32 words starting at offset 8
    let actuation_base = (DRAM_BASE + 0x008) as *mut u16;
    let mut i = 0usize;
    while i < 64 {
        core::ptr::write_volatile(actuation_base.add(i), 120u16);
        i += 1;
    }

    // reset[64] — starting at offset 0x088
    let reset_base = (DRAM_BASE + 0x088) as *mut u16;
    let mut i = 0usize;
    while i < 64 {
        core::ptr::write_volatile(reset_base.add(i), 80u16);
        i += 1;
    }

    // noise[64] — starting at offset 0x108
    let noise_base = (DRAM_BASE + 0x108) as *mut u16;
    let mut i = 0usize;
    while i < 64 {
        core::ptr::write_volatile(noise_base.add(i), 20u16);
        i += 1;
    }

    // layer[256] — starting at offset 0x188
    let layer_base = (DRAM_BASE + 0x188) as *mut u8;

    // Zero all 256 entries first (layers 0–3, keys 0–63).
    let mut i = 0usize;
    while i < 256 {
        core::ptr::write_volatile(layer_base.add(i), 0u8);
        i += 1;
    }

    // Layer 0 identity mapping: keys 0..=55 → key_idx % 58 + 4; keys 56..63 → 0.
    let mut i = 0usize;
    while i < 56 {
        let usage = ((i % 58) + 4) as u8;
        core::ptr::write_volatile(layer_base.add(i), usage);
        i += 1;
    }
    // Keys 56–63 in layer 0 remain 0 (already written above).
}
