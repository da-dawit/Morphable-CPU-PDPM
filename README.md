# PDPM: Perceptron-Driven Pipeline Morphing for Adaptive RISC-V Processors

A dynamically reconfigurable RISC-V processor that morphs its pipeline between 3, 5, and 7 stages at runtime, guided by an online perceptron that jointly predicts optimal pipeline depth AND clock frequency. Built for the UPduino 3.1 FPGA (Lattice iCE40 UP5K).

**Paper:** *"PDPM: Perceptron-Driven Pipeline Morphing for Adaptive RISC-V Processors"* — Dawit Chun (Taejae University) and Han-seok Ko (The Catholic University of America)

---

## The Idea

A fixed-depth pipeline is always a compromise. Branch-heavy code wants a short pipeline (fewer wasted cycles on flushes). Compute-heavy code wants a deep pipeline running at maximum clock. What if the processor could learn which configuration is best — during execution, with no prior training?

PDPM does exactly this. It extends Jiménez and Lin's perceptron branch predictor (HPCA 2001) from predicting branch direction (binary) to predicting microarchitectural configuration (12-class: 3 pipeline depths × 4–6 clock speeds each). The result: **14× less wasted performance** compared to a fixed pipeline, for **under 1% hardware cost**.

---

## Key Results

| Metric | Value |
|--------|-------|
| Overhead vs. perfect oracle (online) | **0.560–3.698%** across 5 workload scenarios |
| Fixed P5@1.0× baseline waste | 34.253% (what PDPM eliminates) |
| Generalization (train 30, test 78 unseen) | **+0.003% overhead**, 97.436% config accuracy |
| Oracle performance captured | **99.997%** with 48 bytes of learned weights |
| UCB1 bandit on same unseen workloads | +45.035% overhead (vs PDPM's +0.003%) |
| PDPM+Phase on repeating workloads | **+0.560%** (near-oracle via instant phase recall) |
| Predictor hardware cost | <50 LUT4 cells (<1% of iCE40 UP5K) |
| Total design size | ~3,600 LUTs (68% utilization) |

---

## Architecture

### The Three Pipeline Modes

**P3 — 3-stage (branch-optimized)**
```
IF → EX → WB
```
1-cycle branch penalty. Max clock: 1.1× base. Wins when β > 25%.

**P5 — 5-stage (balanced)**
```
IF → ID → EX → MEM → WB
```
2-cycle branch penalty. Max clock: 1.3× base. Wins for mixed workloads (8% < β < 22%).

**P7 — 7-stage (throughput-optimized)**
```
IF1 → IF2 → ID → EX1 → EX2 → MEM → WB
```
5-cycle branch penalty. Max clock: 1.5× base. Wins when β < 10%.

### Superset Design

Rather than three separate pipelines, we implement P7 as a superset with **4 bypass multiplexers** that short-circuit stages for shallower modes:

| Mode | bp_if2 | bp_id_ex | bp_ex2 | bp_ex_mem | Active Stages |
|------|--------|----------|--------|-----------|---------------|
| P3   | 1      | 1        | 1      | 1         | 3             |
| P5   | 1      | 0        | 1      | 0         | 5             |
| P7   | 0      | 0        | 0      | 0         | 7             |

### 12-Configuration Space

Each mode supports a range of clock speeds constrained by its critical path:

- **P3:** 1.0×, 1.1× (2 options)
- **P5:** 1.0×, 1.1×, 1.2×, 1.3× (4 options)
- **P7:** 1.0×, 1.1×, 1.2×, 1.3×, 1.4×, 1.5× (6 options)

**Total: 12 valid configurations.** The gap between best and worst is 50–98% across benchmarks.

---

## The Online Perceptron Predictor

The core innovation: 12 perceptrons (one per configuration) score each option using 3 runtime features:

```
s_c(x) = w_{c,0} + w_{c,1}·β + w_{c,2}·ρ + w_{c,3}·σ

where:
  β = branch rate (0–35%)
  ρ = CPI ratio: (P7_cycles − P3_cycles) / P3_cycles × 100
  σ = stall rate from data hazards (0–23%)
```

**Prediction:** pick the configuration with the highest score.
**Learning:** on misclassification, subtract ηx from the wrong config's weights, add ηx to the correct config's weights. Learning rate η = 0.5, 8-bit saturating arithmetic, no multipliers needed.

### What the Perceptron Learns

After training, only **3 of the 12 configurations** develop significant weights — always at maximum clock for the selected depth:

| Config | Branch% weight | CPI Ratio weight | Stall% weight | Bias | Interpretation |
|--------|---------------|-----------------|---------------|------|----------------|
| **P3@1.1×** | +0.47 | +0.56 | — | — | High branches + high CPI ratio → shallow pipeline |
| **P5@1.3×** | −0.27 | — | +0.25 | +0.29 | Moderate branches + stalls → balanced pipeline |
| **P7@1.5×** | — | −0.55 | — | +0.36 | Low CPI ratio → deep pipeline at max clock |

The perceptron autonomously discovered that sub-optimal clock speeds are never worth selecting. It also recovered the analytical decision boundary (P3 wins when β > 22%) from data alone.

### Hyperparameter Robustness

A systematic grid search over learning rate (η) and training passes shows accuracy exceeds 93% across a wide stable region (η ≥ 0.35, passes ≥ 15). The selected operating point (η = 0.5, 20 passes) achieves 97.436% on unseen workloads.

---

## Benchmark Suite (108 total)

### 10 Hand-Written Benchmarks

| # | Benchmark | β(%) | σ(%) | P3 cycles | P5 cycles | P7 cycles | Best Config |
|---|-----------|------|------|-----------|-----------|-----------|-------------|
| 0 | Branch-Heavy | 30 | 0 | 164 | 204 | 282 | **P3@1.1×** |
| 1 | Load-Use | 9 | 23 | 162 | 173 | 233 | P5@1.3× |
| 2 | ALU-Intensive | 6 | 0 | 246 | 262 | 292 | **P7@1.5×** |
| 3 | Bubble Sort | 14 | 7 | N/A | 401 | 507 | P5@1.3× |
| 4 | Compute | 5 | 0 | 392 | 413 | 453 | **P7@1.5×** |
| 5 | Memory Stream | 5 | 0 | 590 | 621 | 681 | **P7@1.5×** |
| 6 | Tight Loop | 35 | 0 | 604 | 766 | 1088 | **P3@1.1×** |
| 7 | Nested Loops | 22 | 0 | 352 | 413 | 533 | P5@1.3× |
| 8 | Switch-Case | 26 | 0 | 543 | 644 | 844 | **P3@1.1×** |
| 9 | Vector Ops | 6 | 0 | 307 | 328 | 368 | **P7@1.5×** |

### 90 Generated Benchmarks

10 categories × 3 sizes × 3 variants:
Pure ALU, Branch-Heavy, Load-Store Stream, Load-Use Hazard, Mixed Nested Loops, Dependency Chains, Independent ALU, Branch Patterns, Fibonacci, Memory Copy.

### 8 C-Compiled Benchmarks

Compiled with `riscv-none-elf-gcc` 15.2.0 (`-march=rv32i -mabi=ilp32 -O2`):

| Benchmark | Cycles | β(%) | Best | Notes |
|-----------|--------|------|------|-------|
| Matrix Multiply (4×4) | 81 | 0 | **P7@1.5×** | Unrolled, no start.S |
| Shift-XOR CRC | 73 | 0 | **P7@1.5×** | Unrolled, no start.S |
| Decision Tree (3×16) | 863 | 28 | **P3@1.1×** | Dense if/else |
| State Machine | 2,762 | 29 | **P3@1.1×** | Branch maze |
| Branch Storm | 1,458 | 21 | P5@1.3× | Mixed control flow |
| Pointer Chase | 1,234 | 13 | P5@1.3× | Load-use chains |
| Vector Ops | 210 | 1 | P5@1.3× | Stall-dominated |
| Dhrystone Mix | 3,115 | 13 | P5@1.3× | General-purpose |

### Oracle Distribution

- **P3@1.1×:** 14 benchmarks (13%)
- **P5@1.3×:** 50 benchmarks (46%)
- **P7@1.5×:** 44 benchmarks (41%)

---

## Comparison vs. Other Policies

### Overhead vs. Perfect Oracle (%)

| Policy | Original-10 | ALU-vs-Branch | Mixed-New | Full-50 | Repeating |
|--------|-------------|---------------|-----------|---------|-----------|
| Always P5@1.0× | 34.253 | 34.878 | 32.022 | 34.157 | 36.780 |
| Always P5@1.3× | 3.271 | 3.753 | 1.555 | 3.198 | 5.215 |
| UCB1 (12-arm) | 26.114 | 25.545 | 21.091 | 21.503 | 23.836 |
| **PDPM** | **1.801** | **2.534** | **2.376** | **3.687** | **2.013** |
| **PDPM+Phase** | **2.673** | **1.803** | **2.388** | **3.698** | **0.560** |

### Generalization (train on 30, test on 78 unseen)

| Policy | Overhead | Config Accuracy |
|--------|----------|----------------|
| Always P5@1.0× | +31.726% | 0.000% |
| Always P5@1.3× | +1.328% | 57.692% |
| UCB1 (12-arm) | +45.035% | 8.718% |
| **PDPM (frozen weights)** | **+0.003%** | **97.436%** |

---

## Hardware

**Target:** UPduino 3.1 (Lattice iCE40 UP5K)

| Resource | Available | Used | Utilization |
|----------|-----------|------|-------------|
| Logic Cells (LUT4) | 5,280 | ~3,600 | 68% |
| Block RAM | 120 Kb | 8 blocks | 27% |
| Multipliers | 8 | 0 | 0% |
| Predictor overhead | — | <50 LUTs | <1% |

Synthesis: Yosys + nextpnr. Simulation: Icarus Verilog.

---

## Project Structure

```
morphable-cpu/
├── benches/                        # 108 benchmark programs (.hex files)
│   ├── bench_branch.hex ... bench_vector.hex    # 10 hand-written
│   ├── bench_gen_*.hex                          # 90 generated
│   └── bench_c_*.hex                            # 8 C-compiled
│
├── c_benchmarks/                   # C source for compiled benchmarks
│   ├── bench_matmul.c              # 4×4 matrix multiply
│   ├── bench_crc.c                 # Shift-XOR CRC
│   ├── bench_qsort.c              # Decision tree classifier
│   ├── bench_bsearch.c            # State machine
│   ├── bench_string.c             # Branch storm
│   ├── bench_linkedlist.c         # Pointer chase
│   ├── bench_fib.c                # Vector ops
│   ├── bench_dhrystone.c          # Dhrystone mix
│   ├── start.S                    # Startup code
│   ├── link.ld                    # Linker script
│   ├── elf2hex.py                 # ELF to hex converter
│   └── build.bat                  # Build script
│
├── cpu_morphable_top.v            # Top-level CPU (871 lines)
├── pipeline_mode_ctrl_v2.v        # Mode controller (module: pipeline_mode_ctrl_v3)
├── perceptron_predictor.v         # Joint perceptron (module: perceptron_predictor_v2)
├── cpi_monitor.v                  # Performance monitoring
│
├── alu.v                          # Arithmetic Logic Unit
├── rf.v                           # Register File (32 registers)
├── imem.v                         # Instruction Memory
├── dmem.v                         # Data Memory
├── immgen.v                       # Immediate Generator
├── branch_resolution.v            # Branch target calculation
├── bc.v                           # Branch condition evaluation
│
├── if_id_reg.v                    # IF/ID pipeline register
├── id_ex_reg.v                    # ID/EX pipeline register
├── ex_mem_reg.v                   # EX/MEM pipeline register
├── mem_wb_reg.v                   # MEM/WB pipeline register
├── if1_if2_reg.v                  # IF1/IF2 register (P7 mode)
├── ex1_ex2_reg.v                  # EX1/EX2 register (P7 mode)
│
├── forwarding_unit.v              # Data forwarding (4 sources, mode-aware)
├── hazard_unit.v                  # Hazard detection
├── control_pipeline.v             # Control signal generation
│
├── cpu_morphable_top_tb.v         # Testbench (108 benchmarks, 416 lines)
├── upduino_top.v                  # FPGA top-level wrapper
├── upduino_top.pcf                # Pin constraint file
│
├── bandit_simulation.py           # Joint predictor evaluation (789 lines)
├── gen_benchmarks.py              # Benchmark generator
├── results/                       # Figures (PNG + PDF)
│   ├── summary_table.png          # Color-coded overhead comparison
│   ├── generalization.png         # Train/test bar chart (97.436%)
│   ├── joint_weights.png          # 12×4 weight heatmap
│   ├── hyperparam_heatmap.png     # η × passes accuracy search
│   ├── regret_Full-50.png         # Cumulative regret curves
│   ├── lr_sensitivity.png         # Accuracy vs learning rate
│   ├── training_convergence.png   # Accuracy vs training passes
│   └── ...                        # Additional regret/analysis plots
│
├── trace_log.csv                  # Simulation trace (3.79 MB, 165K events)
└── README.md
```

**Total:** ~4,000 lines of Verilog, 789 lines Python evaluation, 108 benchmarks.

---

## Building and Running

### Simulation
```bash
# Run all 108 benchmarks in all 3 modes
iverilog -o morphable_tb cpu_morphable_top_tb.v cpu_morphable_top.v \
  pipeline_mode_ctrl_v2.v perceptron_predictor.v cpi_monitor.v \
  alu.v rf.v imem.v dmem.v immgen.v branch_resolution.v bc.v \
  forwarding_unit.v hazard_unit.v control_pipeline.v \
  if_id_reg.v id_ex_reg.v ex_mem_reg.v mem_wb_reg.v \
  if1_if2_reg.v ex1_ex2_reg.v
vvp morphable_tb
```

### Run Predictor Evaluation
```bash
# Requires: trace_log.csv in same directory
python3 bandit_simulation.py
# Outputs all figures to results/ folder
```

### C Benchmark Compilation
```bash
cd c_benchmarks
# Requires: riscv-none-elf-gcc (xPack 15.2.0)
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles \
  -O2 -ffreestanding -fno-builtin -T link.ld -Wl,--no-relax \
  -o bench.elf start.S bench_program.c
python3 elf2hex.py bench.elf > ../benches/bench_c_program.hex
```

### FPGA Synthesis (UPduino 3.1)
```bash
apio build
apio upload
```

---

## Key Engineering Challenges

**JALR Bug (P5/P7):** Function returns (`ret` = `jalr x0, ra, 0`) computed wrong targets in P5/P7 because `is_jalr` was read from the decode stage after the instruction had already moved to execute. Fix: derive `is_jalr` from `ex_a_sel` (JAL sets `a_sel=1`, JALR sets `a_sel=0`), with an extra pipeline register for P7's EX2 stage. This bug caused all 8 C benchmarks to fail until corrected.

**Clock Normalization Trap:** Raw cycle counts always favor P3 (fewer stages = fewer cycles). But after clock normalization, the ranking reverses for compute workloads. Equal-frequency comparisons are misleading — this is why the predictor must learn from *effective time*, not raw cycles.

**Generated Benchmark Halt:** All generated benchmarks use a universal halt via `ADDI + SLLI` to write `0xDEAD` to `x31` (no LUI needed, which avoids instruction encoding issues on the iCE40).

---

## References

- Patterson & Hennessy, *Computer Organization and Design: RISC-V Edition* (2017)
- Hennessy & Patterson, *Computer Architecture: A Quantitative Approach*, 6th ed. (2019)
- Jiménez & Lin, "Dynamic branch prediction with perceptrons," HPCA 2001
- Hrishikesh et al., "The optimal logic depth per pipeline stage is 6 to 8 FO4," ISCA 2002
- Auer et al., "Finite-time analysis of the multiarmed bandit problem," Machine Learning 2002
- RISC-V ISA Specification v2.2 (riscv.org)
- Lattice iCE40 UltraPlus Data Sheet (FPGA-DS-02008)
- UPduino 3.1 Documentation (tinyvision.ai)

---

*This project represents a lot of late nights, subtle pipeline bugs, and the satisfaction of watching a CPU learn to optimize itself. If you're working on something similar — keep going.*

— Dawit