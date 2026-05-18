# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ECE 410 homework assignment repository combining AI/ML (PyTorch) with hardware design (Verilog).

## Development Environment

This project uses **Nix Flakes** for reproducible development environments with direnv integration.

```bash
# Enter development environment (automatically loads via direnv)
direnv allow

# Or manually enter the shell
nix develop
```

### Available Tools

- **Python 3.13** with torch, torchvision, pip
- **iverilog** for Verilog simulation

### Update Dependencies

```bash
nix flake update
```

## Build & Run Commands

No traditional build system is configured yet. Use tools directly:

```bash
# Python/PyTorch
python script.py

# Verilog simulation
iverilog -o output design.v testbench.v
vvp output

# cocotb testbenches (project/m2/tb/)
make MODULE=tb_compute_core sim
make MODULE=tb_interface sim
make precision_sweep        # quantization error sweep

# Presentation figures (project/presentation/)
python plot_lif.py          # LIF neuron diagram (runs iverilog internally)
python plot_arch.py         # architecture block diagram
```

## Project Design

**Algorithm / Workload:** Spiking Neural Network (SNN) for Spiking Heidelberg Digits (SHD) audio classification. Recurrent LIF network, 200 neurons.

**Key numeric formats:**
- Weights: INT8
- Decay constants alpha, beta: Q1.15 unsigned (16-bit); alpha≈0.606 (19875), beta≈0.904 (29635)
- Synaptic/membrane state: INT32
- Spike threshold: INT32 = 32768

**RTL modules (`project/m2/rtl/`):**
- `snn_lif_cell.sv` — single LIF neuron; recurrence: `new_syn = (alpha*syn>>15) + h1_in`, `spike = (mem >= threshold)`, `new_mem = spike ? 0 : (beta*mem>>15) + syn`
- `compute_core.sv` — MAC array, 8× INT8 MACs tiled 25× over 200-neuron weight matrix
- `interface.sv` — SPI Mode 0 slave (`spi_interface`); 2-stage synchronizer, single `always_ff` block

**Testbenches (`project/m2/tb/`):**
- cocotb 2.0.1 on Icarus Verilog 12.0
- `tb_interface.py` — 7/7 PASS
- `tb_compute_core.py` — 5/5 PASS
- `test_precision_sweep.py` — quantization error sweep across weight/state bit-widths

**Simulation logs:** `project/m2/sim/` — all logs force-added past `*.log` gitignore (grader requires build artifacts committed).

**Known iverilog quirks:**
- Use `integer` (not `int`) loop variables in tasks for compatibility
- Drive signals on `negedge clk` to avoid same-edge scheduling ambiguity with `always_ff`
- Array aggregate initialization (`'{...}`) not supported; use element-by-element assignment

## Project Status

**M2 — complete** (commit `fab5979`). Deliverables: RTL modules, cocotb testbenches, simulation logs, annotated waveform PNG, `precision.md`, `README.md`, presentation figures.

**Latency gap (known issue):** Hardware estimated ~45 ms (8 MACs × 50 MHz → 400 M ops/sec over 200-neuron × 25-tile × 40-step computation); software median 7.74 ms. Root cause: bandwidth mismatch vs CPU. Planned fix: replace INT8 MAC array with conditional accumulators (mux + adder, LUT-based) exploiting spike sparsity (~10% activity → ~0.6 ms projected).

**M3 (next):** Load trained SHD weights into RTL, measure end-to-end classification accuracy.
