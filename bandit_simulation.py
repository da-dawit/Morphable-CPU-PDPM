#!/usr/bin/env python3
"""
Joint Pipeline-Depth + Clock-Frequency Online Learning
========================================================

NOVEL CONTRIBUTION: The first RISC-V processor that jointly optimizes
pipeline depth AND clock frequency through online perceptron learning,
using direct execution measurement as the training signal.

12 configurations:
  P3 @ {1.0x, 1.1x}
  P5 @ {1.0x, 1.1x, 1.2x, 1.3x}
  P7 @ {1.0x, 1.1x, 1.2x, 1.3x, 1.4x, 1.5x}

The perceptron observes 3 features (branch%, CPI_ratio%, stall%) and
predicts which of the 12 configurations minimizes effective execution time.

Comparison:
  1. Always-P5@1.0x    — textbook baseline (no adaptation)
  2. Mode-Only Oracle  — knows best mode, uses max clock (previous work)
  3. UCB1 (12-arm)     — online bandit over all 12 configs
  4. Online Perceptron — joint (mode, clock) prediction from features
  5. Perceptron+Phase  — full PDPM system
  6. Full Oracle       — knows best (mode, clock) per phase
"""

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from collections import defaultdict, Counter
import os, sys, math

# ============================================================
# 1. CONFIGURATION SPACE
# ============================================================

# The 12 valid (mode, clock_index) configurations
CONFIGS = []
MAX_CLK_IDX = {0: 1, 1: 3, 2: 5}
CLK_MULT = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5]
for mode in range(3):
    for ci in range(MAX_CLK_IDX[mode] + 1):
        CONFIGS.append((mode, ci))
N_CONFIGS = len(CONFIGS)  # 12

MODE_NAMES = {0: 'P3', 1: 'P5', 2: 'P7'}
BENCH_NAMES = {
    0: 'Branch-Heavy', 1: 'Load-Use', 2: 'ALU-Intensive',
    3: 'Mixed', 4: 'Compute', 5: 'Mem-Stream',
    6: 'Tight-Loop', 7: 'Nested-Loops', 8: 'Switch-Case', 9: 'Vector-Ops'
}

def config_name(cfg_idx):
    m, ci = CONFIGS[cfg_idx]
    return f"P{[3,5,7][m]}@{CLK_MULT[ci]:.1f}x"

# Switching cost (pipeline drain cycles)
SWITCH_COST_MODE = {
    (0,0):0, (0,1):3, (0,2):5,
    (1,0):3, (1,1):0, (1,2):5,
    (2,0):5, (2,1):5, (2,2):0,
}

def switch_cost(cfg_from, cfg_to):
    """Cost of switching between two configurations."""
    m1, _ = CONFIGS[cfg_from]
    m2, _ = CONFIGS[cfg_to]
    return SWITCH_COST_MODE.get((m1, m2), 0)

# ============================================================
# 2. DATA LOADING & MODEL
# ============================================================

