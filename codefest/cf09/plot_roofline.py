"""CF09 task 9 — roofline plot for the SNN accelerator (sky130 ASIC target).

Plots the accelerator's measured attainable performance against its two
arithmetic-intensity bounds (from cman_ai_analysis.md) on the on-chip-memory
roofline of the synthesized design.

Metric convention: this is an event-driven SNN, so work is counted in SynOps
(synaptic operations = one weight x one spike multiply-accumulate), not FLOPs,
matching cman_ai_analysis.md.

Platform ceilings (derived from the synthesized design, not a profiler):
  - Peak compute  = NB_MACS x f_clk = 8 lanes x 50 MHz   = 0.40 GSynOps/s
  - Peak on-chip BW = 8 banks x 1 byte/cycle x 50 MHz     = 0.40 GB/s
  - Ridge point   = peak_compute / peak_BW                = 1.0 SynOp/byte

Kernel AI bounds (cman_ai_analysis.md, 10% sparsity):
  - No reuse (lower)   = (200 x 20) / 8800 = 0.45 SynOp/byte
  - Full reuse (upper) = (200 x 20) / 4800 = 0.83 SynOp/byte

Measured attainable performance (CLLM task 7, cocotb cycle count):
  - SynOps/inference = 100 steps x (20 active x 200) = 400,000 SynOps
  - latency @ 10%    = 75,302 cycles x 20 ns         = 1.506 ms
  - throughput       = 400,000 / 1.506e-3            = 0.266 GSynOps/s

Output: codefest/cf09/benchmarks/roofline_plot.png
"""

import os

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

# --- Platform ceilings (synthesized design) -------------------------------
PEAK_COMPUTE = 0.40   # GSynOps/s : 8 MAC lanes x 50 MHz
PEAK_BW      = 0.40   # GB/s      : 8 SRAM banks x 1 byte/cycle x 50 MHz
RIDGE        = PEAK_COMPUTE / PEAK_BW   # 1.0 SynOp/byte

# --- Kernel arithmetic-intensity bounds (cman_ai_analysis.md) -------------
AI_LOWER = 0.45   # no reuse
AI_UPPER = 0.83   # perfect weight reuse

# --- Measured attainable performance (task 7) -----------------------------
SYNOPS_PER_INF = 100 * 20 * 200          # 400,000 SynOps @ 10% sparsity
LATENCY_S      = 75302 * 20e-9           # 1.506 ms
MEASURED_PERF  = (SYNOPS_PER_INF / LATENCY_S) / 1e9   # GSynOps/s ~= 0.266

# Effective arithmetic intensity implied by the measurement.
# The roofline guarantees perf <= AI x peak_BW, so the measured throughput
# pins a lower bound on the real AI: AI_eff = measured_perf / peak_BW.
# This is *above* the no-reuse bound (0.45), proving the design achieves
# partial weight reuse; it tightens the AI estimate to [AI_eff, AI_UPPER].
AI_EFF = MEASURED_PERF / PEAK_BW          # ~= 0.665 SynOp/byte


def roofline(ai):
    """Attainable performance ceiling at arithmetic intensity `ai`."""
    return np.minimum(PEAK_COMPUTE, PEAK_BW * ai)


def main():
    fig, ax = plt.subplots(figsize=(8, 6))

    # Roofline curve --------------------------------------------------------
    ai = np.logspace(-1, 2, 500)
    ax.plot(ai, roofline(ai), color="#1f4e79", lw=2.5, zorder=3)

    # Ceilings as guide labels
    ax.axhline(PEAK_COMPUTE, color="#1f4e79", ls=":", lw=1, alpha=0.6)
    ax.text(40, PEAK_COMPUTE * 1.08,
            f"compute ceiling = {PEAK_COMPUTE:.2f} GSynOps/s\n(8 MACs x 50 MHz)",
            color="#1f4e79", ha="right", va="bottom", fontsize=9)
    ax.text(0.115, roofline(0.115) * 1.1,
            f"BW ceiling\n(slope = {PEAK_BW:.2f} GB/s)",
            color="#1f4e79", ha="left", va="bottom", fontsize=9, rotation=33,
            rotation_mode="anchor")

    # Ridge point -----------------------------------------------------------
    ax.plot([RIDGE], [PEAK_COMPUTE], "o", color="#1f4e79", ms=8, zorder=5)
    ax.annotate(f"ridge point\n({RIDGE:.1f} SynOp/byte)",
                xy=(RIDGE, PEAK_COMPUTE), xytext=(RIDGE * 1.4, PEAK_COMPUTE * 0.5),
                fontsize=9, color="#1f4e79",
                arrowprops=dict(arrowstyle="->", color="#1f4e79"))

    # Kernel AI bounds (vertical lines) ------------------------------------
    for x, label in [(AI_LOWER, f"AI lower\n(no reuse)\n{AI_LOWER}"),
                     (AI_UPPER, f"AI upper\n(full reuse)\n{AI_UPPER}")]:
        ax.axvline(x, color="#888888", ls="--", lw=1, zorder=2)
        ax.text(x, 0.011, label, rotation=0, ha="center", va="bottom",
                fontsize=8, color="#555555")

    # Shade the AI region the measurement actually allows: [AI_EFF, AI_UPPER].
    # The no-reuse bound (AI_LOWER) is ruled out because the measured
    # throughput exceeds its ceiling -> real reuse is non-zero.
    ax.axvspan(AI_EFF, AI_UPPER, color="#ffd9b3", alpha=0.45, zorder=0)

    # Single measured accelerator point at the back-computed effective AI,
    # sitting on the bandwidth roof (memory-bound, running near the BW limit).
    ax.plot([AI_EFF], [MEASURED_PERF], "D", color="#c00000", ms=11, zorder=7)
    ax.annotate(f"accelerator (MEASURED)\n{MEASURED_PERF:.3f} GSynOps/s\n"
                f"AI_eff = {AI_EFF:.2f} SynOp/byte\n"
                f"@ 10% sparsity, 1.506 ms/inf",
                xy=(AI_EFF, MEASURED_PERF),
                xytext=(1.25, MEASURED_PERF * 0.30),
                fontsize=9, color="#c00000", fontweight="bold",
                arrowprops=dict(arrowstyle="->", color="#c00000"))

    # Axes ------------------------------------------------------------------
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlim(0.1, 100)
    ax.set_ylim(0.01, 1.0)
    ax.set_xlabel("Arithmetic intensity (SynOps/byte)", fontsize=11)
    ax.set_ylabel("Attainable performance (GSynOps/s)", fontsize=11)
    ax.set_title("CF09 Roofline — SNN accelerator (sky130, 50 MHz, on-chip BW)\n"
                 "event-driven sparse MVM; memory-bound (kernel AI < ridge)",
                 fontsize=11)
    ax.grid(True, which="both", ls=":", alpha=0.4)

    out_dir = os.path.join(os.path.dirname(__file__), "benchmarks")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "roofline_plot.png")
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    print(f"Wrote {out_path}")
    print(f"  ridge point        = {RIDGE:.2f} SynOp/byte")
    print(f"  analytic AI bounds = [{AI_LOWER}, {AI_UPPER}] SynOp/byte")
    print(f"  measured perf      = {MEASURED_PERF:.3f} GSynOps/s")
    print(f"  back-computed AI   = {AI_EFF:.3f} SynOp/byte (>= measured/peak_BW)")
    print(f"  -> measurement tightens AI to [{AI_EFF:.2f}, {AI_UPPER}]; no-reuse bound ruled out")


if __name__ == "__main__":
    main()
