OUTPUT_ARCH(lx32)
ENTRY(_start)

MEMORY {
    ram (rwx) : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS {
    /* Startup code at 0x0. */
    .text.startup ORIGIN(ram) : {
        . = ALIGN(4);
        KEEP(*(.text.startup))   /* keep _start from being optimized out */
    } > ram

    /* User code follows startup code immediately. */
    .text : {
        . = ALIGN(4);
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
