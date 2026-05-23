"""Parse tb_top_wave.vcd and write an annotated waveform PNG.

Usage (from project/m3/tb/):
    python plot_wave.py [--vcd tb_top_wave.vcd] [--out ../../sim/cosim_waveform.png]

Annotates three phases visible in the NB=8 waveform:
  1. SPI Write  — cs_n low bursts while busy=0 (weight + spike_in loading)
  2. Compute    — busy=1 from start pulse to done pulse
  3. SPI Read   — cs_n low bursts after busy returns to 0 (STATUS + spike_out)
"""

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.patches as mpatches
import matplotlib.pyplot as plt
import numpy as np


# ---------------------------------------------------------------------------
# Minimal VCD parser
# ---------------------------------------------------------------------------

def parse_vcd(path: str):
    """Return (timescale_ns, signals, changes).

    signals  : dict  id_char -> signal_name
    changes  : dict  id_char -> list of (time_ns, int_value)
    Only scalar (1-bit) signals are tracked.
    """
    timescale_ns = 1.0
    signals: dict[str, str] = {}
    changes: dict[str, list] = defaultdict(list)

    ts_re   = re.compile(r"\$timescale\s+([\d.]+)\s*(ns|ps|us)\s*\$end")
    var_re  = re.compile(r"\$var\s+\w+\s+1\s+(\S+)\s+(\w+)\s*(?:\[\d+\])?\s*\$end")
    time_re = re.compile(r"^#(\d+)$")
    val_re  = re.compile(r"^([01xzXZ])(\S+)$")

    current_time = 0
    with open(path) as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue

            m = ts_re.search(line)
            if m:
                val, unit = float(m.group(1)), m.group(2)
                timescale_ns = val if unit == "ns" else (val / 1000 if unit == "ps" else val * 1000)
                continue

            m = var_re.search(line)
            if m:
                sig_id, sig_name = m.group(1), m.group(2)
                signals[sig_id] = sig_name
                continue

            m = time_re.match(line)
            if m:
                current_time = int(m.group(1)) * timescale_ns
                continue

            m = val_re.match(line)
            if m:
                val_char, sig_id = m.group(1), m.group(2)
                if sig_id in signals:
                    v = 0 if val_char in ("0", "x", "X", "z", "Z") else 1
                    changes[sig_id].append((current_time, v))

    return timescale_ns, signals, changes


def build_wave(changes, end_time):
    """Convert change list to (times, values) step arrays."""
    if not changes:
        return np.array([0, end_time]), np.array([0, 0])
    times  = [t for t, _ in changes]
    values = [v for _, v in changes]
    times.append(end_time)
    values.append(values[-1])
    return np.array(times, dtype=float), np.array(values, dtype=float)


# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------

SIGNALS_ORDERED = ["cs_n", "sck", "mosi", "miso", "busy", "done"]
COLORS = {
    "spi_write": "#3B82F6",   # blue
    "compute":   "#F97316",   # orange
    "spi_read":  "#22C55E",   # green
}

SIGNAL_COLORS = {
    "cs_n": "#64748B",
    "sck":  "#64748B",
    "mosi": "#7C3AED",
    "miso": "#0EA5E9",
    "busy": "#F97316",
    "done": "#22C55E",
}


def detect_phases(name_to_changes, end_time):
    """Return (spi_write_end, compute_start, compute_end, spi_read_start).

    Strategy:
    - compute_start : first time busy rises to 1
    - compute_end   : first time busy falls to 0 after compute_start
    - spi_write_end : last cs_n falling edge before compute_start
    - spi_read_start: first cs_n falling edge after compute_end
    """
    busy_ch = name_to_changes.get("busy", [])
    cs_ch   = name_to_changes.get("cs_n", [])

    compute_start = compute_end = spi_write_end = spi_read_start = None

    for t, v in busy_ch:
        if v == 1 and compute_start is None:
            compute_start = t
        if v == 0 and compute_start is not None and compute_end is None:
            compute_end = t

    if compute_start is not None:
        for t, v in reversed(cs_ch):
            if t < compute_start and v == 0:
                spi_write_end = t
                break

    if compute_end is not None:
        for t, v in cs_ch:
            if t > compute_end and v == 0:
                spi_read_start = t
                break

    return spi_write_end, compute_start, compute_end, spi_read_start


