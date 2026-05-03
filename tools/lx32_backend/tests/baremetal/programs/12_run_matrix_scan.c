#include <stdint.h>
#include "../../../include/lx32k_intrinsics.h"

int main(void) {
    uint16_t *matrix = lx_matrix(0);
    uint32_t chord = lx_chord(0b00000101);
    (void)chord;

    for (int i = 0; i < 64; i++) {
        int32_t velocity = lx_delta(i);
        if (matrix[i] > 2000 || velocity > 100) {
            lx_wait(2);
        }
    }

    lx_report((void *)matrix);
    return 0;
}


