void __attribute__((section(".text.init"))) _start(void) {
    asm volatile(
        "li t0, 1\n" "li t1, 2\n" "li t2, 3\n" "li t3, 4\n"
        "li t4, 5\n" "li t5, 6\n" "li a0, 7\n" "li a1, 8\n"
        "add t0,t0,t1\n" "add t1,t1,t2\n" "add t2,t2,t3\n" "add t3,t3,t0\n"
        "xor t4,t4,t0\n" "xor t5,t5,t1\n" "xor a0,a0,t2\n" "xor a1,a1,t3\n"
        "sub t0,t0,t4\n" "sub t1,t1,t5\n" "sub t2,t2,a0\n" "sub t3,t3,a1\n"
        "andi t4,t0,0xFF\n" "andi t5,t1,0xFF\n" "andi a0,t2,0xFF\n" "andi a1,t3,0xFF\n"
        "add t0,t0,t4\n" "add t1,t1,t5\n" "add t2,t2,a0\n" "add t3,t3,a1\n"
        "xor t4,t4,t0\n" "xor t5,t5,t1\n" "xor a0,a0,t2\n" "xor a1,a1,t3\n"
        "sub t0,t0,t4\n" "sub t1,t1,t5\n" "sub t2,t2,a0\n" "sub t3,t3,a1\n"
        "andi t4,t0,0xFF\n" "andi t5,t1,0xFF\n" "andi a0,t2,0xFF\n" "andi a1,t3,0xFF\n"
        "add t0,t0,t4\n" "add t1,t1,t5\n" "add t2,t2,a0\n" "add t3,t3,a1\n"
        "xor t4,t4,t0\n" "xor t5,t5,t1\n" "xor a0,a0,t2\n" "xor a1,a1,t3\n"
        "sub t0,t0,t4\n" "sub t1,t1,t5\n" "sub t2,t2,a0\n" "sub t3,t3,a1\n"
        "andi t4,t0,0xFF\n" "andi t5,t1,0xFF\n" "andi a0,t2,0xFF\n" "andi a1,t3,0xFF\n"
        "add t0,t0,t4\n" "add t1,t1,t5\n" "add t2,t2,a0\n" "add t3,t3,a1\n"
        "xor t4,t4,t0\n" "xor t5,t5,t1\n" "xor a0,a0,t2\n" "xor a1,a1,t3\n"
        "sub t0,t0,t4\n" "sub t1,t1,t5\n" "sub t2,t2,a0\n" "sub t3,t3,a1\n"
        "andi t4,t0,0xFF\n" "andi t5,t1,0xFF\n" "andi a0,t2,0xFF\n" "andi a1,t3,0xFF\n"
        "li x31, 222\n" "slli x31,x31,8\n" "addi x31,x31,173\n"
        "nop\n" "nop\n" "nop\n" "nop\n" "1: j 1b\n"
    );
}
