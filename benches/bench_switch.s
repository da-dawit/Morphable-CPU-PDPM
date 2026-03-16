# Benchmark 8: Conditional Chain
# Series of dependent conditionals - like a switch statement
# Many branches with short basic blocks - P3's strength

    nop
    
    li x10, 0       # counter
    li x11, 40      # limit
    li x31, 0       # result
    
loop:
    # Get value mod 8
    andi x1, x10, 7
    
    # Chain of conditionals (like switch)
    li x2, 0
    beq x1, x2, case0
    li x2, 1
    beq x1, x2, case1
    li x2, 2
    beq x1, x2, case2
    li x2, 3
    beq x1, x2, case3
    li x2, 4
    beq x1, x2, case4
    li x2, 5
    beq x1, x2, case5
    li x2, 6
    beq x1, x2, case6
    j case7
    
case0:
    addi x31, x31, 1
    j endswitch
case1:
    addi x31, x31, 2
    j endswitch
case2:
    addi x31, x31, 3
    j endswitch
case3:
    addi x31, x31, 4
    j endswitch
case4:
    addi x31, x31, 5
    j endswitch
case5:
    addi x31, x31, 6
    j endswitch
case6:
    addi x31, x31, 7
    j endswitch
case7:
    addi x31, x31, 8
    
endswitch:
    addi x10, x10, 1
    blt x10, x11, loop
    
    # x10 = 40

halt:
    beq x0, x0, halt
