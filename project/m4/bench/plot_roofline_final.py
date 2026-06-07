"""M4 final roofline plot.

Same as CF09 but adds a software baseline point for direct comparison.

SW baseline (M1 profiling):
  - 9.13 ms/sample, 109.5 samples/sec
  - SynOps/inference = 400,000  (same workload)
  - Throughput = 400,000 / 9.13e-3 = 0.0438 GSynOps/s
  - AI: same algorithm, same data access pattern → AI lower bound 0.45 SynOp/byte
    (no weight reuse; placed at the same lower-bound AI as the HW design for
    apples-to-apples comparison on the same roofline axes)
"""

import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

PEAK_COMPUTE = 0.40
PEAK_BW      = 0.40
RIDGE        = PEAK_COMPUTE / PEAK_BW   # 1.0

AI_LOWER = 0.45
AI_UPPER = 0.83

SYNOPS_PER_INF = 100 * 20 * 200
LATENCY_HW_S   = 75302 * 20e-9
MEASURED_PERF  = (SYNOPS_PER_INF / LATENCY_HW_S) / 1e9   # 0.266 GSynOps/s
AI_EFF         = MEASURED_PERF / PEAK_BW                  # 0.664

LATENCY_SW_S   = 9.13e-3
SW_PERF        = (SYNOPS_PER_INF / LATENCY_SW_S) / 1e9    # 0.0438 GSynOps/s
AI_SW          = AI_LOWER                                   # conservative, same algorithm


def roofline(ai):
    return np.minimum(PEAK_COMPUTE, PEAK_BW * ai)


def main():
    fig, ax = plt.subplots(figsize=(8, 6))

    ai = np.logspace(-1, 2, 500)
    ax.plot(ai, roofline(ai), color="#1f4e79", lw=2.5, zorder=3)

    ax.axhline(PEAK_COMPUTE, color="#1f4e79", ls=":", lw=1, alpha=0.6)
    ax.text(40, PEAK_COMPUTE * 1.08,
            f"compute ceiling = {PEAK_COMPUTE:.2f} GSynOps/s\n(8 MACs × 50 MHz)",
            color="#1f4e79", ha="right", va="bottom", fontsize=9)
    ax.text(0.115, roofline(0.115) * 1.1,
            f"BW ceiling\n(slope = {PEAK_BW:.2f} GB/s)",
            color="#1f4e79", ha="left", va="bottom", fontsize=9, rotation=33,
            rotation_mode="anchor")

    ax.plot([RIDGE], [PEAK_COMPUTE], "o", color="#1f4e79", ms=8, zorder=5)
    ax.annotate(f"ridge ({RIDGE:.1f} SynOp/byte)",
                xy=(RIDGE, PEAK_COMPUTE), xytext=(RIDGE * 1.5, PEAK_COMPUTE * 0.55),
                fontsize=9, color="#1f4e79",
                arrowprops=dict(arrowstyle="->", color="#1f4e79"))

    for x, label in [(AI_LOWER, f"AI lower\n(no reuse)\n{AI_LOWER}"),
                     (AI_UPPER, f"AI upper\n(full reuse)\n{AI_UPPER}")]:
        ax.axvline(x, color="#888888", ls="--", lw=1, zorder=2)
        ax.text(x, 0.011, label, ha="center", va="bottom", fontsize=8, color="#555555")

    ax.axvspan(AI_EFF, AI_UPPER, color="#ffd9b3", alpha=0.45, zorder=0)

    # SW baseline point (M1)
    ax.plot([AI_SW], [SW_PERF], "^", color="#2ca02c", ms=11, zorder=7)
    ax.annotate(f"SW baseline (M1)\n{SW_PERF:.4f} GSynOps/s\n9.13 ms/sample",
                xy=(AI_SW, SW_PERF),
                xytext=(0.15, SW_PERF * 6),
                fontsize=9, color="#2ca02c", fontweight="bold",
                arrowprops=dict(arrowstyle="->", color="#2ca02c"))

    # HW measured point
    ax.plot([AI_EFF], [MEASURED_PERF], "D", color="#c00000", ms=11, zorder=7)
    ax.annotate(f"HW accelerator (M4)\n{MEASURED_PERF:.3f} GSynOps/s\n"
                f"AI_eff = {AI_EFF:.2f}  1.506 ms/inf",
                xy=(AI_EFF, MEASURED_PERF),
                xytext=(1.3, MEASURED_PERF * 0.28),
                fontsize=9, color="#c00000", fontweight="bold",
                arrowprops=dict(arrowstyle="->", color="#c00000"))

    # Speedup annotation
    ax.annotate("", xy=(AI_EFF, MEASURED_PERF), xytext=(AI_SW, SW_PERF),
                arrowprops=dict(arrowstyle="->", color="#888888", lw=1.5,
                                linestyle="dashed"))
    ax.text(0.52, 0.075, "6.1× speedup", fontsize=9, color="#555555",
            ha="center", va="center", rotation=35)

    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlim(0.1, 100)
    ax.set_ylim(0.01, 1.0)
    ax.set_xlabel("Arithmetic intensity (SynOps/byte)", fontsize=11)
    ax.set_ylabel("Attainable performance (GSynOps/s)", fontsize=11)
    ax.set_title("M4 Roofline — SNN accelerator vs. SW baseline\n"
                 "(sky130 ASIC, 50 MHz, on-chip BW; event-driven sparse MVM)",
                 fontsize=11)
    ax.grid(True, which="both", ls=":", alpha=0.4)

    out_dir = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(out_dir, "roofline_final.png")
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()
