# Benchmark: Load-Use Heavy
# Tests load-use hazards where P5 forwarding should help
# P5 can forward from MEM stage, P3 must stall

    nop
    
    # Store test values to memory
    li x1, 10
    sw x1, 0(x0)      # mem[0] = 10
    li x1, 20
    sw x1, 4(x0)      # mem[4] = 20
    li x1, 30
    sw x1, 8(x0)      # mem[8] = 30
    
    # Initialize
    li x10, 0         # accumulator
    li x11, 0         # loop counter
    li x12, 20        # loop limit
    
loop:
    # Load-use pattern 1: load then immediately use
    lw x1, 0(x0)      # load 10
    add x10, x10, x1  # USE x1 immediately (load-use hazard!)
    
    # Load-use pattern 2
    lw x2, 4(x0)      # load 20
    add x10, x10, x2  # USE x2 immediately (load-use hazard!)
    
    # Load-use pattern 3
    lw x3, 8(x0)      # load 30
    add x10, x10, x3  # USE x3 immediately (load-use hazard!)
    
    # Loop control
    addi x11, x11, 1  # counter++
    blt x11, x12, loop
    
    # x10 should be (10+20+30) * 20 = 1200
halt:
    beq x0, x0, halt