/* Bare-metal startup for morphable CPU benchmarks */
/* Sets stack pointer, calls main(), writes halt sentinel to x31 */

.section .text.init
.global _start

_start:
    /* Set stack pointer to top of DMEM (address 0x3FC) */
    li sp, 0x3FC
    
    /* Clear x31 (halt register) */
    li x31, 0
    
    /* Call the benchmark main function */
    jal ra, main
    
    /* After main returns, write halt sentinel: x31 = 0xDEAD */
    /* Build 0xDEAD = 57005 using ADDI + SLLI (no LUI needed) */
    li x31, 222       /* x31 = 0xDE */
    slli x31, x31, 8  /* x31 = 0xDE00 */
    addi x31, x31, 173 /* x31 = 0xDEAD */
    
    /* Infinite loop (safety net) */
halt_loop:
    nop
    nop
    nop
    nop
    j halt_loop
