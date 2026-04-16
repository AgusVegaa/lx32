/*
 * 09_custom_intrinsics.c — Smoke test for all six LX32K custom instructions.
 *
 * Exercises every PULSAR intrinsic through the typed C API in
 * lx32k_intrinsics.h.  Results are stored in volatile locals to prevent
 * dead-code elimination under -O0.
 *
 * With lx32k_intrinsics.h's always_inline wrappers, each call site below
 * compiles to exactly one custom instruction regardless of -O level.
 * Before always_inline, each call at -O0 generated ~12 instructions (frame
 * setup, store/reload round-trip, jal, frame teardown).
 *
 * Expected output (one instruction per intrinsic, -O1):
 *   lx.sensor  x10, x10   ; sensor 3
 *   lx.matrix  x10, x0    ; snapshot pointer (col=0 → x0)
 *   lx.delta   x10, x10   ; velocity for key 42
 *   lx.chord   x10, x10   ; chord bitmask 0b101010
 *   lx.wait    x10        ; 10-cycle stall
 *   lx.report  x10        ; DMA kick
 */

#include <stdint.h>
#include "../include/lx32k_intrinsics.h"

void test_pulsar_custom_isa(void)
{
    /* LX.SENSOR: read sensor 3, sign-extend to 32 bits. */
    volatile int32_t s = lx_sensor(3);

    /* LX.MATRIX: get pointer to the 64-entry snapshot array. */
    volatile uint16_t *m = lx_matrix(0);

    /* LX.DELTA: compute velocity for key 42 (current − previous frame). */
    volatile int32_t d = lx_delta(42);

    /* LX.CHORD: check if keys 1, 3, and 5 are all active (bitmask 0b101010). */
    volatile uint32_t c = lx_chord(0b101010);

    /* LX.WAIT: stall the pipeline for 10 cycles. */
    lx_wait(10);

    /* LX.REPORT: send the snapshot buffer as the current HID report. */
    lx_report((void *)m);

    /* Suppress unused-variable warnings. */
    (void)s;
    (void)d;
    (void)c;
}

/*
 * Large-constant smoke test — verifies lx_wait() with a cycle count that
 * exceeds the simm12 range (> 2047), exercising the LUI+ADDI materialization
 * path in normalizeIntrinsicRegOperand.
 *
 * Before the fix, passing any constant > 2047 to lx_wait() triggered a
 * report_fatal_error.
 */
void test_large_wait(void)
{
    lx_wait(5000);   /* 5000 > 2047: requires LUI + ADDI to materialize */
    lx_wait(4096);   /* 4096 = 0x1000: lo12 == 0, only LUI needed */
}
