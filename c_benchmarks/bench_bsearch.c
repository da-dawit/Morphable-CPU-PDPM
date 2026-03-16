/* Branch Maze — Unpredictable State Machine
 * State transitions depend on data, creating unpredictable branches
 * Target: branch rate > 25%, P3 winner
 */

volatile int trace[32];

void main(void) {
    int state = 0;
    int counter = 0;
    int output = 0;
    int i;
    
    /* Run state machine for 128 transitions */
    for (i = 0; i < 128; i++) {
        int input = (i * 13 + state * 7) & 0xF;
        
        if (state == 0) {
            if (input > 8) { state = 1; output += 1; }
            else if (input > 4) { state = 2; output += 2; }
            else { state = 3; output += 3; }
        } else if (state == 1) {
            if (input > 10) { state = 0; output += 4; }
            else if (input > 6) { state = 3; output += 5; }
            else if (input > 2) { state = 2; output += 6; }
            else { state = 0; output += 7; }
        } else if (state == 2) {
            if (input > 12) { state = 3; output += 8; }
            else if (input > 7) { state = 1; output += 9; }
            else if (input > 3) { state = 0; output += 10; }
            else { state = 1; output += 11; }
        } else {
            if (input > 9) { state = 2; output += 12; }
            else if (input > 5) { state = 0; output += 13; }
            else { state = 1; output += 14; }
        }
        
        counter++;
        if (i < 32) trace[i] = state;
    }
    
    asm volatile("mv a0, %0" : : "r"(output + counter));
}
