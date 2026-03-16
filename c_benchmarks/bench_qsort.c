/* Decision Tree — Maximum Branch Density
 * Simulates a classifier with unpredictable branch outcomes
 * Nearly every instruction is a comparison + branch
 * Target: branch rate > 30%, P3 winner
 */

volatile int inputs[16];
volatile int outputs[16];

void main(void) {
    int i;
    int class_a = 0, class_b = 0, class_c = 0, class_d = 0;
    
    /* Initialize with pseudo-random pattern */
    for (i = 0; i < 16; i++)
        inputs[i] = (i * 37 + 13) & 0x3F;
    
    /* Decision tree: 4 levels deep, 16 iterations */
    /* Each iteration has 4-8 unpredictable branches */
    for (i = 0; i < 16; i++) {
        int x = inputs[i];
        if (x > 32) {
            if (x > 48) {
                if (x > 56) { class_a++; }
                else { class_b++; }
            } else {
                if (x > 40) { class_c++; }
                else { class_d++; }
            }
        } else {
            if (x > 16) {
                if (x > 24) { class_d++; }
                else { class_a++; }
            } else {
                if (x > 8) { class_b++; }
                else { class_c++; }
            }
        }
    }
    
    /* Second pass with modified inputs — more branches */
    for (i = 0; i < 16; i++) {
        int x = inputs[i] ^ 0x1F;
        if (x > 32) {
            if (x > 48) {
                if (x > 56) { class_a++; }
                else { class_b++; }
            } else {
                if (x > 40) { class_c++; }
                else { class_d++; }
            }
        } else {
            if (x > 16) {
                if (x > 24) { class_d++; }
                else { class_a++; }
            } else {
                if (x > 8) { class_b++; }
                else { class_c++; }
            }
        }
    }
    
    /* Third pass */
    for (i = 0; i < 16; i++) {
        int x = inputs[i] ^ 0x2A;
        if (x > 32) {
            if (x > 48) {
                if (x > 56) { class_a++; }
                else { class_b++; }
            } else {
                if (x > 40) { class_c++; }
                else { class_d++; }
            }
        } else {
            if (x > 16) {
                if (x > 24) { class_d++; }
                else { class_a++; }
            } else {
                if (x > 8) { class_b++; }
                else { class_c++; }
            }
        }
    }
    
    outputs[0] = class_a; outputs[1] = class_b;
    outputs[2] = class_c; outputs[3] = class_d;
    
    asm volatile("mv a0, %0" : : "r"(class_a + class_b + class_c + class_d));
}
