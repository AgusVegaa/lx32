/*
 * lx32k_intrinsics.h — PULSAR LX32K Custom Instruction Interface
 *
 * Exposes all six LX32K custom instructions as static inline C functions.
 * Include this header in any baremetal firmware or test program that targets
 * the PULSAR keyboard processor.
 *
 * Encoding summary (see docs/lx32k/custom_isa.md for full specification):
 *
 *   LX.SENSOR  CUSTOM-0 funct3=000  Read a 16-bit Hall effect sensor value
 *   LX.MATRIX  CUSTOM-0 funct3=001  Get pointer to 64-key sensor snapshot
 *   LX.DELTA   CUSTOM-0 funct3=010  Compute frame-to-frame sensor delta
 *   LX.CHORD   CUSTOM-0 funct3=011  Check if a key-chord bitmask is active
 *   LX.WAIT    CUSTOM-1 funct3=000  Stall the pipeline for N cycles
 *   LX.REPORT  CUSTOM-1 funct3=001  Initiate DMA transfer of HID report
 *
 * All functions compile to a single instruction when targeting lx32-unknown-elf.
 * The __builtin_lx_* names are defined in the LX32 Clang frontend extension;
 * this header is a thin, self-documenting wrapper that enforces the correct
 * C-level types and provides API documentation in one place.
 *
 * Usage:
 *   #include "lx32k_intrinsics.h"
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef LX32K_INTRINSICS_H
#define LX32K_INTRINSICS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Force inlining at every optimization level, including -O0.
 *
 * Without this attribute the compiler treats `static inline` as advisory and
 * emits each wrapper as a real call frame at -O0, turning a single-cycle
 * custom instruction into a 12-instruction function call (frame setup,
 * store/reload round-trip, jal, frame teardown).  With always_inline the
 * wrappers disappear entirely at every opt level and the custom instruction
 * appears directly in the caller.
 */
#define LX_ALWAYS_INLINE __attribute__((always_inline)) static inline

/* -------------------------------------------------------------------------
 * 1. LX.SENSOR — Read Individual Hall Effect Sensor
 *
 * Reads the 16-bit signed value from the Hall effect sensor at the given
 * index and sign-extends it to 32 bits.  The sensor_controller guarantees a
 * valid, stable reading from its internal scan buffer; this instruction never
 * stalls.
 *
 * @param idx  Sensor index in [0, 63].
 * @return     Sign-extended 16-bit sensor value.
 * -------------------------------------------------------------------------*/
LX_ALWAYS_INLINE int32_t lx_sensor(uint32_t idx)
{
    return __builtin_lx_sensor(idx);
}

/* -------------------------------------------------------------------------
 * 2. LX.MATRIX — Get Sensor Snapshot Pointer
 *
 * Returns a pointer to the base of the 128-byte snapshot array that holds
 * the most recent complete reading of all 64 sensors (uint16_t[64]).  The
 * sensor_controller uses double-buffering; the returned pointer always refers
 * to the fully-settled, non-updating buffer.  This instruction never stalls.
 *
 * The `col` argument is reserved for instruction-format consistency and is
 * ignored by the hardware; pass 0.
 *
 * @param col  Unused (pass 0).
 * @return     Pointer to uint16_t sensor_snapshot[64].
 * -------------------------------------------------------------------------*/
LX_ALWAYS_INLINE uint16_t *lx_matrix(uint32_t col)
{
    return __builtin_lx_matrix(col);
}

/* -------------------------------------------------------------------------
 * 3. LX.DELTA — Compute Frame-to-Frame Key Velocity
 *
 * Computes current_frame[key_idx] - previous_frame[key_idx] inside the
 * sensor_controller and returns the signed 16-bit result sign-extended to
 * 32 bits.  A positive value indicates the key is moving downward; a
 * negative value indicates release.  This instruction never stalls.
 *
 * @param key_idx  Sensor index in [0, 63].
 * @return         Signed 16-bit velocity, sign-extended to 32 bits.
 * -------------------------------------------------------------------------*/
LX_ALWAYS_INLINE int32_t lx_delta(uint32_t key_idx)
{
    return __builtin_lx_delta(key_idx);
}

/* -------------------------------------------------------------------------
 * 4. LX.CHORD — Test Active Key Bitmask
 *
 * Tests whether every key whose bit is set in `bitmask` is currently active
 * (pressed).  The hardware compares `bitmask` against the live 32-bit key
 * state register in one cycle.  Returns 1 if all masked keys are active,
 * 0 otherwise.  This instruction never stalls.
 *
 * @param bitmask  32-bit mask; bit N corresponds to key N (keys 0–31).
 * @return         1 if the chord matches, 0 otherwise.
 * -------------------------------------------------------------------------*/
LX_ALWAYS_INLINE uint32_t lx_chord(uint32_t bitmask)
{
    return __builtin_lx_chord(bitmask);
}

/* -------------------------------------------------------------------------
 * 5. LX.WAIT — Precise Pipeline Stall
 *
 * Suspends instruction fetch for exactly `cycles` clock cycles.  Useful for
 * fine-grained timing control — e.g., debounce windows or hardware
 * synchronisation.  Passing 0 is a no-op.
 *
 * Total wall-clock impact: 1 decode cycle + `cycles` stall cycles.
 *
 * @param cycles  Number of pipeline stall cycles; any uint32_t value is valid.
 * -------------------------------------------------------------------------*/
LX_ALWAYS_INLINE void lx_wait(uint32_t cycles)
{
    __builtin_lx_wait(cycles);
}

/* -------------------------------------------------------------------------
 * 6. LX.REPORT — Initiate HID Report DMA Transfer
 *
 * Hands an 8-byte HID report buffer to the DMA engine for transfer to the
 * USB endpoint.  From the CPU's perspective this is a 1-cycle instruction;
 * the DMA transfer proceeds in the background.  If the DMA engine is still
 * busy with a previous transfer, the pipeline stalls until it is ready.
 *
 * @param report_ptr  Pointer to an 8-byte aligned HID report buffer.
 * -------------------------------------------------------------------------*/
LX_ALWAYS_INLINE void lx_report(const void *report_ptr)
{
    __builtin_lx_report(report_ptr);
}

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* LX32K_INTRINSICS_H */
