# ECE 410/510 HW4AI — Spring 2026
Andrew Stanton

## Milestone 4 (final submission)

This repository contains the complete M4 deliverable package for the
event-driven SNN accelerator project: an RTL implementation of a recurrent
Leaky Integrate-and-Fire (LIF) spiking neural network accelerator for
Spiking Heidelberg Digits (SHD) audio classification, synthesized on sky130
using OpenLane 2.

**M4 deliverables:** [`project/m4/`](project/m4/)

**Design justification report:** [`project/m4/report/design_justification.pdf`](project/m4/report/design_justification.pdf)
(LaTeX source: [`project/m4/report/design_justification.tex`](project/m4/report/design_justification.tex))

### Quick summary

| Metric | Software (CPU) | Hardware (50 MHz, 10% sparsity) |
|---|---|---|
| Latency | 9.13 ms/sample | 1.506 ms/sample |
| Throughput | 109.5 samples/sec | 664 samples/sec |
| Memory | 1397 MB RSS | ~43 KB on-chip |
| Energy/inference | ~593 mJ (rough) | 0.223 mJ |

Speedup: **6.1×** latency / throughput at the nominal operating point.

### Repository layout

```
project/
├── m1/          — software profiling (PyTorch SHD SNN baseline)
├── m2/          — RTL modules, cocotb testbenches, precision analysis
├── m3/          — top-level integration, cosimulation, synthesis
└── m4/          — final deliverable package (this submission)
    ├── README.md         (file catalog)
    ├── rtl/              (final RTL: top.sv, compute_core.sv, interface.sv)
    ├── tb/               (final testbench: tb_top.sv)
    ├── sim/              (final_run.log PASS 3/3, final_waveform.png)
    ├── synth/            (config.json, timing, area, power reports)
    ├── bench/            (benchmark.md, benchmark_data.csv, roofline_final.png)
    └── report/           (design_justification.pdf, figures/)
```
