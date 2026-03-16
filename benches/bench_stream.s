# Benchmark 5: Memory Streaming with Software Pipelining
# This benchmark is **predicted** (not sure tho) to favor deeper pipelines by:
# 1. Having multiple independent memory streams
# 2. Separating loads from their uses (software pipelining)
# 3. Minimizing branches (1 branch per 18 operations)
#
# The key: loads are issued early, and results are used later

    nop
    
    # Initialize array at mem[0..28] (8 words: 10, 20, 30, 40, 50, 60, 70, 80)
    li x1, 10
    sw x1, 0(x0)
    li x1, 20
    sw x1, 4(x0)
    li x1, 30
    sw x1, 8(x0)
    li x1, 40
    sw x1, 12(x0)
    li x1, 50
    sw x1, 16(x0)
    li x1, 60
    sw x1, 20(x0)
    li x1, 70
    sw x1, 24(x0)
    li x1, 80
    sw x1, 28(x0)
    
    # Initialize counters
    li x10, 0           # loop counter
    li x11, 30          # loop limit (30 iterations)
    li x31, 0           # accumulator for result
    
loop:
    # Software pipelined loads - issue all 8 loads first
    # By the time we use x1, the load has completed
    lw x1, 0(x0)        # load mem[0] = 10
    lw x2, 4(x0)        # load mem[1] = 20
    lw x3, 8(x0)        # load mem[2] = 30
    lw x4, 12(x0)       # load mem[3] = 40
    lw x5, 16(x0)       # load mem[4] = 50
    lw x6, 20(x0)       # load mem[5] = 60
    lw x7, 24(x0)       # load mem[6] = 70
    lw x8, 28(x0)       # load mem[7] = 80
    
    # Now accumulate - loads should be complete by now
    # Each add is independent (all add to x31)
    add x31, x31, x1    # x31 += 10
    add x31, x31, x2    # x31 += 20
    add x31, x31, x3    # x31 += 30
    add x31, x31, x4    # x31 += 40
    add x31, x31, x5    # x31 += 50
    add x31, x31, x6    # x31 += 60
    add x31, x31, x7    # x31 += 70
    add x31, x31, x8    # x31 += 80
    
    # Increment and branch (only 1 branch per 17 operations!)
    addi x10, x10, 1
    blt x10, x11, loop
    
    # Final result: x31 = (10+20+30+40+50+60+70+80) * 30 = 360 * 30 = 10800
    # x10 = 30

halt:
    beq x0, x0, halt