def draw_signal(ax, times, values, y_base, height=0.7, color="#64748B"):
    """Draw a digital waveform as a filled step polygon."""
    t_step = np.repeat(times, 2)[1:]
    v_step = np.repeat(values, 2)[:-1]
    y = y_base + v_step * height
    ax.step(t_step, y, where="post", color=color, linewidth=1.2)
    ax.fill_between(t_step, y_base, y, step="post",
                    color=color, alpha=0.25)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vcd", default="tb_top_wave.vcd")
    ap.add_argument("--out", default="../sim/cosim_waveform.png")
    args = ap.parse_args()

    vcd_path = Path(args.vcd)
    if not vcd_path.exists():
        sys.exit(f"VCD not found: {vcd_path}. Run `make wave` first.")

    print(f"Parsing {vcd_path} …")
    _ts, signals, changes = parse_vcd(str(vcd_path))

    # Build name→changes map
    name_to_changes: dict[str, list] = {}
    for sig_id, name in signals.items():
        name_to_changes[name] = changes[sig_id]

    end_time = max(
        (ch[-1][0] for ch in name_to_changes.values() if ch),
        default=1000.0
    )

    spi_write_end, compute_start, compute_end, spi_read_start = detect_phases(
        name_to_changes, end_time)

    # Build per-signal step arrays
    waves = {}
    for name in SIGNALS_ORDERED:
        ch = name_to_changes.get(name, [(0, 0)])
        waves[name] = build_wave(ch, end_time)

    # -----------------------------------------------------------------------
    # Plot
    # -----------------------------------------------------------------------
    n_sig = len(SIGNALS_ORDERED)
    fig, ax = plt.subplots(figsize=(14, 5))

    gap   = 1.2
    h_sig = 0.8

    for i, name in enumerate(SIGNALS_ORDERED):
        y_base = (n_sig - 1 - i) * gap
        t, v = waves[name]
        draw_signal(ax, t, v, y_base, height=h_sig,
                    color=SIGNAL_COLORS.get(name, "#64748B"))
        ax.text(-end_time * 0.015, y_base + h_sig / 2, name,
                ha="right", va="center", fontsize=9,
                fontfamily="monospace", color=SIGNAL_COLORS.get(name, "#333"))

    y_top    = n_sig * gap
    y_bottom = -0.2

    def shade(x0, x1, label, color, label_y=None):
        if x0 is None or x1 is None:
            return
        ax.axvspan(x0, x1, alpha=0.08, color=color, zorder=0)
        ax.axvline(x0, color=color, linewidth=0.8, linestyle="--", alpha=0.6)
        ax.axvline(x1, color=color, linewidth=0.8, linestyle="--", alpha=0.6)
        lx = (x0 + x1) / 2
        ly = label_y if label_y else y_top - 0.15
        ax.text(lx, ly, label, ha="center", va="top", fontsize=9,
                color=color, fontweight="bold")

    shade(0,              spi_write_end,  "① SPI Write\n(weights + spike_in)",
          COLORS["spi_write"], y_top - 0.05)
    shade(compute_start,  compute_end,    "② Compute\n(busy=1)",
          COLORS["compute"],   y_top - 0.05)
    shade(spi_read_start, end_time,       "③ SPI Read\n(STATUS + spike_out)",
          COLORS["spi_read"],  y_top - 0.05)

    ax.set_xlim(-end_time * 0.02, end_time * 1.02)
    ax.set_ylim(y_bottom, y_top + 0.2)
    ax.set_xlabel("Simulation time (ns)", fontsize=10)
    ax.set_title(
        "tb_top_wave co-simulation waveform  —  NB_HIDDEN=8, NB_MACS=8, NB_STEPS=2\n"
        "Integrated top: spi_interface + compute_core (Icarus Verilog 12.0 / cocotb 2.0.1)",
        fontsize=10,
    )
    ax.set_yticks([])

    patches = [
        mpatches.Patch(color=COLORS["spi_write"], alpha=0.5, label="① SPI Write"),
        mpatches.Patch(color=COLORS["compute"],   alpha=0.5, label="② Compute (busy=1)"),
        mpatches.Patch(color=COLORS["spi_read"],  alpha=0.5, label="③ SPI Read"),
    ]
    ax.legend(handles=patches, loc="upper left", fontsize=8)

    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["left"].set_visible(False)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out_path, dpi=150, bbox_inches="tight")
    print(f"Saved: {out_path}")


if __name__ == "__main__":
    main()
