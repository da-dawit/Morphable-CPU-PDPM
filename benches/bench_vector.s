# Benchmark 9: Vector Operations (Straight-line)
# Very long sequences of independent operations with minimal branches
# Simulates SIMD-style vectorized code - P7's sweet spot

    nop
    
    # Initialize 8 "vector elements"
    li x1, 1
    li x2, 2
    li x3, 3
    li x4, 4
    li x5, 5
    li x6, 6
    li x7, 7
    li x8, 8
    
    li x10, 0       # loop counter
    li x11, 25      # iterations
    
loop:
    # Vector add (8 independent ops)
    addi x1, x1, 1
    addi x2, x2, 1
    addi x3, x3, 1
    addi x4, x4, 1
    addi x5, x5, 1
    addi x6, x6, 1
    addi x7, x7, 1
    addi x8, x8, 1
    
    # Vector multiply by 2 (shift left)
    add x1, x1, x1
    add x2, x2, x2
    add x3, x3, x3
    add x4, x4, x4
    add x5, x5, x5
    add x6, x6, x6
    add x7, x7, x7
    add x8, x8, x8
    
    # Vector subtract (back to reasonable values)
    addi x1, x1, -3
    addi x2, x2, -3
    addi x3, x3, -3
    addi x4, x4, -3
    addi x5, x5, -3
    addi x6, x6, -3
    addi x7, x7, -3
    addi x8, x8, -3
    
    # Only ONE branch per 24 ALU operations!
    addi x10, x10, 1
    blt x10, x11, loop
    
    # Reduce to x31
    add x31, x1, x2
    add x31, x31, x3
    add x31, x31, x4
    add x31, x31, x5
    add x31, x31, x6
    add x31, x31, x7
    add x31, x31, x8
    
    # x10 = 25

halt:
    beq x0, x0, halt
