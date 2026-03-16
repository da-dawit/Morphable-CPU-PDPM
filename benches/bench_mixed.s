# Benchmark 3: Mixed Workload (Bubble Sort)
# Realistic code with both branches and memory access
# Sorts 8 numbers in memory

    nop
    
    # Initialize array at mem[0..28] (8 words)
    li x1, 64
    sw x1, 0(x0)
    li x1, 25
    sw x1, 4(x0)
    li x1, 12
    sw x1, 8(x0)
    li x1, 22
    sw x1, 12(x0)
    li x1, 11
    sw x1, 16(x0)
    li x1, 99
    sw x1, 20(x0)
    li x1, 3
    sw x1, 24(x0)
    li x1, 45
    sw x1, 28(x0)
    
    # Bubble sort
    li x20, 8           # array size
    li x21, 0           # outer loop counter i

outer:
    li x22, 0           # inner loop counter j
    addi x23, x20, -1   # n-1
    sub x23, x23, x21   # n-1-i (inner loop limit)
    
inner:
    # Calculate addresses
    slli x24, x22, 2    # j * 4
    addi x25, x24, 4    # (j+1) * 4
    
    # Load arr[j] and arr[j+1]
    lw x1, 0(x24)       # x1 = arr[j]
    lw x2, 0(x25)       # x2 = arr[j+1]
    
    # Compare and swap if needed
    blt x1, x2, noswap  # if arr[j] < arr[j+1], no swap
    
    # Swap
    sw x2, 0(x24)       # arr[j] = arr[j+1]
    sw x1, 0(x25)       # arr[j+1] = arr[j]
    
noswap:
    addi x22, x22, 1    # j++
    blt x22, x23, inner # if j < n-1-i, continue inner
    
    addi x21, x21, 1    # i++
    addi x26, x20, -1   # n-1
    blt x21, x26, outer # if i < n-1, continue outer

    # Load first element to show result (should be 3, smallest)
    lw x30, 0(x0)
    # Load last element (should be 99, largest)
    lw x31, 28(x0)
    
halt:
    beq x0, x0, halt
