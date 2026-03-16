/* Dhrystone-Style — Balanced Mixed Workload
 * Array processing + comparisons + arithmetic
 * Realistic mix of all operation types
 * Target: P5 (balanced)
 */

#define LOOPS 10

volatile int IntGlob;
volatile int Array1[16];
volatile int Array2[16];

void main(void) {
    int i, j;
    int result = 0;
    
    IntGlob = 3;
    for (i = 0; i < 16; i++) {
        Array1[i] = i * 2 + 1;
        Array2[i] = (i + 5) * 3;
    }
    
    for (j = 0; j < LOOPS; j++) {
        /* Array shift */
        for (i = 0; i < 15; i++)
            Array1[i] = Array1[i + 1] + 1;
        Array1[15] = Array1[0];
        
        /* Comparison + conditional swap */
        for (i = 0; i < 8; i++) {
            if (Array1[i] > Array1[i + 8]) {
                int t = Array1[i];
                Array1[i] = Array1[i + 8];
                Array1[i + 8] = t;
            }
        }
        
        IntGlob = (IntGlob + 1) & 0x7;
        result += Array1[3] + IntGlob;
    }
    
    asm volatile("mv a0, %0" : : "r"(result));
}
