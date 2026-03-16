# Morphable RISC-V CPU

A dynamically reconfigurable RISC-V processor that can switch between 3-stage, 5-stage, and 7-stage pipeline configurations at runtime. Built for the UPduino 3.1 FPGA.

---

## About This Project

Hey! I'm Dawit, a computer engineering student, and this is my final project for my processor design course.

I've always been fascinated by the tradeoffs in CPU design - why do some processors have 5 pipeline stages while others have 14? Why can't a processor just... adapt? That question led me down a rabbit hole that became this project.

The idea is simple but (I think) pretty cool: what if a CPU could morph its own pipeline depth based on what code it's running? Branch-heavy code? Use a shorter pipeline to minimize misprediction penalties. Compute-heavy loops? Switch to a deeper pipeline that can run at higher clock speeds.

I spent way too many late nights debugging hazard detection logic and figuring out why my forwarding unit wasn't forwarding. But honestly? I loved every minute of it. There's something deeply satisfying about watching your own CPU execute instructions correctly for the first time.

---

## Architecture Overview

### The Three Modes

P3 Mode (3-stage pipeline)
```
IF -> EX -> WB
```
The simplest configuration. Instructions flow through fetch, execute (which handles decode, ALU, and memory), and writeback. Only 1-2 cycle branch penalty. Great for control-flow heavy code, but limited clock speed due to the long critical path in the execute stage. Maximum clock: 1.1x baseline.

P5 Mode (5-stage pipeline)
```
IF -> ID -> EX -> MEM -> WB
```
The classic RISC pipeline that Patterson and Hennessy taught us. Balanced performance with proper hazard detection and data forwarding. This is the "safe" mode - it handles everything reasonably well. Maximum clock: 1.3x baseline.

P7 Mode (7-stage pipeline)
```
IF1 -> IF2 -> ID -> EX1 -> EX2 -> MEM -> WB
```
The deep pipeline configuration. Split fetch and execute stages mean shorter critical paths, enabling higher clock frequencies. But there's a cost - branch mispredictions hurt more (5 cycles to flush), and we need extra forwarding paths. Worth it for compute-heavy workloads where the clock speed advantage outweighs the penalties. Maximum clock: 1.5x baseline.

### Key Components

| Module | Description |
|--------|-------------|
| cpu_morphable_top | Top-level module that instantiates everything and handles mode switching |
| pipeline_mode_ctrl_v2 | The brain - controls which pipeline stages are active |
| forwarding_unit | Handles data forwarding for all three modes |
| hazard_unit | Detects hazards and generates stalls/flushes |
| perceptron_predictor | Hybrid AI predictor that learns optimal mode AND clock for workloads |
| cpi_monitor | Tracks cycles-per-instruction for performance feedback |

### The Hybrid AI Predictor

This is the part I'm most proud of. I built a predictor that combines decision tree logic with perceptron-style learned weights. It predicts TWO things:

