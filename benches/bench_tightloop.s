# Benchmark 6: Tight Branch Loop
# Many short branches in a tight loop - P3 excels due to low branch penalty
# This simulates control-flow heavy code like state machines

    nop
    
    li x10, 0       # counter
    li x11, 50      # limit
    li x1, 0        # accumulator
    
loop:
    # Alternating branch pattern - worst case for deep pipelines
    andi x2, x10, 1     # x2 = counter & 1
    beq x2, x0, even    # if even, jump
    
    # Odd path
    addi x1, x1, 1
    j next
    
even:
    # Even path
    addi x1, x1, 2
    
next:
    # Another branch
    andi x3, x10, 3     # x3 = counter & 3
    beq x3, x0, div4    # if divisible by 4
    j skip
    
div4:
    addi x1, x1, 10
    
skip:
    addi x10, x10, 1
    blt x10, x11, loop
    
    # Result in x1
    # x10 should be 50

halt:
    beq x0, x0, halt
