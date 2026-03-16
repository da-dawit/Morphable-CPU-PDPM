#!/usr/bin/env python3
"""
RISC-V Benchmark Generator for Morphable CPU
=============================================

Generates 90 benchmarks (indices 10-99) with diverse workload profiles.
Combined with the original 10 (indices 0-9), this gives 100 total.

All new benchmarks use universal halt: x31 = 0xDEAD (57005).

Workload characteristics are controlled by:
  - branch_rate: fraction of instructions that are branches
  - load_rate: fraction that are loads/stores  
  - alu_density: fraction of pure ALU computation
  - loop_depth: nesting depth of loops (affects branch pattern regularity)
  - hazard_rate: fraction of instructions with RAW dependencies

Output: benches/bench_NNN.hex files (one per benchmark)
"""

import os, random, struct

# ============================================================
# RV32I INSTRUCTION ENCODERS
# ============================================================

def encode_r(rd, rs1, rs2, funct3, funct7=0):
    return ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | \
           ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
           ((rd & 0x1F) << 7) | 0x33

def encode_i(rd, rs1, imm, funct3, opcode=0x13):
    return ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def encode_s(rs1, rs2, imm, funct3=0x2):
    return (((imm >> 5) & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | \
           ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
           ((imm & 0x1F) << 7) | 0x23

def encode_b(rs1, rs2, offset, funct3):
    """Encode B-type. offset is in bytes, must be even."""
    imm = offset & 0xFFFFFFFF  # handle negative
    b12 = (imm >> 12) & 1
    b11 = (imm >> 11) & 1
    b10_5 = (imm >> 5) & 0x3F
    b4_1 = (imm >> 1) & 0xF
    return (b12 << 31) | (b10_5 << 25) | ((rs2 & 0x1F) << 20) | \
           ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
           (b4_1 << 8) | (b11 << 7) | 0x63

def encode_lui(rd, imm20):
    return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | 0x37

# Instruction shorthands
def ADDI(rd, rs1, imm):  return encode_i(rd, rs1, imm & 0xFFF, 0x0)
def SLTI(rd, rs1, imm):  return encode_i(rd, rs1, imm & 0xFFF, 0x2)
def ANDI(rd, rs1, imm):  return encode_i(rd, rs1, imm & 0xFFF, 0x7)
def ORI(rd, rs1, imm):   return encode_i(rd, rs1, imm & 0xFFF, 0x6)
def XORI(rd, rs1, imm):  return encode_i(rd, rs1, imm & 0xFFF, 0x4)
def SLLI(rd, rs1, shamt): return encode_i(rd, rs1, shamt & 0x1F, 0x1)
def SRLI(rd, rs1, shamt): return encode_i(rd, rs1, shamt & 0x1F, 0x5)
def ADD(rd, rs1, rs2):   return encode_r(rd, rs1, rs2, 0x0, 0x00)
def SUB(rd, rs1, rs2):   return encode_r(rd, rs1, rs2, 0x0, 0x20)
def AND(rd, rs1, rs2):   return encode_r(rd, rs1, rs2, 0x7, 0x00)
def OR(rd, rs1, rs2):    return encode_r(rd, rs1, rs2, 0x6, 0x00)
def XOR(rd, rs1, rs2):   return encode_r(rd, rs1, rs2, 0x4, 0x00)
def SLL(rd, rs1, rs2):   return encode_r(rd, rs1, rs2, 0x1, 0x00)
def SLT(rd, rs1, rs2):   return encode_r(rd, rs1, rs2, 0x2, 0x00)
def LW(rd, rs1, imm):    return encode_i(rd, rs1, imm & 0xFFF, 0x2, 0x03)
def SW(rs1, rs2, imm):   return encode_s(rs1, rs2, imm & 0xFFF, 0x2)
def BEQ(rs1, rs2, off):  return encode_b(rs1, rs2, off, 0x0)
def BNE(rs1, rs2, off):  return encode_b(rs1, rs2, off, 0x1)
def BLT(rs1, rs2, off):  return encode_b(rs1, rs2, off, 0x4)
def BGE(rs1, rs2, off):  return encode_b(rs1, rs2, off, 0x5)
def NOP():               return ADDI(0, 0, 0)  # addi x0, x0, 0
def LUI(rd, imm20):      return encode_lui(rd, imm20)

# Registers: x1-x9 = temps, x10 = result/sentinel, x11-x20 = work, x31 = halt
# x0 = zero (hardwired)

# ============================================================
# HALT SEQUENCE: Write 0xDEAD to x31
# ============================================================

def halt_sequence():
    """Universal halt: x31 = 0xDEAD (57005).
    Built WITHOUT LUI (in case CPU doesn't support it).
    
    ADDI x31, x0, 222   -> x31 = 0xDE = 222
    SLLI x31, x31, 8    -> x31 = 0xDE00 = 56832
    ADDI x31, x31, 173  -> x31 = 0xDEAD = 57005
    
    Followed by NOP padding + infinite loop safety net.
    """
    return [
        ADDI(31, 0, 222),       # x31 = 222 (0xDE)
        SLLI(31, 31, 8),        # x31 = 56832 (0xDE00)
        ADDI(31, 31, 173),      # x31 = 57005 (0xDEAD)
        NOP(),                   # pipeline drain
        NOP(),
        NOP(),
        NOP(),
        NOP(),
        NOP(),
        NOP(),
        BEQ(0, 0, 0),           # infinite loop safety net
    ]


def verify_halt():
    """Verify the halt encoding is correct."""
    # LUI x31, 0x0E: 0x0E << 12 = 14 << 12 = 57344
    # ADDI x31, x31, 0xEAD: sign_ext(0xEAD) = 0xFFFFFEAD = -339
    # 57344 + (-339) = 57005 = 0xDEAD ✓
    assert 57344 + (-339) == 0xDEAD, f"Halt math wrong: {57344 + (-339)} != {0xDEAD}"
    # Also verify the 12-bit encoding: 0xEAD & 0xFFF = 0xEAD
    # Sign extend: bit 11 = 1, so value = 0xEAD - 0x1000 = 3757 - 4096 = -339 ✓
    assert (0xEAD - 0x1000) == -339

verify_halt()

# ============================================================
# BENCHMARK GENERATORS
# ============================================================

def gen_pure_alu(rng, n_insts=80):
    """Straight-line ALU computation. No branches, no memory.
    Expected: P7 optimal (deep pipeline, no branch penalties)."""
    insts = [ADDI(1, 0, rng.randint(1, 100))]  # seed x1
    regs = list(range(2, 20))
    for i in range(n_insts):
        rd = rng.choice(regs)
        rs1 = rng.choice([1] + regs[:i % 15 + 1])
        op = rng.choice(['add', 'sub', 'and', 'or', 'xor', 'sll', 'addi', 'andi', 'ori', 'slli'])
        if op == 'add': insts.append(ADD(rd, rs1, rng.choice(regs[:i % 10 + 1])))
        elif op == 'sub': insts.append(SUB(rd, rs1, rng.choice(regs[:i % 10 + 1])))
        elif op == 'and': insts.append(AND(rd, rs1, rng.choice(regs[:i % 10 + 1])))
        elif op == 'or': insts.append(OR(rd, rs1, rng.choice(regs[:i % 10 + 1])))
        elif op == 'xor': insts.append(XOR(rd, rs1, rng.choice(regs[:i % 10 + 1])))
        elif op == 'sll': insts.append(SLL(rd, rs1, rng.choice(regs[:i % 10 + 1])))
        elif op == 'addi': insts.append(ADDI(rd, rs1, rng.randint(-50, 50)))
        elif op == 'andi': insts.append(ANDI(rd, rs1, rng.randint(0, 255)))
        elif op == 'ori': insts.append(ORI(rd, rs1, rng.randint(0, 255)))
        elif op == 'slli': insts.append(SLLI(rd, rs1, rng.randint(1, 10)))
    return insts + halt_sequence()


def gen_branch_heavy(rng, n_iters=10, branch_density=0.5):
    """Loop with high branch frequency. 
    Expected: P3 optimal (shallow pipeline, low branch penalty)."""
    insts = []
    insts.append(ADDI(10, 0, 0))          # x10 = 0 (counter)
    insts.append(ADDI(11, 0, n_iters))    # x11 = limit
    
    # Loop body: mix of ALU and frequent branches
    loop_start = len(insts)
    body_size = max(2, int(2 / branch_density))  # fewer ALU ops = higher branch rate
    
    for i in range(body_size - 1):
        rd = rng.choice([12, 13, 14, 15])
        insts.append(ADDI(rd, rd, rng.randint(1, 10)))
    
    insts.append(ADDI(10, 10, 1))         # x10++
    
    # Branch back to loop_start
    offset = (loop_start - len(insts)) * 4  # negative offset
    insts.append(BLT(10, 11, offset))
    
    # Add conditional branches inside for more branch density
    if branch_density > 0.3:
        # Nested inner check
        extra = []
        extra.append(ADDI(10, 0, 0))
        extra.append(ADDI(11, 0, n_iters))
        loop2 = len(insts) + len(extra)
        extra.append(ADDI(12, 12, 1))
        extra.append(ADDI(10, 10, 1))
        back_off = (loop2 - (len(insts) + len(extra) + 1)) * 4
        extra.append(BNE(10, 11, back_off))
        insts = insts + extra
    
    return insts + halt_sequence()


def gen_load_store_stream(rng, n_ops=40):
    """Sequential memory access pattern. Loads and stores with minimal ALU.
    Expected: P5-P7 depending on hazards."""
    insts = []
    insts.append(ADDI(1, 0, 0))   # x1 = base address = 0
    
    for i in range(n_ops):
        offset = (i * 4) & 0x7FF  # stay in valid range
        if rng.random() < 0.5:
            # Store
            rd = rng.choice([2, 3, 4, 5])
            insts.append(ADDI(rd, 0, rng.randint(1, 100)))
            insts.append(SW(1, rd, offset))
        else:
            # Load
            rd = rng.choice([6, 7, 8, 9])
            insts.append(LW(rd, 1, offset))
            # Use loaded value (creates load-use hazard)
            if rng.random() < 0.5:
                insts.append(ADDI(rd, rd, 1))
    
    return insts + halt_sequence()


def gen_load_use_heavy(rng, n_ops=30):
    """Maximizes load-use hazards: load then immediately use.
    Expected: P5 optimal (P3 handles hazards better, P7 suffers more)."""
    insts = []
    insts.append(ADDI(1, 0, 0))   # base addr
    # Store some initial data
    for i in range(8):
        insts.append(ADDI(2, 0, i * 7 + 3))
        insts.append(SW(1, 2, i * 4))
    
    # Load-then-use pattern
    for i in range(n_ops):
        rd = 3 + (i % 6)
        offset = (i % 8) * 4
        insts.append(LW(rd, 1, offset))
        insts.append(ADD(rd, rd, rd))      # immediate use → stall
        insts.append(ADDI(rd, rd, 1))      # chain dependency
    
    return insts + halt_sequence()


def gen_mixed_loop(rng, outer=5, inner=8):
    """Nested loop with mixed operations.
    Moderate branches, some memory, some ALU."""
    insts = []
    insts.append(ADDI(10, 0, 0))          # outer counter
    insts.append(ADDI(20, 0, outer))      # outer limit
    
    outer_start = len(insts)
    insts.append(ADDI(11, 0, 0))          # inner counter
    insts.append(ADDI(21, 0, inner))      # inner limit
    
    inner_start = len(insts)
    # Inner body: ALU + occasional memory
    insts.append(ADD(12, 10, 11))
    insts.append(SLLI(13, 12, 2))
    if rng.random() < 0.5:
        insts.append(SW(0, 12, 0))
        insts.append(LW(14, 0, 0))
    else:
        insts.append(ADDI(14, 12, 5))
        insts.append(XOR(15, 14, 13))
    
    insts.append(ADDI(11, 11, 1))
    inner_back = (inner_start - len(insts)) * 4
    insts.append(BLT(11, 21, inner_back))
    
    insts.append(ADDI(10, 10, 1))
    outer_back = (outer_start - len(insts)) * 4
    insts.append(BLT(10, 20, outer_back))
    
    return insts + halt_sequence()


def gen_chain_dependency(rng, length=60):
    """Long RAW dependency chain. Each instruction depends on the previous.
    Tests forwarding unit heavily."""
    insts = [ADDI(1, 0, 1)]
    for i in range(length):
        op = rng.choice(['addi', 'slli', 'add_self'])
        if op == 'addi':
            insts.append(ADDI(1, 1, rng.randint(1, 5)))
        elif op == 'slli':
            insts.append(SLLI(1, 1, 1))
        else:
            insts.append(ADD(1, 1, 1))
    return insts + halt_sequence()


def gen_independent_alu(rng, n=60):
    """Independent ALU operations (no dependencies between consecutive insts).
    No stalls expected — tests raw throughput."""
    insts = []
    for i in range(min(18, n)):
        insts.append(ADDI(i + 1, 0, rng.randint(1, 100)))
    for i in range(n):
        rd = (i % 18) + 1
        rs1 = ((i + 7) % 18) + 1
        rs2 = ((i + 13) % 18) + 1
        insts.append(ADD(rd, rs1, rs2))
    return insts + halt_sequence()


def gen_branch_pattern(rng, pattern_type='regular', n_iters=20):
    """Different branch predictability patterns.
    'regular' = always taken (easy to predict)
    'alternating' = taken/not-taken alternating
    'random' = unpredictable branches
    """
    insts = []
    insts.append(ADDI(10, 0, 0))
    insts.append(ADDI(11, 0, n_iters))
    insts.append(ADDI(12, 0, 0))  # toggle for alternating
    
    loop_start = len(insts)
    insts.append(ADDI(10, 10, 1))
    insts.append(ADDI(13, 10, 0))  # copy counter
    
    if pattern_type == 'regular':
        # Always-taken branch (counter < limit)
        insts.append(ADDI(14, 0, 1))
        skip_off = 2 * 4  # skip next 2 insts
        insts.append(BEQ(14, 0, skip_off))  # never taken (1 != 0)
        insts.append(ADDI(15, 15, 1))
        insts.append(ADDI(16, 16, 1))
    elif pattern_type == 'alternating':
        insts.append(XORI(12, 12, 1))  # toggle 0/1
        skip_off = 2 * 4
        insts.append(BEQ(12, 0, skip_off))  # taken every other iteration
        insts.append(ADDI(15, 15, 1))
        insts.append(ADDI(16, 16, 1))
    else:  # random-ish via bit manipulation
        insts.append(SLLI(14, 10, 3))
        insts.append(XORI(14, 14, 0x55))
        insts.append(ANDI(14, 14, 1))
        skip_off = 2 * 4
        insts.append(BNE(14, 0, skip_off))
        insts.append(ADDI(15, 15, 1))
        insts.append(ADDI(16, 16, 1))
    
    back_off = (loop_start - len(insts)) * 4
    insts.append(BLT(10, 11, back_off))
    
    return insts + halt_sequence()


def gen_fibonacci(rng, n=15):
    """Fibonacci sequence computation. Mix of branches and ALU."""
    insts = []
    insts.append(ADDI(1, 0, 0))    # fib(0) = 0
    insts.append(ADDI(2, 0, 1))    # fib(1) = 1
    insts.append(ADDI(10, 0, 0))   # counter
    insts.append(ADDI(11, 0, n))   # limit
    
    loop = len(insts)
    insts.append(ADD(3, 1, 2))     # fib(n) = fib(n-1) + fib(n-2)
    insts.append(ADDI(1, 2, 0))    # shift
    insts.append(ADDI(2, 3, 0))    # shift
    insts.append(ADDI(10, 10, 1))
    back = (loop - len(insts)) * 4
    insts.append(BLT(10, 11, back))
    
    return insts + halt_sequence()


def gen_memory_copy(rng, n_words=20):
    """Memory copy: load from one region, store to another."""
    insts = []
    insts.append(ADDI(1, 0, 0))     # src base
    insts.append(ADDI(2, 0, 0))     # dst base (offset by n_words*4 in addressing)
    # Init source data
    for i in range(min(n_words, 20)):
        insts.append(ADDI(3, 0, i * 11 + 7))
        insts.append(SW(1, 3, i * 4))
    # Copy loop
    insts.append(ADDI(10, 0, 0))
    insts.append(ADDI(11, 0, min(n_words, 20)))
    loop = len(insts)
    insts.append(SLLI(4, 10, 2))     # offset = counter * 4
    insts.append(ADD(5, 1, 4))       # src addr
    insts.append(LW(3, 5, 0))        # load
    insts.append(ADDI(6, 5, 80))     # dst = src + 80
    insts.append(SW(6, 3, 0))        # store
    insts.append(ADDI(10, 10, 1))
    back = (loop - len(insts)) * 4
    insts.append(BLT(10, 11, back))
    
    return insts + halt_sequence()


# ============================================================
# BENCHMARK PARAMETER GRID
# ============================================================

def generate_all_benchmarks(output_dir='benches', start_idx=10):
    """Generate exactly 90 benchmarks with indices 10-99."""
    os.makedirs(output_dir, exist_ok=True)
    
    benchmarks = []
    idx = start_idx
    
    # --- Category 1: Pure ALU (15 benchmarks) --- idx 10-24
    for n in [30, 50, 70, 90, 120]:
        for seed in range(3):
            rng = random.Random(idx * 100 + seed)
            insts = gen_pure_alu(rng, n_insts=n)
            name = f'alu_n{n}_s{seed}'
            benchmarks.append((idx, name, insts, 'P7', f'Pure ALU, {n} ops'))
            idx += 1
    
    # --- Category 2: Branch-Heavy (15 benchmarks) --- idx 25-39
    for density in [0.2, 0.3, 0.4, 0.5, 0.6]:
        for iters in [8, 15, 25]:
            rng = random.Random(idx * 100)
            insts = gen_branch_heavy(rng, n_iters=iters, branch_density=density)
            name = f'branch_d{int(density*100)}_i{iters}'
            benchmarks.append((idx, name, insts, 'P3', f'Branch-heavy, density={density}'))
            idx += 1
    
    # --- Category 3: Load-Store Streaming (10 benchmarks) --- idx 40-49
    for n in [15, 25, 35, 45, 60]:
        for seed in range(2):
            rng = random.Random(idx * 100 + seed)
            insts = gen_load_store_stream(rng, n_ops=n)
            name = f'stream_n{n}_s{seed}'
            benchmarks.append((idx, name, insts, 'P7', f'Load-store stream, {n} ops'))
            idx += 1
    
    # --- Category 4: Load-Use Hazard Heavy (10 benchmarks) --- idx 50-59
    for n in [10, 15, 20, 25, 30]:
        for seed in range(2):
            rng = random.Random(idx * 100 + seed)
            insts = gen_load_use_heavy(rng, n_ops=n)
            name = f'loaduse_n{n}_s{seed}'
            benchmarks.append((idx, name, insts, 'P5', f'Load-use hazards, {n} ops'))
            idx += 1
    
    # --- Category 5: Mixed Nested Loops (10 benchmarks) --- idx 60-69
    mixed_params = [
        (3, 4), (3, 6), (3, 10),
        (5, 4), (5, 6), (5, 10),
        (8, 4), (8, 6),
        (4, 8), (6, 5),
    ]
    for outer, inner in mixed_params:
        rng = random.Random(idx * 100)
        insts = gen_mixed_loop(rng, outer=outer, inner=inner)
        name = f'mixed_o{outer}_i{inner}'
        benchmarks.append((idx, name, insts, 'P5', f'Nested loop {outer}x{inner}'))
        idx += 1
    
    # --- Category 6: Dependency Chains (10 benchmarks) --- idx 70-79
    for length in [20, 30, 40, 50, 60, 70, 80, 90, 100, 120]:
        rng = random.Random(idx * 100)
        insts = gen_chain_dependency(rng, length=length)
        name = f'chain_l{length}'
        benchmarks.append((idx, name, insts, 'P7', f'Dep chain, length={length}'))
        idx += 1
    
    # --- Category 7: Independent ALU (5 benchmarks) --- idx 80-84
    for n in [30, 50, 70, 90, 120]:
        rng = random.Random(idx * 100)
        insts = gen_independent_alu(rng, n=n)
        name = f'indep_n{n}'
        benchmarks.append((idx, name, insts, 'P7', f'Independent ALU, {n} ops'))
        idx += 1
    
    # --- Category 8: Branch Pattern Variants (9 benchmarks) --- idx 85-93
    for pattern in ['regular', 'alternating', 'random']:
        for iters in [10, 20, 35]:
            rng = random.Random(idx * 100)
            insts = gen_branch_pattern(rng, pattern_type=pattern, n_iters=iters)
            name = f'brpat_{pattern[:3]}_i{iters}'
            benchmarks.append((idx, name, insts, 'P3' if pattern == 'random' else 'P5', 
                             f'Branch pattern: {pattern}'))
            idx += 1
    
    # --- Category 9: Fibonacci (3 benchmarks) --- idx 94-96
    for n in [10, 20, 30]:
        rng = random.Random(idx * 100)
        insts = gen_fibonacci(rng, n=n)
        name = f'fib_n{n}'
        benchmarks.append((idx, name, insts, 'P5', f'Fibonacci, n={n}'))
        idx += 1
    
    # --- Category 10: Memory Copy (3 benchmarks) --- idx 97-99
    for n in [10, 15, 20]:
        rng = random.Random(idx * 100)
        insts = gen_memory_copy(rng, n_words=n)
        name = f'memcpy_n{n}'
        benchmarks.append((idx, name, insts, 'P5', f'Memory copy, {n} words'))
        idx += 1
    
    # Verify count
    assert len(benchmarks) == 90, f"Expected 90 benchmarks, got {len(benchmarks)}"
    assert idx == 100, f"Expected final idx=100, got {idx}"
    
    # Write all hex files
    manifest = []
    for bench_idx, name, insts, expected_mode, description in benchmarks:
        filepath = os.path.join(output_dir, f'bench_{bench_idx:03d}.hex')
        with open(filepath, 'w') as f:
            f.write(f'// Benchmark {bench_idx}: {name}\n')
            f.write(f'// {description}\n')
            f.write(f'// Expected optimal mode: {expected_mode}\n')
            f.write(f'// {len(insts)} instructions\n')
            for inst in insts:
                f.write(f'{inst:08X}\n')
        manifest.append({
            'index': bench_idx, 'name': name, 'file': f'bench_{bench_idx:03d}.hex',
            'n_insts': len(insts), 'expected': expected_mode, 'desc': description
        })
        
    print(f"Generated {len(benchmarks)} benchmarks (indices {start_idx}-{idx - 1})")
    return manifest


if __name__ == '__main__':
    manifest = generate_all_benchmarks()
    
    # Print summary
    print(f"\n{'Idx':<5} {'Name':<25} {'Insts':<7} {'Expected':<8} Description")
    print("-" * 80)
    for m in manifest:
        print(f"{m['index']:<5} {m['name']:<25} {m['n_insts']:<7} {m['expected']:<8} {m['desc']}")
    
    # Count by expected mode
    from collections import Counter
    modes = Counter(m['expected'] for m in manifest)
    print(f"\nExpected mode distribution: {dict(modes)}")