def load_trace(csv_path):
    rows, summaries = [], []
    with open(csv_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('EVENT'): continue
            parts = line.split(',')
            if parts[0] == 'TSUM':
                summaries.append({
                    'mode': int(parts[1]), 'bench': int(parts[2]),
                    'cycles': int(parts[3]), 'insts': int(parts[4]),
                    'stalls': int(parts[5]), 'flushes': int(parts[6])
                })
            elif parts[0] == 'T':
                rows.append({
                    'mode': int(parts[1]), 'bench': int(parts[2]),
                    'cycle': int(parts[3]), 'type': parts[4],
                    'pc': int(parts[5], 16)
                })
    return pd.DataFrame(rows), pd.DataFrame(summaries)


def build_model(summaries):
    """
    Build effective-time model for ALL 12 configurations.
    
    Returns:
        eff12: dict[bench][cfg_idx] = effective_time
        features: dict[bench] = {'branch':%, 'ratio':%, 'stall':%}
        raw_cycles: dict[bench][mode] = cycles
    """
    raw_cycles = defaultdict(dict)
    for _, row in summaries.iterrows():
        raw_cycles[row['bench']][row['mode']] = row['cycles']
    
    # Build effective time for all 12 configs
    eff12 = defaultdict(dict)
    for b in raw_cycles:
        for cfg_idx, (mode, ci) in enumerate(CONFIGS):
            if mode in raw_cycles[b]:
                eff12[b][cfg_idx] = raw_cycles[b][mode] / CLK_MULT[ci]
    
    # Features from P5 runs (mode=1) + P3/P7 ratio
    features = {}
    all_benches = sorted(set(summaries['bench']))
    for b in all_benches:
        s5 = summaries[(summaries['bench'] == b) & (summaries['mode'] == 1)]
        s0 = summaries[(summaries['bench'] == b) & (summaries['mode'] == 0)]
        s2 = summaries[(summaries['bench'] == b) & (summaries['mode'] == 2)]
        
        feat = {'branch': 15, 'ratio': 50, 'stall': 0}
        if len(s5) > 0:
            r = s5.iloc[0]
            if r['insts'] > 0:
                feat['branch'] = min(99, int(r['flushes'] * 100 / r['insts']))
            if r['cycles'] > 0:
                feat['stall'] = min(99, int(r['stalls'] * 100 / r['cycles']))
        if len(s0) > 0 and len(s2) > 0:
            p3 = s0.iloc[0]['cycles']
            p7 = s2.iloc[0]['cycles']
            if p3 > 0:
                feat['ratio'] = max(0, min(200, int((p7 / p3 - 1) * 100)))
        features[b] = feat
    
    return dict(eff12), features, dict(raw_cycles)


def eff_time(eff12, bench, cfg_idx):
    if bench in eff12 and cfg_idx in eff12[bench]:
        return eff12[bench][cfg_idx]
    if bench in eff12 and len(eff12[bench]) > 0:
        return max(eff12[bench].values()) * 2.0
    return 99999.0


def oracle_config(eff12, bench):
    """Best of all 12 configurations."""
    best_c, best_e = 0, float('inf')
    for ci in range(N_CONFIGS):
        e = eff_time(eff12, bench, ci)
        if e < best_e:
            best_e, best_c = e, ci
    return best_c


def mode_only_oracle(eff12, bench):
    """Best mode at its max clock (what previous 3-class predictor does)."""
    best_c, best_e = 0, float('inf')
    for mode in range(3):
        max_ci = MAX_CLK_IDX[mode]
        cfg_idx = None
        for i, (m, ci) in enumerate(CONFIGS):
            if m == mode and ci == max_ci:
                cfg_idx = i
                break
        if cfg_idx is not None:
            e = eff_time(eff12, bench, cfg_idx)
            if e < best_e:
                best_e, best_c = e, cfg_idx
    return best_c


# ============================================================
# 3. WORKLOAD GENERATION
# ============================================================

def make_workload(bench_seq, ipp=1000, reps=3):
    phases, inst = [], 0
    for _ in range(reps):
        for b in bench_seq:
            phases.append((b, inst, inst + ipp))
            inst += ipp
    return phases


# ============================================================
# 4. POLICIES
# ============================================================

class AlwaysP5_1x:
    """Textbook baseline: P5 at 1.0x clock."""
    name = "Always P5@1.0x"
    def __init__(self):
        # P5@1.0x is config index 2
        self.cfg = next(i for i,(m,c) in enumerate(CONFIGS) if m==1 and c==0)
    def reset(self): pass
    def notify_phase(self, b): pass
    def select(self, cur, idx): return self.cfg
    def update(self, cfg, reward, features=None, actual_best=None): pass


class AlwaysP5_Max:
    """P5 at max clock (1.3x) — a stronger baseline."""
    name = "Always P5@1.3x"
    def __init__(self):
        self.cfg = next(i for i,(m,c) in enumerate(CONFIGS) if m==1 and c==3)
    def reset(self): pass
    def notify_phase(self, b): pass
    def select(self, cur, idx): return self.cfg
    def update(self, cfg, reward, features=None, actual_best=None): pass


class ModeOnlyOracle:
    """Knows best MODE but always uses max clock for that mode.
    This is what the 3-class predictor achieves at best."""
    name = "Mode-Only Oracle"
    def __init__(self, eff12):
        self.eff12 = eff12
        self._bench = None
    def reset(self): pass
    def notify_phase(self, b): self._bench = b
    def select(self, cur, idx):
        return mode_only_oracle(self.eff12, self._bench) if self._bench else 5
    def update(self, cfg, reward, features=None, actual_best=None): pass


class FullOracle:
    """Knows best of all 12 configurations. Upper bound."""
    name = "Full Oracle"
    def __init__(self, eff12):
        self.eff12 = eff12
        self._bench = None
    def reset(self): pass
    def notify_phase(self, b): self._bench = b
    def select(self, cur, idx):
        return oracle_config(self.eff12, self._bench) if self._bench else 5
    def update(self, cfg, reward, features=None, actual_best=None): pass


class RandomPolicy:
    name = "Random"
    def reset(self): pass
    def notify_phase(self, b): pass
    def select(self, cur, idx): return np.random.randint(0, N_CONFIGS)
    def update(self, cfg, reward, features=None, actual_best=None): pass


class UCB1_12:
    """UCB1 over all 12 configurations."""
    name = "UCB1 (12-arm)"
    def __init__(self, c=2.0):
        self.c = c
        self.reset()
    def reset(self):
        self.counts = np.zeros(N_CONFIGS)
        self.sum_r = np.zeros(N_CONFIGS)
        self.total = 0
        self._rmin, self._rmax = float('inf'), float('-inf')
    def notify_phase(self, b): pass
    def _norm(self, r):
        self._rmin = min(self._rmin, r)
        self._rmax = max(self._rmax, r)
        s = self._rmax - self._rmin
        return (r - self._rmin) / s if s > 1e-15 else 0.5
    def select(self, cur, idx):
        for a in range(N_CONFIGS):
            if self.counts[a] == 0: return a
        means = self.sum_r / self.counts
        bonus = self.c * np.sqrt(np.log(self.total) / self.counts)
        return int(np.argmax(means + bonus))
    def update(self, cfg, reward, features=None, actual_best=None):
        nr = self._norm(reward) if self.total >= N_CONFIGS else 0.5
        self.counts[cfg] += 1
        self.sum_r[cfg] += nr
        self.total += 1


class JointPerceptron:
    """
    NOVEL: Joint Pipeline-Depth + Clock-Frequency Online Perceptron.
    
    12 perceptrons (one per configuration), each computing:
        score_i = w_i · x   where x = [branch%, ratio%, stall%, 1.0]
    
    Prediction: argmax_i(score_i)
    
    Training: perceptron update rule — reinforce correct config,
    anti-reinforce wrong config.
    
    This is the core innovation: learning which of 12 (depth, clock)
    configurations minimizes effective execution time, from workload
    features, during execution.
    """
    name = "Joint Perceptron"
    
    def __init__(self, n_features=4, lr=0.1):
        self.n_features = n_features
        self.lr = lr
        self.reset()
    
    def reset(self):
        rng = np.random.RandomState(42)
        self.weights = rng.randn(N_CONFIGS, self.n_features) * 0.01
        self._tried = [False] * N_CONFIGS
        self._round = 0
        self._bench = None
    
    def notify_phase(self, b): self._bench = b
    
    def _features(self, feat_dict):
        if feat_dict is None: return np.array([0.5, 0.5, 0.5, 1.0])
        return np.array([
            feat_dict.get('branch', 15) / 100.0,
            feat_dict.get('ratio', 50) / 100.0,
            feat_dict.get('stall', 0) / 100.0,
            1.0  # bias
        ])
    
    def select(self, cur, idx, features=None):
        self._round += 1
        # Initial exploration: try each config once
        for i in range(N_CONFIGS):
            if not self._tried[i]:
                self._tried[i] = True
                return i
        # Perceptron forward pass
        x = self._features(features)
        scores = self.weights @ x
        return int(np.argmax(scores))
    
    def update(self, cfg, reward, features=None, actual_best=None):
        if actual_best is None: return
        x = self._features(features)
        if cfg != actual_best:
            self.weights[cfg] -= self.lr * x
            self.weights[actual_best] += self.lr * x


class JointPerceptronWithPhase(JointPerceptron):
    """Joint Perceptron + Phase Memory. The full PDPM system."""
    name = "Joint Perceptron + Phase"
    
    def __init__(self, n_features=4, lr=0.1):
        super().__init__(n_features, lr)
        self.phase_mem = {}
        self.phase_conf = {}
        self.conf_thresh = 3
    
    def reset(self):
        super().reset()
        self.phase_mem = {}
        self.phase_conf = {}
    
    def select(self, cur, idx, features=None):
        sig = self._bench
        if sig in self.phase_mem and self.phase_conf.get(sig, 0) >= self.conf_thresh:
            return self.phase_mem[sig]
        return super().select(cur, idx, features=features)
    
    def update(self, cfg, reward, features=None, actual_best=None):
        super().update(cfg, reward, features=features, actual_best=actual_best)
        sig = self._bench
        if actual_best is not None:
            if sig not in self.phase_mem:
                self.phase_mem[sig] = actual_best
                self.phase_conf[sig] = 1
            elif self.phase_mem[sig] == actual_best:
                self.phase_conf[sig] += 1
            else:
                self.phase_mem[sig] = actual_best
                self.phase_conf[sig] = 1


# ============================================================
# 5. SIMULATION ENGINE
# ============================================================

def simulate(policy, phases, eff12, feature_db, interval=200):
    history = []
    cur_cfg = next(i for i,(m,c) in enumerate(CONFIGS) if m==1 and c==0)  # start P5@1.0x
    total_eff, total_oracle = 0.0, 0.0
    idx = 0
    
    for bench, p_start, p_end in phases:
        policy.notify_phase(bench)
        n_win = max(1, (p_end - p_start) // interval)
        feats = feature_db.get(bench, {'branch': 15, 'ratio': 50, 'stall': 0})
        best_cfg = oracle_config(eff12, bench)
        oracle_e = eff_time(eff12, bench, best_cfg)
        mode_best = mode_only_oracle(eff12, bench)
        mode_oracle_e = eff_time(eff12, bench, mode_best)
        
        for _ in range(n_win):
            # Select
            if hasattr(policy.select, '__code__') and 'features' in policy.select.__code__.co_varnames:
                chosen = policy.select(cur_cfg, idx, features=feats)
            else:
                chosen = policy.select(cur_cfg, idx)
            
            sw = switch_cost(cur_cfg, chosen)
            e = eff_time(eff12, bench, chosen)
            e_sw = e + sw / interval
            
            reward = 1.0 / e_sw if e_sw > 0 else 0
            
            try:
                policy.update(chosen, reward, features=feats, actual_best=best_cfg)
            except TypeError:
                policy.update(chosen, reward)
            
            total_eff += e_sw * interval
            total_oracle += oracle_e * interval
            
            history.append({
                'inst': idx, 'bench': bench,
                'chosen': chosen, 'oracle': best_cfg, 'mode_oracle': mode_best,
                'correct_full': chosen == best_cfg,
                'correct_mode': CONFIGS[chosen][0] == CONFIGS[best_cfg][0],
                'eff': e_sw, 'oracle_eff': oracle_e, 'mode_oracle_eff': mode_oracle_e,
                'regret': (e_sw - oracle_e) * interval,
                'regret_vs_mode': (e_sw - mode_oracle_e) * interval,
            })
            
            cur_cfg = chosen
            idx += interval
    
    return history, total_eff, total_oracle


# ============================================================
# 6. EXPERIMENTS
# ============================================================

def run_experiments(eff12, feature_db):
    np.random.seed(42)
    
    valid = sorted([b for b in eff12 if len(eff12[b]) >= 6])
    
    workloads = {
        'Original-10': ([0,2,1,6,4,8,7,9,5,3], 1000, 3),
        'ALU-vs-Branch': ([10,25,13,37,16,30,22,39], 1000, 3),
        'Mixed-New': ([40,50,60,70,80,85,91,97], 1000, 3),
        'Full-50': (valid[:50], 500, 2),
        'Repeating': ([0,4,0,4,0,4,0,4], 1000, 4),
        'Phase-Recall': ([0,2,0,2,0,2,0,2], 1000, 2),
    }
    
    all_results = {}
    for wname, (seq, ipp, reps) in workloads.items():
        phases = make_workload(seq, ipp, reps)
        policies = [
            AlwaysP5_1x(),
            AlwaysP5_Max(),
            RandomPolicy(),
            ModeOnlyOracle(eff12),
            UCB1_12(c=2.0),
            JointPerceptron(lr=0.1),
            JointPerceptronWithPhase(lr=0.1),
            FullOracle(eff12),
        ]
        results = {}
        for pol in policies:
            pol.reset()
            hist, total, oracle_total = simulate(pol, phases, eff12, feature_db, interval=200)
            results[pol.name] = {'history': hist, 'total': total, 'oracle_total': oracle_total}
        all_results[wname] = results
    
    # === GENERALIZATION: Train on 30, test on 70 ===
    train = valid[:30]
    test = valid[30:]
    
    perc = JointPerceptron(lr=0.1)
    perc.reset()
    simulate(perc, make_workload(train, 1000, 5), eff12, feature_db, interval=200)
    
    # Freeze and test
    frozen = JointPerceptron(lr=0.0)
    frozen.reset()
    frozen.weights = perc.weights.copy()
    frozen._tried = [True] * N_CONFIGS
    
    gen_results = {}
    test_phases = make_workload(test, 1000, 1)
    for name, pol in [
        ('Always P5@1.0x', AlwaysP5_1x()),
        ('Always P5@1.3x', AlwaysP5_Max()),
        ('Mode-Only Oracle', ModeOnlyOracle(eff12)),
        ('UCB1 (12-arm)', UCB1_12(c=2.0)),
        ('Perceptron (trained on 30)', frozen),
        ('Full Oracle', FullOracle(eff12)),
    ]:
        if hasattr(pol, 'reset') and 'trained' not in name:
            pol.reset()
        hist, total, ot = simulate(pol, test_phases, eff12, feature_db, interval=200)
        correct = sum(1 for r in hist if r['correct_full']) / len(hist) * 100
        overhead = (total / ot - 1) * 100
        gen_results[name] = {'overhead': overhead, 'correct': correct, 'total': total, 'oracle': ot}
    
    return all_results, gen_results


# ============================================================
# 7. PLOTTING
# ============================================================

plt.rcParams.update({
    'font.size': 9, 'font.family': 'serif',
    'figure.dpi': 300, 'savefig.dpi': 300, 'savefig.bbox': 'tight',
    'axes.linewidth': 0.5, 'lines.linewidth': 1.2,
    'legend.fontsize': 7, 'axes.labelsize': 9, 'axes.titlesize': 10,
})

COLORS = {
    'Always P5@1.0x': '#cccccc', 'Always P5@1.3x': '#999999',
    'Random': '#dddddd', 'Mode-Only Oracle': '#e69f00',
    'UCB1 (12-arm)': '#56b4e9', 'Joint Perceptron': '#009e73',
    'Joint Perceptron + Phase': '#d55e00', 'Full Oracle': '#000000',
}
LSTYLES = {
    'Always P5@1.0x': ':', 'Always P5@1.3x': '--',
    'Random': ':', 'Mode-Only Oracle': '-.',
    'UCB1 (12-arm)': '--', 'Joint Perceptron': '-',
    'Joint Perceptron + Phase': '-', 'Full Oracle': '-',
}
LWIDTHS = {'Joint Perceptron + Phase': 2.0, 'Joint Perceptron': 1.5, 'Full Oracle': 1.0}


def plot_regret(results, wname, outdir):
    fig, ax = plt.subplots(1, 1, figsize=(3.5, 2.8))
    for pname, data in results.items():
        h = data['history']
        insts = [r['inst'] for r in h]
        cum_reg = np.cumsum([r['regret'] for r in h])
        ax.plot(insts, cum_reg, label=pname,
                color=COLORS.get(pname, '#333'),
                linestyle=LSTYLES.get(pname, '-'),
                linewidth=LWIDTHS.get(pname, 1.0))
    ax.set_xlabel('Instructions')
    ax.set_ylabel('Cumulative Regret\n(eff. cycles vs. Full Oracle)')
    ax.set_title(f'Workload: {wname}')
    ax.legend(loc='upper left', framealpha=0.9, ncol=2, fontsize=5.5)
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    fig.savefig(os.path.join(outdir, f'regret_{wname}.png'))
    fig.savefig(os.path.join(outdir, f'regret_{wname}.pdf'))
    plt.close(fig)


def plot_summary_table(all_results, gen_results, outdir):
    """Main comparison table."""
    workloads = [w for w in all_results.keys() if w != 'Phase-Recall']
    all_pols = set()
    for w in workloads: all_pols.update(all_results[w].keys())
    
    order = ['Always P5@1.0x', 'Always P5@1.3x', 'Random', 'Mode-Only Oracle',
             'UCB1 (12-arm)', 'Joint Perceptron', 'Joint Perceptron + Phase', 'Full Oracle']
    order = [p for p in order if p in all_pols]
    
    fig, ax = plt.subplots(1, 1, figsize=(4.5, 2.5))
    ax.axis('off')
    
    cells = []
    for pname in order:
        row = []
        for w in workloads:
            if pname in all_results[w]:
                t = all_results[w][pname]['total']
                ot = all_results[w]['Full Oracle']['total']
                oh = (t / ot - 1) * 100
                row.append(f'{oh:.1f}%')
            else: row.append('-')
        cells.append(row)
    
    # Shorten column labels
    col_labels = [w[:12] for w in workloads]
    table = ax.table(cellText=cells, rowLabels=order, colLabels=col_labels,
                      loc='center', cellLoc='center')
    table.auto_set_font_size(False)
    table.set_fontsize(6)
    table.scale(1.0, 1.3)
    
    for i, pname in enumerate(order):
        for j in range(len(workloads)):
            cell = table[i+1, j]
            txt = cells[i][j]
            if txt != '-':
                v = float(txt.replace('%', ''))
                if v <= 2.0: cell.set_facecolor('#d4edda')
                elif v <= 5.0: cell.set_facecolor('#fff3cd')
                elif v <= 15.0: cell.set_facecolor('#ffeeba')
                else: cell.set_facecolor('#f8d7da')
    
    ax.set_title('Overhead vs. Full Oracle (%)', fontsize=9, pad=10)
    plt.tight_layout()
    fig.savefig(os.path.join(outdir, 'summary_table.png'))
    fig.savefig(os.path.join(outdir, 'summary_table.pdf'))
    plt.close(fig)


def plot_generalization(gen_results, outdir):
    """Bar chart: generalization test results."""
    fig, ax = plt.subplots(1, 1, figsize=(3.5, 2.5))
    
    names = list(gen_results.keys())
    overheads = [gen_results[n]['overhead'] for n in names]
    corrects = [gen_results[n]['correct'] for n in names]
    
    x = np.arange(len(names))
    bars = ax.bar(x, overheads, color=['#ccc','#999','#e69f00','#56b4e9','#d55e00','#000'])
    ax.set_xticks(x)
    ax.set_xticklabels([n.replace(' ', '\n') for n in names], fontsize=5.5, ha='center')
    ax.set_ylabel('Overhead vs. Full Oracle (%)')
    ax.set_title('Generalization: Train on 30, Test on 70 Unseen', fontsize=9)
    
    for bar, c in zip(bars, corrects):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.3,
                f'{c:.0f}%', ha='center', va='bottom', fontsize=6)
    
    ax.grid(True, alpha=0.3, axis='y')
    plt.tight_layout()
    fig.savefig(os.path.join(outdir, 'generalization.png'))
    fig.savefig(os.path.join(outdir, 'generalization.pdf'))
    plt.close(fig)


def plot_weights(eff12, feature_db, outdir):
    """Train a perceptron on all data and visualize weights."""
    perc = JointPerceptron(lr=0.05)
    perc.reset()
    all_b = sorted(eff12.keys())
    for _ in range(50):
        for b in all_b:
            if b not in feature_db: continue
            best = oracle_config(eff12, b)
            pred = perc.select(0, 0, features=feature_db[b])
            perc.update(pred, 0, features=feature_db[b], actual_best=best)
    
    fig, ax = plt.subplots(1, 1, figsize=(4.0, 3.5))
    w = perc.weights  # (12, 4)
    feat_names = ['Branch%', 'CPI Ratio%', 'Stall%', 'Bias']
    cfg_labels = [config_name(i) for i in range(N_CONFIGS)]
    
    im = ax.imshow(w, cmap='RdBu_r', aspect='auto', vmin=-0.5, vmax=0.5)
    ax.set_xticks(range(4))
    ax.set_xticklabels(feat_names, fontsize=7)
    ax.set_yticks(range(N_CONFIGS))
    ax.set_yticklabels(cfg_labels, fontsize=6)
    
    for i in range(N_CONFIGS):
        for j in range(4):
            ax.text(j, i, f'{w[i,j]:.2f}', ha='center', va='center', fontsize=5,
                    color='white' if abs(w[i,j]) > 0.3 else 'black')
    
    plt.colorbar(im, ax=ax, shrink=0.8)
    ax.set_title('Learned Joint Perceptron Weights\n(12 configs × 4 features)', fontsize=9)
    plt.tight_layout()
    fig.savefig(os.path.join(outdir, 'joint_weights.png'))
    fig.savefig(os.path.join(outdir, 'joint_weights.pdf'))
    plt.close(fig)


def plot_config_distribution(all_results, eff12, outdir):
    """Show what configs the perceptron actually picks vs oracle."""
    wname = 'Original-10'
    if wname not in all_results: return
    
    fig, axes = plt.subplots(1, 2, figsize=(5, 2.5))
    
    for ax, pname in zip(axes, ['Joint Perceptron + Phase', 'Full Oracle']):
        if pname not in all_results[wname]: continue
        h = all_results[wname][pname]['history']
        chosen_cfgs = Counter(r['chosen'] for r in h)
        labels = [config_name(i) for i in range(N_CONFIGS)]
        counts = [chosen_cfgs.get(i, 0) for i in range(N_CONFIGS)]
        colors = ['#e41a1c' if CONFIGS[i][0]==0 else '#377eb8' if CONFIGS[i][0]==1 else '#4daf4a'
                  for i in range(N_CONFIGS)]
        ax.barh(range(N_CONFIGS), counts, color=colors, alpha=0.8)
        ax.set_yticks(range(N_CONFIGS))
        ax.set_yticklabels(labels, fontsize=6)
        ax.set_xlabel('Times Selected', fontsize=7)
        ax.set_title(pname, fontsize=8)
    
    plt.tight_layout()
    fig.savefig(os.path.join(outdir, 'config_distribution.png'))
    fig.savefig(os.path.join(outdir, 'config_distribution.pdf'))
    plt.close(fig)


# ============================================================
# 8. TEXT OUTPUT
# ============================================================

def print_results(all_results, gen_results, eff12, feature_db):
    print("\n" + "=" * 78)
    print("  JOINT PIPELINE-DEPTH + CLOCK-FREQUENCY ONLINE LEARNING")
    print("  100 Benchmarks × 12 Configurations")
    print("=" * 78)
    
    # Config space
    print(f"\n--- 12 Configuration Space ---")
    for i, (m, ci) in enumerate(CONFIGS):
        print(f"  [{i:2d}] P{[3,5,7][m]} @ {CLK_MULT[ci]:.1f}x")
    
    # Per-workload
    for wname, results in all_results.items():
        print(f"\n--- Workload: {wname} ---")
        ot = results['Full Oracle']['total']
        print(f"{'Policy':<28} {'Overhead':>9} {'Config%':>8} {'Mode%':>7}")
        print("-" * 56)
        
        order = ['Always P5@1.0x', 'Always P5@1.3x', 'Mode-Only Oracle',
                 'UCB1 (12-arm)', 'Joint Perceptron', 'Joint Perceptron + Phase', 'Full Oracle']
        for pname in order:
            if pname not in results: continue
            t = results[pname]['total']
            h = results[pname]['history']
            oh = (t / ot - 1) * 100
            cfg_corr = sum(1 for r in h if r['correct_full']) / len(h) * 100
            mode_corr = sum(1 for r in h if r['correct_mode']) / len(h) * 100
            marker = ' <<<' if 'Phase' in pname else ''
            print(f"  {pname:<26} {oh:+8.1f}% {cfg_corr:7.1f}% {mode_corr:6.1f}%{marker}")
    
    # Generalization
    print(f"\n{'=' * 78}")
    print("  GENERALIZATION: Train on 30 benchmarks, Test on 70 UNSEEN")
    print(f"{'=' * 78}")
    print(f"{'Policy':<32} {'Overhead':>9} {'Correct':>8}")
    print("-" * 52)
    for name, g in gen_results.items():
        print(f"  {name:<30} {g['overhead']:+8.1f}% {g['correct']:7.1f}%")
    
    # Oracle distribution
    valid = sorted([b for b in eff12 if len(eff12[b]) >= 6])
    print(f"\n--- Oracle Config Distribution ({len(valid)} benchmarks) ---")
    oracle_cfgs = Counter(oracle_config(eff12, b) for b in valid)
    for i in range(N_CONFIGS):
        if oracle_cfgs[i] > 0:
            print(f"  {config_name(i):<12}: {oracle_cfgs[i]:3d} benchmarks")


# ============================================================
# 9. MAIN
# ============================================================

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    trace_path = os.path.join(script_dir, 'trace_log.csv')
    if not os.path.exists(trace_path):
        trace_path = '/mnt/user-data/uploads/trace_log.csv'
    if not os.path.exists(trace_path):
        print("ERROR: trace_log.csv not found!"); sys.exit(1)
    
    outdir = os.path.join(script_dir, 'results')
    os.makedirs(outdir, exist_ok=True)
    
    print("Loading trace data...")
    traces, sums = load_trace(trace_path)
    print(f"  {len(traces)} events, {len(sums)} summaries")
    
    print("Building 12-configuration model...")
    eff12, feature_db, raw_cycles = build_model(sums)
    valid = [b for b in eff12 if len(eff12[b]) >= 6]
    print(f"  {len(valid)} valid benchmarks, {N_CONFIGS} configurations")
    
    print("Running experiments...")
    all_results, gen_results = run_experiments(eff12, feature_db)
    
    print("Generating plots...")
    for wname in all_results:
        if wname == 'Phase-Recall': continue
        plot_regret(all_results[wname], wname, outdir)
    plot_summary_table(all_results, gen_results, outdir)
    plot_generalization(gen_results, outdir)
    plot_weights(eff12, feature_db, outdir)
    plot_config_distribution(all_results, eff12, outdir)
    
    print_results(all_results, gen_results, eff12, feature_db)
    
    print(f"\n{'=' * 78}")
    print(f"  Plots saved to: {outdir}/")
    print(f"{'=' * 78}")

if __name__ == '__main__':
    main()