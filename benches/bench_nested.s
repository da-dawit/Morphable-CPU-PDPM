# Benchmark 7: Nested Short Loops
# Multiple nested loops with few iterations each - branch-heavy
# Simulates matrix-style nested iteration with small dimensions

    nop
    
    li x31, 0       # result accumulator
    li x10, 0       # outer counter i
    li x14, 8       # outer limit
    
outer:
    li x11, 0       # middle counter j
    li x15, 8       # middle limit
    
middle:
    li x12, 0       # inner counter k
    li x16, 4       # inner limit (very short!)
    
inner:
    # Simple computation
    add x1, x10, x11
    add x1, x1, x12
    add x31, x31, x1
    
    addi x12, x12, 1
    blt x12, x16, inner
    
    addi x11, x11, 1
    blt x11, x15, middle
    
    addi x10, x10, 1
    blt x10, x14, outer
    
    # x10 should be 8, x31 has accumulated sum

halt:
    beq x0, x0, halt
