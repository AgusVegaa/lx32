/* link_firmware.ld — Linker script for real PULSAR hardware.
 *
 * Memory map (from docs/lx32k/memory_map.md):
 *   IRAM  0x0000_0000  32 KiB  — firmware code (.text, .rodata)
 *   DRAM  0x0001_0000  64 KiB  — data + BSS + stack
 *
 * MMIO and sensor buffer symbols are provided for firmware reference;
 * they are not part of any section allocation.
 */

OUTPUT_ARCH(lx32)
ENTRY(_start)

MEMORY {
    iram (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
    dram (rwx) : ORIGIN = 0x00010000, LENGTH = 64K
}

/* ── MMIO symbols ──────────────────────────────────────────────────────── */
SENSOR_CTRL_BASE  = 0x40000000;
DMA_CTRL_BASE     = 0x40000100;
USB_CTRL_BASE     = 0x40000200;
OLED_CTRL_BASE    = 0x40000300;
TIMER_BASE        = 0x40000400;
SENSOR_DATA_BASE  = 0x50000000;

/* Per-key config block size (matches Config struct layout in pulsar_pac/src/config.rs):
 *   +0x000  magic      u32
 *   +0x004  version    u32
 *   +0x008  actuation  64 × u16  = 0x080
 *   +0x088  reset      64 × u16  = 0x080
 *   +0x108  noise      64 × u16  = 0x080
 *   +0x188  layer      256 × u8  = 0x100
 *   +0x288  END
 */
_config_block_size = 0x288;

SECTIONS {
    /* ── Code + read-only data → IRAM ─────────────────────────────────── */
    .text.startup ORIGIN(iram) : {
        . = ALIGN(4);
        KEEP(*(.text.startup))   /* _start must be at address 0 */
    } > iram

    .text : {
        . = ALIGN(4);
        *(.text .text.*)
    } > iram

    .rodata : {
        . = ALIGN(4);
        *(.rodata .rodata.*)
    } > iram

    _iram_end = .;

    /* ── Per-key config block (first 0x288 bytes of DRAM, fixed at 0x0001_0000) ─
     * This section reserves space so that .data/.bss never overlap the config
     * area.  The config block is initialised at runtime by pulsar_pac::config::
     * init_defaults(); it is not part of the ELF load image.
     */
    .config ORIGIN(dram) (NOLOAD) : {
        . = ALIGN(4);
        _config_start = .;
        KEEP(*(.config .config.*))
        . = _config_start + _config_block_size;
        _config_end = .;
    } > dram

    /* ── Initialized data → DRAM (loaded from IRAM image) ─────────────── */
    .data : AT(_iram_end) {
        . = ALIGN(4);
        _data_start = .;
        *(.data .data.*)
        _data_end = .;
    } > dram

    /* ── Zero-initialized data ─────────────────────────────────────────── */
    .bss : {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } > dram

    /* ── Stack (grows downward from the top of DRAM) ───────────────────── */
    . = ALIGN(16);
    _stack_top = ORIGIN(dram) + LENGTH(dram);
}
