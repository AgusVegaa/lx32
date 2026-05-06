//! oled.rs — SSD1306 OLED status display over bit-banged SPI.
//!
//! Renders a minimal 128×8-pixel status bar on a 128×32 OLED:
//!   Row 0–7:  number of active keys (large digit rendered from a 5×7 bitmap)
//!
//! Hardware wiring (OLED CTRL MMIO at 0x4000_0300):
//!   Word 0 (W):   bit[0] = SCLK, bit[1] = MOSI, bit[2] = DC, bit[3] = CS
//!   Word 1 (R/W): bit[0] = BUSY (transmit in progress, write stalls DMA)
//!
//! The OLED controller stub in the RTL provides the same MMIO map.  On real
//! hardware, replace the stub with a proper SPI state machine.

#![no_std]
#![no_main]

use pulsar::{dma, sensor, timing};

// ── MMIO base address ──────────────────────────────────────────────────────

const OLED_BASE: u32 = 0x4000_0300;

// ── SPI pin bit masks ──────────────────────────────────────────────────────

const PIN_SCLK: u32 = 1 << 0;
const PIN_MOSI: u32 = 1 << 1;
const PIN_DC:   u32 = 1 << 2;
const PIN_CS:   u32 = 1 << 3;

// ── SSD1306 commands ───────────────────────────────────────────────────────

const CMD_DISPLAY_ON:       u8 = 0xAF;
const CMD_DISPLAY_OFF:      u8 = 0xAE;
const CMD_SET_PAGE:         u8 = 0xB0;
const CMD_SET_COL_LOW:      u8 = 0x00;
const CMD_SET_COL_HIGH:     u8 = 0x10;
const CMD_CHARGE_PUMP_ON:   u8 = 0x8D;
const CMD_CHARGE_PUMP_SET:  u8 = 0x14;
const CMD_CONTRAST:         u8 = 0x81;
const CONTRAST_VALUE:       u8 = 0xCF;

// ── 5×7 bitmap font for digits 0–9 ────────────────────────────────────────
// Each digit is encoded as 5 bytes (columns), each byte a 7-row bitmask.

static FONT_5X7: [[u8; 5]; 10] = [
    [0x3E, 0x51, 0x49, 0x45, 0x3E], // 0
    [0x00, 0x42, 0x7F, 0x40, 0x00], // 1
    [0x42, 0x61, 0x51, 0x49, 0x46], // 2
    [0x21, 0x41, 0x45, 0x4B, 0x31], // 3
    [0x18, 0x14, 0x12, 0x7F, 0x10], // 4
    [0x27, 0x45, 0x45, 0x45, 0x39], // 5
    [0x3C, 0x4A, 0x49, 0x49, 0x30], // 6
    [0x01, 0x71, 0x09, 0x05, 0x03], // 7
    [0x36, 0x49, 0x49, 0x49, 0x36], // 8
    [0x06, 0x49, 0x49, 0x29, 0x1E], // 9
];

// ── MMIO helpers ──────────────────────────────────────────────────────────

#[inline(always)]
unsafe fn mmio_write(offset: u32, val: u32) {
    let ptr = (OLED_BASE + offset * 4) as *mut u32;
    core::ptr::write_volatile(ptr, val);
}

// Current GPIO state (drives MMIO word 0).
static mut GPIO: u32 = PIN_CS; // CS deasserted (high) initially

#[inline(always)]
unsafe fn gpio_set(bits: u32) {
    GPIO |= bits;
    mmio_write(0, GPIO);
}

#[inline(always)]
unsafe fn gpio_clear(bits: u32) {
    GPIO &= !bits;
    mmio_write(0, GPIO);
}

// ── Bit-bang SPI byte transfer ─────────────────────────────────────────────

unsafe fn spi_byte(byte: u8) {
    for bit in (0..8).rev() {
        if (byte >> bit) & 1 != 0 {
            gpio_set(PIN_MOSI);
        } else {
            gpio_clear(PIN_MOSI);
        }
        gpio_set(PIN_SCLK);
        timing::wait(2); // half-period ≈ 40 ns at 50 MHz
        gpio_clear(PIN_SCLK);
        timing::wait(2);
    }
}

// ── Send one command byte ──────────────────────────────────────────────────

unsafe fn send_cmd(cmd: u8) {
    gpio_clear(PIN_DC); // DC = 0 → command
    gpio_clear(PIN_CS); // CS asserted
    spi_byte(cmd);
    gpio_set(PIN_CS); // CS deasserted
}

// ── Send one data byte ────────────────────────────────────────────────────

unsafe fn send_data(byte: u8) {
    gpio_set(PIN_DC);   // DC = 1 → data
    gpio_clear(PIN_CS);
    spi_byte(byte);
    gpio_set(PIN_CS);
}

// ── SSD1306 initialisation sequence ───────────────────────────────────────

unsafe fn oled_init() {
    send_cmd(CMD_DISPLAY_OFF);
    send_cmd(CMD_CHARGE_PUMP_ON);
    send_cmd(CMD_CHARGE_PUMP_SET);
    send_cmd(CMD_CONTRAST);
    send_cmd(CONTRAST_VALUE);
    send_cmd(CMD_DISPLAY_ON);
}

// ── Write a digit to page 0, columns start_col..start_col+5 ──────────────

unsafe fn oled_draw_digit(digit: u8, start_col: u8) {
    let d = (digit % 10) as usize;
    send_cmd(CMD_SET_PAGE | 0); // page 0
    send_cmd(CMD_SET_COL_LOW  | (start_col & 0x0F));
    send_cmd(CMD_SET_COL_HIGH | ((start_col >> 4) & 0x0F));
    for col in 0..5usize {
        send_data(FONT_5X7[d][col]);
    }
    send_data(0x00); // 1-pixel gap between characters
}

// ── Count active keys from sensor snapshot ────────────────────────────────

fn count_active_keys(snapshot: &[u16]) -> u8 {
    const THRESHOLD: u16 = 1000;
    let mut count = 0u8;
    for &v in snapshot {
        if v > THRESHOLD {
            count += 1;
        }
    }
    count
}

// ── Entry point ────────────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn main() -> i32 {
    unsafe {
        oled_init();
    }
    loop {
        let snapshot = sensor::snapshot();
        let active = count_active_keys(snapshot);

        // Display tens and units digits.
        unsafe {
            oled_draw_digit(active / 10, 56);  // centre of 128-wide display
            oled_draw_digit(active % 10, 63);
        }

        // Build and send a minimal HID report.
        let report: [u8; 8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
        dma::report(&report);

        timing::wait(6_250); // 125 µs USB SOF alignment
    }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {
        core::hint::spin_loop();
    }
}
