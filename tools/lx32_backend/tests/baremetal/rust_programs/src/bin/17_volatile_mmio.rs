//! Volatile load/store test — models MMIO-style memory semantics.
//!
//! Expected exit code: 42.
#![no_std]
#![no_main]

#[no_mangle]
pub extern "C" fn main() -> i32 {
    unsafe {
        let mut mmio = [0u32; 4];
        let p = mmio.as_mut_ptr();
        core::ptr::write_volatile(p.add(0), 9);
        core::ptr::write_volatile(p.add(1), 33);
        let a = core::ptr::read_volatile(p.add(0));
        let b = core::ptr::read_volatile(p.add(1));
        (a + b) as i32
    }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
