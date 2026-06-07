# Milestone 4 — File Catalog

Event-driven recurrent LIF SNN accelerator for SHD audio classification.
All files below are relative to `project/m4/`.

## Source code

| File | Description | Checklist item |
|---|---|---|
| `rtl/top.sv` | Top-level module: wraps `spi_interface` and `compute_core`; unchanged from M3 | §2 Source code |
| `rtl/compute_core.sv` | Event-driven FSM + 8×INT8 MAC array + SRAM banks; unchanged from M2 | §2 Source code |
| `rtl/interface.sv` | SPI Mode 0 slave (`spi_interface`) with 2-stage synchronizer; unchanged from M2 | §2 Source code |

The M4 RTL is identical to M3/M2 — no changes were made between milestones.
The versions committed here are the exact sources that produced the synthesis
and benchmark numbers in this package.

## Testbenches

| File | Description | Checklist item |
|---|---|---|
| `tb/tb_top.sv` | Top-level SV wrapper for cocotb (`test_top.py`); same as M3 | §2 Testbench |

The full test suite (including `test_bench.py` benchmark harness) lives in
`project/m3/tb/`. Run `make` (top target) or `make bench` from that directory.

## Simulation outputs

| File | Description | Checklist item |
|---|---|---|
| `sim/final_run.log` | cocotb log for `test_top`: TESTS=3 PASS=3 FAIL=0 | §2 Sim log |
| `sim/final_waveform.png` | Annotated waveform: SPI weight load, BUSY, DONE pulse | §2 Waveform |

## Synthesis results (OpenLane 2, sky130)

| File | Description | Checklist item |
|---|---|---|
| `synth/config.json` | OpenLane 2 config used for synthesis (CLOCK_PERIOD=20ns, sky130 HD) | §3 Config |
| `synth/openlane_run.log` | OpenLane stdout/stderr from the M3 synthesis run | §3 Run log |
| `synth/timing_report.txt` | Trimmed STA report (full 145 MB report at `m3/synth/timing_report.txt.gz`); WNS = −1653 ns (reset-tree artifact; see §7 of report) | §3 Timing |
| `synth/area_report.txt` | Cell counts: 1,261,907 cells, 22,325 DFFs, 40 SRAM macros; chip area 12,475,476 µm² | §3 Area |
| `synth/power_report.txt` | Total 148.06 mW (TT 25°C 1.8V): SRAM 51.2%, sequential 38.1%, comb 10.7% | §3 Power |

## Benchmark

| File | Description | Checklist item |
|---|---|---|
| `bench/benchmark.md` | HW vs SW headline table, speedup, energy, activity-dependent analysis | §4 Benchmark |
| `bench/benchmark_data.csv` | Raw measurements: threshold sweep cycle counts, synth numbers, AI values | §4 Raw data |
| `bench/roofline_final.png` | Log-log roofline: HW measured point + SW baseline point | §4 Roofline |
| `bench/plot_roofline_final.py` | Script that generates `roofline_final.png` | (reproducibility) |

## Design justification report

| File | Description | Checklist item |
|---|---|---|
| `report/design_justification.tex` | LaTeX source for the 9-section report | §5 Report |
| `report/design_justification.pdf` | Compiled PDF (compile with `pdflatex design_justification.tex`) | §5 Report |
| `report/figures/roofline_final.png` | Roofline figure referenced in report §2 | §5 Figures |
| `report/figures/final_waveform.png` | Waveform figure referenced in report §4, §6 | §5 Figures |