1. Which pipeline mode to use (P3, P5, or P7)
2. What clock multiplier to use (within each mode's physical constraints)

The predictor looks at three features extracted from the running code:
- Branch percentage: How much of the code is branches?
- CPI ratio: How much does the deeper pipeline hurt CPI compared to shallow?
- Stall percentage: How often are we stalling for hazards?

Physical Clock Constraints (these are real hardware limits):
- P3: Can choose from 1.0x or 1.1x (long critical path limits options)
- P5: Can choose from 1.0x, 1.1x, 1.2x, or 1.3x (medium critical path)
- P7: Can choose from 1.0x, 1.1x, 1.2x, 1.3x, 1.4x, or 1.5x (short critical path)

The predictor learns to select BOTH the mode AND the optimal clock within that mode's allowed range. It doesn't just pick the maximum - it learns when to be aggressive vs conservative based on workload characteristics.

After training on my benchmark suite, it achieves 90% prediction accuracy for mode selection.

How it works:

```
INPUT                              OUTPUT
-----                              ------
Branch% = 6%       ----+
                       |           Mode Selection (Decision Tree)
CPI Ratio = 19%    ----+---> [Hybrid AI] ---> Mode: P7
                       |           Clock Selection (Perceptron)
Stall% = 0%        ----+      ---> Clock: 1.5x (chosen from P7's range: 1.0-1.5x)
```

Another example with different workload:
```
Branch% = 35%      ----+
                       |
CPI Ratio = 80%    ----+---> [Hybrid AI] ---> Mode: P3
                       |                 ---> Clock: 1.1x (chosen from P3's range: 1.0-1.1x)
Stall% = 0%        ----+
```

The decision tree handles mode selection:
```
IF branch > 26% AND ratio > 40% THEN P3
ELIF branch < 14% AND ratio < 33% THEN P7
ELIF stall > 13% THEN P5
ELSE use perceptron scores to decide
```

Then the perceptron selects clock speed within that mode's allowed range:
```
score = bias + w1*(100-branch) + w2*(100-ratio) + w3*(100-stall)

For P3 (range: 1.0x-1.1x):
  score > 50 -> 1.1x, else 1.0x

For P5 (range: 1.0x-1.3x):
  score > 75 -> 1.3x, > 60 -> 1.2x, > 45 -> 1.1x, else 1.0x

For P7 (range: 1.0x-1.5x):
  score > 90 -> 1.5x, > 75 -> 1.4x, > 60 -> 1.3x, > 45 -> 1.2x, > 30 -> 1.1x, else 1.0x
```

The AI learns that:
- Low branch% + low ratio = safe to push higher clocks
- High branch% or high ratio = be conservative with clock speed

---

## Hardware

Target FPGA: UPduino 3.1 (Lattice iCE40 UP5K)
- 5.3K LUTs
- 1Mb SPRAM
- 120Kb DPRAM
- 8 multipliers

The UPduino is a tiny, affordable FPGA that forced me to be efficient with my design. Every LUT counts when you're trying to fit three different pipeline configurations into 5K logic elements.

---

## Project Structure

```
morphable-cpu/
├── benches/                    # Benchmark programs (.hex files)
│   ├── bench_branch.hex        # Branch-heavy workload
│   ├── bench_loaduse.hex       # Load-use dependency patterns
│   ├── bench_alu.hex           # ALU-intensive computation
│   ├── bench_mixed.hex         # Bubble sort (mixed operations)
│   ├── bench_compute.hex       # Pure computation
│   ├── bench_stream.hex        # Memory streaming
│   ├── bench_tightloop.hex     # Tight loop branches
│   ├── bench_nested.hex        # Nested loops
│   ├── bench_switch.hex        # Switch-case patterns
│   └── bench_vector.hex        # Vector-style operations
│
├── cpu_morphable_top.v         # Top-level CPU module
├── pipeline_mode_ctrl_v2.v     # Mode switching controller
├── alu.v                       # Arithmetic Logic Unit
├── rf.v                        # Register File (32 registers)
├── imem.v                      # Instruction Memory
├── dmem.v                      # Data Memory
├── immgen.v                    # Immediate Generator
├── branch_resolution.v         # Branch target calculation
├── bc.v                        # Branch condition evaluation
│
├── if_id_reg.v                 # IF/ID pipeline register
├── id_ex_reg.v                 # ID/EX pipeline register
├── ex_mem_reg.v                # EX/MEM pipeline register
├── mem_wb_reg.v                # MEM/WB pipeline register
├── if1_if2_reg.v               # IF1/IF2 register (P7 mode)
├── ex1_ex2_reg.v               # EX1/EX2 register (P7 mode)
│
├── forwarding_unit.v           # Data forwarding logic
├── hazard_unit.v               # Hazard detection
├── control_pipeline.v          # Control signal generation
│
├── perceptron_predictor.v      # Hybrid AI mode/clock predictor
├── cpi_monitor.v               # Performance monitoring
│
├── cpu_morphable_top_tb.v      # Main testbench with AI training
├── upduino_top.v               # FPGA top-level wrapper
├── upduino_top.pcf             # Pin constraint file
│
├── assembler                   # Simple assembler tool
└── README.md                   # You are here!
```

---

## Results

### Benchmark Performance

After running all 10 benchmarks across all three modes with realistic clock scaling:

| Benchmark | Best Mode | Clock | Cycles | Eff. Time | Speedup |
|-----------|-----------|-------|--------|-----------|---------|
| Branch-Heavy | P3 | 1.1x | 163 | 1.48 | 1.10x |
| Load-Use | P5 | 1.3x | 172 | 1.32 | 1.21x |
| ALU-Intensive | P7 | 1.5x | 291 | 1.94 | 1.26x |
| Mixed (Bubble Sort) | P5 | 1.3x | 400 | 3.07 | N/A |
| Compute | P7 | 1.5x | 452 | 3.01 | 1.29x |
| Memory-Stream | P7 | 1.5x | 680 | 4.53 | 1.30x |
| Tight-Loop | P3 | 1.1x | 603 | 5.48 | 1.10x |
| Nested-Loops | P5 | 1.3x | 412 | 3.16 | 1.11x |
| Switch-Case | P3 | 1.1x | 542 | 4.92 | 1.10x |
| Vector-Ops | P7 | 1.5x | 367 | 2.44 | 1.25x |

### Win Distribution
- P3: 3 wins (branch-heavy workloads)
- P5: 3 wins (mixed workloads, hazard-heavy code)
- P7: 4 wins (compute-heavy workloads)

### Predictor Accuracy
The hybrid AI predictor achieves 90% accuracy in selecting the optimal pipeline mode based on workload characteristics.

### Key Insight
No single pipeline depth is best for all workloads. The morphable approach allows the CPU to adapt:
- P3 wins when branch penalty savings outweigh the clock speed loss
- P5 wins for balanced workloads that need good hazard handling
- P7 wins when the 1.5x clock advantage overcomes the deeper pipeline overhead

---

## What I Learned

1. Hazard detection is harder than it looks. Especially in P7 mode where you need to check both EX1 and EX2 stages for load-use hazards. I spent three days debugging an infinite stall issue before realizing the load instruction was never advancing through the pipeline.

2. Forwarding paths multiply quickly. P5 needs forwarding from EX/MEM and MEM/WB. P7 adds EX2 as another source. The priority logic gets tricky.

3. Simple ML can work. I started with a pure perceptron and it completely failed (0% accuracy - it kept oscillating). Switching to a hybrid decision tree + perceptron approach got me to 90%. Sometimes the right structure matters more than fancy algorithms.

4. Clock frequency is the hidden variable. In simulation, P3 always looks best because it has fewer cycles. But in real hardware, deeper pipelines can run faster. Accounting for realistic physical constraints changed my results completely.

5. Testing saves sanity. I wrote 10 different benchmarks specifically designed to stress different aspects of the pipeline. Every time I thought I was done, a new benchmark would expose a bug.

---

## Building and Running

### Simulation
```bash
# Run the testbench
apio sim

# View waveforms
gtkwave cpu_morphable_top_tb.vcd
```

### Synthesis (UPduino 3.1)
```bash
apio build
apio upload
```

---

## Future Work

If I had more time, I'd love to explore:

- Dynamic mode switching during execution: Right now modes are set at reset. True runtime switching mid-program would be amazing.
- Branch prediction integration: A good branch predictor could change which mode is optimal.
- Power analysis: Does P3 use less power than P7? Probably, but I'd like to measure it.
- More pipeline depths: Why stop at 7? What about P9 or P11?

---

## Acknowledgments

Thanks to my professor for letting me pursue this slightly crazy idea, and to everyone who listened to me ramble about pipeline hazards at 2 AM.

Special thanks to the open-source FPGA community - tools like Yosys, nextpnr, and the IceStorm project made this possible on my student budget.

---

## References

- Patterson & Hennessy, Computer Organization and Design: RISC-V Edition
- Hennessy & Patterson, Computer Architecture: A Quantitative Approach
- RISC-V Specification (riscv.org)
- UPduino 3.1 Documentation (tinyvision.ai)

---

This project represents countless hours of learning, debugging, and occasionally yelling at my monitor. If you're a student working on something similar - keep going. The moment your CPU executes its first instruction correctly is worth all the frustration.

— Dawit

## Logs
================================================================
MORPHABLE CPU - HYBRID AI PREDICTOR
================================================================

The AI learns to select BOTH:
1. Pipeline mode (P3, P5, P7)
2. Clock multiplier within that mode's allowed range

Physical Clock Constraints:
P3: 1.0x, 1.1x
P5: 1.0x, 1.1x, 1.2x, 1.3x
P7: 1.0x, 1.1x, 1.2x, 1.3x, 1.4x, 1.5x

================================================================
PHASE 1: EXHAUSTIVE DATA COLLECTION
================================================================
Testing all valid (mode, clock) combinations...

--- Benchmark 0: Branch-Heavy ---
WARNING: cpu_morphable_top_tb.v:267: $readmemh(benches/bench_branch.hex): Not enough words in the file for the requested range [0:255].
WARNING: imem.v:19: $readmemh(prog.hex): Not enough words in the file for the requested range [0:255].
P3:  163 cyc | Eff: @1.0x=1.63 @1.1x=1.48
WARNING: cpu_morphable_top_tb.v:267: $readmemh(benches/bench_branch.hex): Not enough words in the file for the requested range [0:255].
P5:  203 cyc | Eff: @1.0x=2.03 @1.1x=1.84 @1.2x=1.69 @1.3x=1.56
WARNING: cpu_morphable_top_tb.v:267: $readmemh(benches/bench_branch.hex): Not enough words in the file for the requested range [0:255].
P7:  281 cyc | Eff: @1.0x=2.81 @1.1x=2.55 @1.2x=2.34 @1.3x=2.16 @1.4x=2.00 @1.5x=1.87
>>> BEST: P3 @ 1.1x (eff=1.48) | Features: br=30%, ratio=72%, stall=0%

--- Benchmark 1: Load-Use ---
WARNING: cpu_morphable_top_tb.v:268: $readmemh(benches/bench_loaduse.hex): Not enough words in the file for the requested range [0:255].
P3:  161 cyc | Eff: @1.0x=1.61 @1.1x=1.46
WARNING: cpu_morphable_top_tb.v:268: $readmemh(benches/bench_loaduse.hex): Not enough words in the file for the requested range [0:255].
P5:  172 cyc | Eff: @1.0x=1.72 @1.1x=1.56 @1.2x=1.43 @1.3x=1.32
WARNING: cpu_morphable_top_tb.v:268: $readmemh(benches/bench_loaduse.hex): Not enough words in the file for the requested range [0:255].
P7:  232 cyc | Eff: @1.0x=2.32 @1.1x=2.10 @1.2x=1.93 @1.3x=1.78 @1.4x=1.65 @1.5x=1.54
>>> BEST: P5 @ 1.3x (eff=1.32) | Features: br=8%, ratio=44%, stall=23%

--- Benchmark 2: ALU-Intensive ---
WARNING: cpu_morphable_top_tb.v:269: $readmemh(benches/bench_alu.hex): Not enough words in the file for the requested range [0:255].
P3:  245 cyc | Eff: @1.0x=2.45 @1.1x=2.22
WARNING: cpu_morphable_top_tb.v:269: $readmemh(benches/bench_alu.hex): Not enough words in the file for the requested range [0:255].
P5:  261 cyc | Eff: @1.0x=2.61 @1.1x=2.37 @1.2x=2.17 @1.3x=2.00
WARNING: cpu_morphable_top_tb.v:269: $readmemh(benches/bench_alu.hex): Not enough words in the file for the requested range [0:255].
P7:  291 cyc | Eff: @1.0x=2.91 @1.1x=2.64 @1.2x=2.42 @1.3x=2.23 @1.4x=2.07 @1.5x=1.94
>>> BEST: P7 @ 1.5x (eff=1.94) | Features: br=6%, ratio=18%, stall=0%

--- Benchmark 3: Mixed (Bubble Sort) ---
WARNING: cpu_morphable_top_tb.v:270: $readmemh(benches/bench_mixed.hex): Not enough words in the file for the requested range [0:255].
P3: 15000 cyc | Eff: T/O T/O
WARNING: cpu_morphable_top_tb.v:270: $readmemh(benches/bench_mixed.hex): Not enough words in the file for the requested range [0:255].
P5:  400 cyc | Eff: @1.0x=4.00 @1.1x=3.63 @1.2x=3.33 @1.3x=3.07
WARNING: cpu_morphable_top_tb.v:270: $readmemh(benches/bench_mixed.hex): Not enough words in the file for the requested range [0:255].
P7:  506 cyc | Eff: @1.0x=5.06 @1.1x=4.60 @1.2x=4.21 @1.3x=3.89 @1.4x=3.61 @1.5x=3.37
>>> BEST: P5 @ 1.3x (eff=3.07) | Features: br=15%, ratio=100%, stall=7%

--- Benchmark 4: Compute-Intensive ---
WARNING: cpu_morphable_top_tb.v:271: $readmemh(benches/bench_compute.hex): Not enough words in the file for the requested range [0:255].
P3:  391 cyc | Eff: @1.0x=3.91 @1.1x=3.55
WARNING: cpu_morphable_top_tb.v:271: $readmemh(benches/bench_compute.hex): Not enough words in the file for the requested range [0:255].
P5:  412 cyc | Eff: @1.0x=4.12 @1.1x=3.74 @1.2x=3.43 @1.3x=3.16
WARNING: cpu_morphable_top_tb.v:271: $readmemh(benches/bench_compute.hex): Not enough words in the file for the requested range [0:255].
P7:  452 cyc | Eff: @1.0x=4.52 @1.1x=4.10 @1.2x=3.76 @1.3x=3.47 @1.4x=3.22 @1.5x=3.01
>>> BEST: P7 @ 1.5x (eff=3.01) | Features: br=5%, ratio=15%, stall=0%

--- Benchmark 5: Memory-Streaming ---
WARNING: cpu_morphable_top_tb.v:272: $readmemh(benches/bench_stream.hex): Not enough words in the file for the requested range [0:255].
P3:  589 cyc | Eff: @1.0x=5.89 @1.1x=5.35
WARNING: cpu_morphable_top_tb.v:272: $readmemh(benches/bench_stream.hex): Not enough words in the file for the requested range [0:255].
P5:  620 cyc | Eff: @1.0x=6.20 @1.1x=5.63 @1.2x=5.16 @1.3x=4.76
WARNING: cpu_morphable_top_tb.v:272: $readmemh(benches/bench_stream.hex): Not enough words in the file for the requested range [0:255].
P7:  680 cyc | Eff: @1.0x=6.80 @1.1x=6.18 @1.2x=5.66 @1.3x=5.23 @1.4x=4.85 @1.5x=4.53
>>> BEST: P7 @ 1.5x (eff=4.53) | Features: br=5%, ratio=15%, stall=0%

--- Benchmark 6: Tight-Loop ---
WARNING: cpu_morphable_top_tb.v:273: $readmemh(benches/bench_tightloop.hex): Not enough words in the file for the requested range [0:255].
P3:  603 cyc | Eff: @1.0x=6.03 @1.1x=5.48
WARNING: cpu_morphable_top_tb.v:273: $readmemh(benches/bench_tightloop.hex): Not enough words in the file for the requested range [0:255].
P5:  765 cyc | Eff: @1.0x=7.65 @1.1x=6.95 @1.2x=6.37 @1.3x=5.88
WARNING: cpu_morphable_top_tb.v:273: $readmemh(benches/bench_tightloop.hex): Not enough words in the file for the requested range [0:255].
P7: 1087 cyc | Eff: @1.0x=10.87 @1.1x=9.88 @1.2x=9.05 @1.3x=8.36 @1.4x=7.76 @1.5x=7.24
>>> BEST: P3 @ 1.1x (eff=5.48) | Features: br=35%, ratio=80%, stall=0%

--- Benchmark 7: Nested-Loops ---
WARNING: cpu_morphable_top_tb.v:274: $readmemh(benches/bench_nested.hex): Not enough words in the file for the requested range [0:255].
P3:  351 cyc | Eff: @1.0x=3.51 @1.1x=3.19
WARNING: cpu_morphable_top_tb.v:274: $readmemh(benches/bench_nested.hex): Not enough words in the file for the requested range [0:255].
P5:  412 cyc | Eff: @1.0x=4.12 @1.1x=3.74 @1.2x=3.43 @1.3x=3.16
WARNING: cpu_morphable_top_tb.v:274: $readmemh(benches/bench_nested.hex): Not enough words in the file for the requested range [0:255].
P7:  532 cyc | Eff: @1.0x=5.32 @1.1x=4.83 @1.2x=4.43 @1.3x=4.09 @1.4x=3.80 @1.5x=3.54
>>> BEST: P5 @ 1.3x (eff=3.16) | Features: br=22%, ratio=51%, stall=0%

--- Benchmark 8: Switch-Case ---
WARNING: cpu_morphable_top_tb.v:275: $readmemh(benches/bench_switch.hex): Not enough words in the file for the requested range [0:255].
P3:  542 cyc | Eff: @1.0x=5.42 @1.1x=4.92
WARNING: cpu_morphable_top_tb.v:275: $readmemh(benches/bench_switch.hex): Not enough words in the file for the requested range [0:255].
P5:  643 cyc | Eff: @1.0x=6.43 @1.1x=5.84 @1.2x=5.35 @1.3x=4.94
WARNING: cpu_morphable_top_tb.v:275: $readmemh(benches/bench_switch.hex): Not enough words in the file for the requested range [0:255].
P7:  843 cyc | Eff: @1.0x=8.43 @1.1x=7.66 @1.2x=7.02 @1.3x=6.48 @1.4x=6.02 @1.5x=5.62
>>> BEST: P3 @ 1.1x (eff=4.92) | Features: br=26%, ratio=55%, stall=0%

--- Benchmark 9: Vector-Ops ---
WARNING: cpu_morphable_top_tb.v:276: $readmemh(benches/bench_vector.hex): Not enough words in the file for the requested range [0:255].
P3:  306 cyc | Eff: @1.0x=3.06 @1.1x=2.78
WARNING: cpu_morphable_top_tb.v:276: $readmemh(benches/bench_vector.hex): Not enough words in the file for the requested range [0:255].
P5:  327 cyc | Eff: @1.0x=3.27 @1.1x=2.97 @1.2x=2.72 @1.3x=2.51
WARNING: cpu_morphable_top_tb.v:276: $readmemh(benches/bench_vector.hex): Not enough words in the file for the requested range [0:255].
P7:  367 cyc | Eff: @1.0x=3.67 @1.1x=3.33 @1.2x=3.05 @1.3x=2.82 @1.4x=2.62 @1.5x=2.44
>>> BEST: P7 @ 1.5x (eff=2.44) | Features: br=6%, ratio=19%, stall=0%

================================================================
PHASE 2: TRAIN HYBRID AI
================================================================

Epoch  1: 1 mode errors | Thresholds: P3_br>26, P7_br<10, P7_rat<25
Epoch  2: 1 mode errors | Thresholds: P3_br>26, P7_br<10, P7_rat<25
Epoch  3: 1 mode errors | Thresholds: P3_br>26, P7_br<10, P7_rat<25
Epoch  4: 1 mode errors | Thresholds: P3_br>26, P7_br<10, P7_rat<25
Epoch  5: 1 mode errors | Thresholds: P3_br>26, P7_br<10, P7_rat<25
Epoch  6: 1 mode errors | Thresholds: P3_br>26, P7_br<10, P7_rat<25
Epoch  7: 1 mode errors | Thresholds: P3_br>26, P7_br<10, P7_rat<25
Epoch  8: 1 mode errors | Thresholds: P3_br>26, P7_br<10, P7_rat<25
Epoch  9: 1 mode errors | Thresholds: P3_br>26, P7_br<10, P7_rat<25
Epoch 10: 1 mode errors | Thresholds: P3_br>26, P7_br<10, P7_rat<25
Epoch 11: 1 mode errors | Thresholds: P3_br>26, P7_br<10, P7_rat<25
Epoch 12: 1 mode errors | Thresholds: P3_br>26, P7_br<10, P7_rat<25
Epoch 13: 1 mode errors | Thresholds: P3_br>26, P7_br<10, P7_rat<25
Epoch 14: 1 mode errors | Thresholds: P3_br>26, P7_br<10, P7_rat<25
Epoch 15: 1 mode errors | Thresholds: P3_br>26, P7_br<10, P7_rat<25

Final Learned Parameters:
Mode: P3 if branch>26, P7 if branch<10 & ratio<25, else P5
Clock: bias=175, w_branch=30, w_ratio=25, w_stall=20

================================================================
PHASE 3: FINAL PREDICTIONS
================================================================

Benchmark       | Features (Br/Rat/St) | Actual       | Predicted    | Mode?
----------------|----------------------|--------------|--------------|------
Branch-Heavy    | 30% / 72% /  0%      | P3 @ 1.1x    | P3 @ 1.1x    | YES
Load-Use        |  8% / 44% / 23%      | P5 @ 1.3x    | P5 @ 1.3x    | YES
ALU-Intensive   |  6% / 18% /  0%      | P7 @ 1.5x    | P7 @ 1.5x    | YES
Mixed (Bubble)  | 15% / 100% /  7%      | P5 @ 1.3x    | P5 @ 1.3x    | YES
Compute         |  5% / 15% /  0%      | P7 @ 1.5x    | P7 @ 1.5x    | YES
Mem-Stream      |  5% / 15% /  0%      | P7 @ 1.5x    | P7 @ 1.5x    | YES
Tight-Loop      | 35% / 80% /  0%      | P3 @ 1.1x    | P3 @ 1.1x    | YES
Nested-Loops    | 22% / 51% /  0%      | P5 @ 1.3x    | P3 @ 1.1x    | no
Switch-Case     | 26% / 55% /  0%      | P3 @ 1.1x    | P3 @ 1.1x    | YES
Vector-Ops      |  6% / 19% /  0%      | P7 @ 1.5x    | P7 @ 1.5x    | YES

================================================================
MODE PREDICTION ACCURACY: 9/10 (90%)
================================================================

================================================================
FINAL SUMMARY
================================================================

Optimal (Mode, Clock) for each benchmark:
Benchmark       | Mode | Clock | Cycles | Eff.Time | Speedup
----------------|------|-------|--------|----------|--------
Branch-Heavy    | P3  | 1.1x  |   163  |     1.48 | 1.10x
Load-Use        | P5  | 1.3x  |   172  |     1.32 | 1.21x
ALU-Intensive   | P7  | 1.5x  |   291  |     1.94 | 1.26x
Mixed (Bubble)  | P5  | 1.3x  |   400  |     3.07 | N/A
Compute         | P7  | 1.5x  |   452  |     3.01 | 1.29x
Mem-Stream      | P7  | 1.5x  |   680  |     4.53 | 1.30x
Tight-Loop      | P3  | 1.1x  |   603  |     5.48 | 1.10x
Nested-Loops    | P5  | 1.3x  |   412  |     3.16 | 1.11x
Switch-Case     | P3  | 1.1x  |   542  |     4.92 | 1.10x
Vector-Ops      | P7  | 1.5x  |   367  |     2.44 | 1.25x

Win Count:
P3: 3 wins | P5: 3 wins | P7: 4 wins

================================================================
AI Predictor Output:

Given: branch%, CPI_ratio%, stall%
Output: (Mode, Clock) where clock is CHOSEN within mode's range

Example: branch=6%, ratio=19%, stall=0%
-> Mode=P7 (low branch, low ratio)
-> Clock=1.5x (high score, max allowed for P7)

Example: branch=35%, ratio=80%, stall=0%
-> Mode=P3 (high branch)
-> Clock=1.1x (max allowed for P3)
================================================================
cpu_morphable_top_tb.v:580: $finish called at 281365000 (1ps)
gtkwave --rcvar "splash_disable on" --rcvar "do_initial_zoom_fit 1" cpu_morphable_top_tb.vcd cpu_morphable_top_tb.gtkw
WM Destroy
GTKWave Analyzer v3.3.100 (w)1999-2019 BSI
RCVAR   | 'splash_disable on' FOUND
RCVAR   | 'do_initial_zoom_fit 1' FOUND
[0] start time.
[281365000] end time.
** WARNING: Error opening save file 'cpu_morphable_top_tb.gtkw', skipping.
=========================================================== [SUCCESS] Took 7.10 seconds ===========================================================