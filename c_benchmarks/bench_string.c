/* Branch Storm — pure assembly, dense unpredictable branches
 * Alternating taken/not-taken branches on changing data
 * Target: P3 (branch rate > 30%)
 */

void __attribute__((section(".text.init"))) _start(void) {
    asm volatile(
        "li sp, 0x3FC\n"
        "li t0, 0\n"       /* counter */
        "li t1, 37\n"      /* pseudo-random state */
        "li t2, 64\n"      /* loop limit */
        "li a0, 0\n"       /* accumulator */

        /* Main loop: each iteration has 6+ branches */
        "loop_start:\n"
        /* Update pseudo-random: t1 = (t1 * 13 + 7) & 0x3F */
        "slli a1, t1, 3\n"
        "add a1, a1, t1\n"
        "slli a2, t1, 2\n"
        "add t1, a1, a2\n"
        "addi t1, t1, 7\n"
        "andi t1, t1, 0x3F\n"

        /* Branch tree on t1 value — 4 levels deep */
        "li a3, 32\n"
        "bge t1, a3, above32\n"
        /* t1 < 32 */
        "li a3, 16\n"
        "bge t1, a3, range16_31\n"
        /* t1 < 16 */
        "li a3, 8\n"
        "bge t1, a3, range8_15\n"
        /* t1 < 8 */
        "addi a0, a0, 1\n"
        "j next_iter\n"
        "range8_15:\n"
        "addi a0, a0, 2\n"
        "j next_iter\n"
        "range16_31:\n"
        "li a3, 24\n"
        "bge t1, a3, range24_31\n"
        "addi a0, a0, 3\n"
        "j next_iter\n"
        "range24_31:\n"
        "addi a0, a0, 4\n"
        "j next_iter\n"

        "above32:\n"
        "li a3, 48\n"
        "bge t1, a3, range48_63\n"
        /* 32-47 */
        "li a3, 40\n"
        "bge t1, a3, range40_47\n"
        "addi a0, a0, 5\n"
        "j next_iter\n"
        "range40_47:\n"
        "addi a0, a0, 6\n"
        "j next_iter\n"
        "range48_63:\n"
        "li a3, 56\n"
        "bge t1, a3, range56_63\n"
        "addi a0, a0, 7\n"
        "j next_iter\n"
        "range56_63:\n"
        "addi a0, a0, 8\n"

        "next_iter:\n"
        "addi t0, t0, 1\n"
        "blt t0, t2, loop_start\n"

        /* Halt */
        "li x31, 222\n"
        "slli x31, x31, 8\n"
        "addi x31, x31, 173\n"
        "nop\n" "nop\n" "nop\n" "nop\n"
        "1: j 1b\n"
    );
}
