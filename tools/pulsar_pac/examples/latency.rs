//! latency.rs — End-to-end key-to-USB latency measurement fixture.
//!
//! Toggles GPIO[0] on every hardware rapid-trigger event so a logic analyser
//! or oscilloscope can measure the latency from key actuation to report DMA.
//!
//! Measurement procedure:
//!   1. Flash this firmware.
//!   2. Connect a probe to the GPIO[0] output pin.
//!   3. Press a key; rising edge = first cycle after hardware comparator fires.
//!   4. USB SOF capture on a second channel shows host-visible latency.
//!
//! The hardware rapid-trigger unit scans all 64 keys once per 64 clock cycles
//! (~1.28 µs at 50 MHz).  GPIO toggle happens within one bus cycle of the
//! event register read.

#![no_std]
#![no_main]

use pulsar::{dma, gpio, rapid_trigger};

const GPIO_KEY_ACTIVE: u32 = 1 << 0;

#[no_mangle]
pub extern "C" fn main() -> i32 {
    gpio::write(0);
    rapid_trigger::reset_state();

    let mut report = [0u8; 8];

    loop {
        if let Some(ev) = rapid_trigger::poll() {
            if ev.is_press {
                gpio::set(GPIO_KEY_ACTIVE);
                report[2] = 0x04u8.wrapping_add(ev.key % 26);
            } else {
                gpio::clear(GPIO_KEY_ACTIVE);
                report[2] = 0x00;
            }
            dma::report(&report);
        }
    }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {
        core::hint::spin_loop();
    }
}
