# Benchmark 1: Branch-Heavy Loop
# P3 should outperform P5 here (1-cycle vs 2-cycle branch penalty)
# Counts down from 20 to 0, then counts up to 20
# Many branches, few data dependencies

    nop
    
    # Initialize
    li x1, 20           # counter = 20
    li x2, 0            # zero reference
    li x3, 0            # result accumulator

countdown:
    addi x3, x3, 1      # result++
    addi x1, x1, -1     # counter--
    bne x1, x2, countdown   # if counter != 0, loop

    # Now count back up
    li x1, 0            # counter = 0
    li x4, 20           # target = 20

countup:
    addi x3, x3, 1      # result++
    addi x1, x1, 1      # counter++
    blt x1, x4, countup # if counter < 20, loop

    # x3 should be 40 (20 + 20 iterations)
    
halt:
    beq x0, x0, halt    # infinite loop (halt)
