void __attribute__((section(".text.init"))) _start(void) {
    asm volatile(
        "li t0, 0xA5\n" "li t1, 0x5A\n" "li t2, 0x12\n" "li t3, 0x56\n"
        "li t4, 0x78\n" "li t5, 0x9A\n" "li a0, 0xBC\n" "li a1, 0xDE\n"
        "slli a2,t1,1\n" "xor t0,t0,a2\n" "srli a2,t2,1\n" "xor t1,t1,a2\n"
        "slli a2,t3,2\n" "xor t2,t2,a2\n" "srli a2,t0,2\n" "xor t3,t3,a2\n"
        "add t0,t0,t3\n" "add t1,t1,t0\n" "add t2,t2,t1\n" "add t3,t3,t2\n"
        "slli a2,t5,1\n" "xor t4,t4,a2\n" "srli a2,a0,1\n" "xor t5,t5,a2\n"
        "slli a2,a1,2\n" "xor a0,a0,a2\n" "srli a2,t4,2\n" "xor a1,a1,a2\n"
        "add t4,t4,a1\n" "add t5,t5,t4\n" "add a0,a0,t5\n" "add a1,a1,a0\n"
        "slli a2,t1,3\n" "xor t0,t0,a2\n" "srli a2,t2,3\n" "xor t1,t1,a2\n"
        "slli a2,t3,1\n" "xor t2,t2,a2\n" "srli a2,t0,1\n" "xor t3,t3,a2\n"
        "sub t0,t0,t2\n" "sub t1,t1,t3\n" "sub t2,t2,t0\n" "sub t3,t3,t1\n"
        "slli a2,t5,3\n" "xor t4,t4,a2\n" "srli a2,a0,3\n" "xor t5,t5,a2\n"
        "slli a2,a1,1\n" "xor a0,a0,a2\n" "srli a2,t4,1\n" "xor a1,a1,a2\n"
        "sub t4,t4,a0\n" "sub t5,t5,a1\n" "sub a0,a0,t4\n" "sub a1,a1,t5\n"
        "add t0,t0,t4\n" "add t1,t1,t5\n" "add t2,t2,a0\n" "add t3,t3,a1\n"
        "xor t0,t0,t3\n" "xor t1,t1,t0\n" "xor t2,t2,t1\n" "xor t3,t3,t2\n"
        "li x31, 222\n" "slli x31,x31,8\n" "addi x31,x31,173\n"
        "nop\n" "nop\n" "nop\n" "nop\n" "1: j 1b\n"
    );
}
