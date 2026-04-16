#include <stdint.h>
#include "../../../include/lx32k_intrinsics.h"

void test_complex_scan(void) {
    uint16_t *matrix   = lx_matrix(0);
    uint32_t  chord    = lx_chord(0b00000101);
    (void)chord;

    for (int i = 0; i < 64; i++) {
        int32_t velocity = lx_delta(i);
        if (matrix[i] > 2000 || velocity > 100) {
            lx_wait(2);
        }
    }

    lx_report((void *)matrix);
}

int main(void) {
    test_complex_scan();
    return 0;  /* expected: 0 */
}


