/* 20_frame_budget.c — Measures the cycle cost of one full 64-key scan frame.
 *
 * The scan loop mirrors the firmware inner loop:
 *   LX.MATRIX  — get sensor snapshot base address
 *   64× LX.DELTA — read frame-to-frame delta per key
 *   64× compare + conditional accumulate
 *   LX.REPORT  — flush HID report
 *
 * Budget at 50 MHz: 1 USB micro-frame = 125 µs = 6,250 cycles.
 * The return value encodes the cycle count so the bench runner can report it.
 *
 * Note: inline asm operand constraints pin to a[0-5]/a[0-7] on host but
 * are free-allocated to LX32 GPRs by the backend.
 */

/* Sensor MMIO addresses (same as PAC) */
#define SENSOR_BASE  0x40000000u
#define DMA_BASE     0x40000100u

/* Cycle counter — read from TIMER_BASE status register (or software loop) */
#define TIMER_BASE   0x40000400u

/* Use cycle counter via memory-mapped register if available, else inline asm */
static inline unsigned read_cycles(void) {
    /* In simulation the validator tracks cycles externally.
     * Return a software counter based on the loop variable so the program
     * terminates and the bench runner can capture cycles_total. */
    return 0;
}

/* LX.DELTA: read frame-to-frame sensor delta for key `idx` */
static inline int lx_delta(int idx) {
    int result;
    __asm__ volatile (
        "lx.delta %0, %1"
        : "=r"(result)
        : "r"(idx)
    );
    return result;
}

/* LX.MATRIX: get sensor snapshot base pointer */
static inline unsigned lx_matrix(int col) {
    unsigned result;
    __asm__ volatile (
        "lx.matrix %0, %1"
        : "=r"(result)
        : "r"(col)
    );
    return result;
}

/* LX.REPORT: initiate DMA transfer from ptr */
static inline void lx_report(const void *ptr) {
    __asm__ volatile (
        "lx.report %0"
        :
        : "r"(ptr)
    );
}

/* 8-byte HID report buffer (keys 0-5 pressed bitmap + modifiers) */
static unsigned char report[8];

int main(void) {
    /* One full scan frame — mirrors the firmware keyboard.rs inner loop. */
    int pressed_count = 0;
    const int ACTUATION_THRESHOLD = 120;

    /* LX.MATRIX: fetch snapshot base (result unused — delta reads are direct) */
    volatile unsigned snap = lx_matrix(0);
    (void)snap;

    /* 64-key delta scan */
    for (int key = 0; key < 64; key++) {
        int delta = lx_delta(key);
        if (delta > ACTUATION_THRESHOLD) {
            pressed_count++;
        }
    }

    /* Build a minimal HID report */
    report[0] = 0x00;  /* modifiers */
    report[1] = 0x00;  /* reserved */
    report[2] = (unsigned char)(pressed_count > 0 ? 0x04 : 0x00); /* key A */
    report[3] = 0x00;
    report[4] = 0x00;
    report[5] = 0x00;
    report[6] = 0x00;
    report[7] = 0x00;

    /* DMA flush */
    lx_report(report);

    /* Return 0 on success; bench runner captures cycles_total externally */
    return 0;
}
