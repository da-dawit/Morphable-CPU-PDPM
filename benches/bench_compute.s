# Benchmark 4: Compute-Intensive (Independent Operations)
# Long chains of independent ALU operations - ideal for deep pipelines
# No branches in the main loop body, minimal data dependencies
#
# This benchmark computes multiple accumulators in parallel
# to maximize instruction-level parallelism (ILP) ~> probably good for P7?

    nop #initial
    
    # Initialize 8 independent accumulators
    li x1, 1        # acc1
    li x2, 2        # acc2
    li x3, 3        # acc3
    li x4, 4        # acc4
    li x5, 5        # acc5
    li x6, 6        # acc6
    li x7, 7        # acc7
    li x8, 8        # acc8
    
    # Initialize constants for computation
    li x9, 3        # multiplier (add 3x)
    li x10, 0       # loop counter
    li x11, 20      # loop limit (20 iterations)
    
loop:
    # 8 independent additions - no dependencies between them!
    # Each accumulator only depends on itself
    add x1, x1, x9      # acc1 += 3
    add x2, x2, x9      # acc2 += 3
    add x3, x3, x9      # acc3 += 3
    add x4, x4, x9      # acc4 += 3
    add x5, x5, x9      # acc5 += 3
    add x6, x6, x9      # acc6 += 3
    add x7, x7, x9      # acc7 += 3
    add x8, x8, x9      # acc8 += 3
    
    # More independent operations
    add x1, x1, x1      # acc1 *= 2
    add x2, x2, x2      # acc2 *= 2
    add x3, x3, x3      # acc3 *= 2
    add x4, x4, x4      # acc4 *= 2
    add x5, x5, x5      # acc5 *= 2
    add x6, x6, x6      # acc6 *= 2
    add x7, x7, x7      # acc7 *= 2
    add x8, x8, x8      # acc8 *= 2
    
    # Increment loop counter
    addi x10, x10, 1
    blt x10, x11, loop
    
    # Sum all accumulators into x31 for verification
    add x31, x1, x2
    add x31, x31, x3
    add x31, x31, x4
    add x31, x31, x5
    add x31, x31, x6
    add x31, x31, x7
    add x31, x31, x8

halt:
    beq x0, x0, halt