/* Load-Use Chain — Data Dependency Benchmark
 * Each load result feeds the next load's address
 * Heavy load-use stalls, tests forwarding
 * Target: P5 (handles stalls with forwarding)
 */

volatile int table[32];

void main(void) {
    int i;
    
    /* Build indirection table — each entry points to another */
    table[0] = 7; table[1] = 14; table[2] = 3; table[3] = 21;
    table[4] = 11; table[5] = 28; table[6] = 1; table[7] = 18;
    table[8] = 25; table[9] = 4; table[10] = 16; table[11] = 9;
    table[12] = 30; table[13] = 6; table[14] = 22; table[15] = 2;
    table[16] = 13; table[17] = 27; table[18] = 8; table[19] = 31;
    table[20] = 5; table[21] = 15; table[22] = 24; table[23] = 10;
    table[24] = 19; table[25] = 0; table[26] = 29; table[27] = 12;
    table[28] = 20; table[29] = 23; table[30] = 17; table[31] = 26;
    
    /* Chase pointers through table — each load depends on previous */
    int idx = 0;
    int sum = 0;
    for (i = 0; i < 64; i++) {
        idx = table[idx & 31];  /* load-use: idx from previous load */
        sum += idx;
    }
    
    /* Second chain from different start */
    idx = 15;
    for (i = 0; i < 64; i++) {
        idx = table[idx & 31];
        sum += idx;
    }
    
    asm volatile("mv a0, %0" : : "r"(sum));
}
