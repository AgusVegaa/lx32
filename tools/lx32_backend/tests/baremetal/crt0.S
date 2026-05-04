.section .text.startup
.globl _start
.type _start, @function

.extern main

_start:

    lui     x2, 1

    la      x5, __bss_start
    la      x6, __bss_end
_bss_clear:
    beq     x5, x6, _bss_done
    sw      x0, 0(x5)
    addi    x5, x5, 4
    jal     x0, _bss_clear
_bss_done:

    jal     x1, main

    lui     x5, 0xFFFFF
    sw      x10, 4(x5)

_halt:
    jal     x0, _halt

.size _start, . - _start
