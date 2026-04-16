#include <stdint.h>

int main(void) {
    uint16_t *matrix = __builtin_lx_matrix(0);
    uint32_t chord = __builtin_lx_chord(0b00000101);
    (void)chord;

    for (int i = 0; i < 64; i++) {
        int32_t velocity = __builtin_lx_delta(i);
        if (matrix[i] > 2000 || velocity > 100) {
            __builtin_lx_wait(2);
        }
    }

    __builtin_lx_report((void *)matrix);
    return 0;
}



