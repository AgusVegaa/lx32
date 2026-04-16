OUTPUT_ARCH(lx32)
ENTRY(_start)

MEMORY {
    ram (rwx) : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS {
    /* Startup code at 0x0 (5 instructions = 0x14 bytes). */
    .text.startup ORIGIN(ram) : {
        . = ALIGN(4);
        KEEP(*(.text.startup))   /* keep _start from being optimized out */
    } > ram

    /*
     * crt0 occupies 5 instructions (0x00–0x13).  Place user .text
     * immediately after so the first instruction of main is reachable
     * by the R_RISCV_JAL relocation emitted for "jal ra, main".
     */
    .text ORIGIN(ram) + 0x14 : {
        *(.text .text.*)
    } > ram

    /* Read-only data */
    .rodata : {
        . = ALIGN(4);
        *(.rodata .rodata.*)
    } > ram

    /* Initialized data */
    .data : {
        . = ALIGN(4);
        *(.data .data.*)
    } > ram

    /* Zero-initialized data (BSS) */
    .bss : {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } > ram

    /* Stack */
    . = ALIGN(16);
    _stack_top = ORIGIN(ram) + LENGTH(ram);
}