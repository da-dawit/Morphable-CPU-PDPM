# Benchmark 4: ALU Intensive (Compute Heavy)
# Lots of arithmetic, minimal branches, no memory
# Both modes should perform similarly

    nop
    
    # Initialize
    li x1, 1
    li x2, 2
    li x3, 3
    li x10, 0           # loop counter
    li x11, 15          # iterations
    
loop:
    # Chain of ALU operations
    add x4, x1, x2      # x4 = x1 + x2
    add x5, x3, x4      # x5 = x3 + x4
    sub x6, x5, x1      # x6 = x5 - x1
    xor x7, x4, x5      # x7 = x4 ^ x5
    or  x8, x6, x7      # x8 = x6 | x7
    and x9, x8, x5      # x9 = x8 & x5
    sll x4, x9, x1      # x4 = x9 << x1
    srl x5, x4, x2      # x5 = x4 >> x2
    add x6, x4, x5      # x6 = x4 + x5
    sub x7, x6, x3      # x7 = x6 - x3
    
    # Update values for next iteration
    addi x1, x1, 1
    addi x2, x2, 1
    addi x3, x3, 1
    
    addi x10, x10, 1    # counter++
    blt x10, x11, loop  # loop
    
    # Final result in x7
    
halt:
    beq x0, x0, halt
