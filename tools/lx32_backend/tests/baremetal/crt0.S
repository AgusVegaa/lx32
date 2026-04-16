.section .text.startup
.globl _start
.type _start, @function

.extern main

_start:

    lui     x2, 1

    jal     x1, main

    lui     x5, 0xFFFFF
    sw      x10, 4(x5)

_halt:
    jal     x0, _halt

.size _start, . - _start
