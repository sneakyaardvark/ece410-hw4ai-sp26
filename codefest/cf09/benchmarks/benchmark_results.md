# CF09 CLLM — Software baseline vs. hardware accelerator benchmark

Benchmark of the SHD recurrent-LIF SNN: PyTorch software baseline (`shd_snn`,
task 6) vs. the event-driven RTL accelerator (`project/m3`, `compute_core`,
task 7). Speedup and energy efficiency in task 8.

Configuration: `NB_HIDDEN=200`, `NB_STEPS=100`, INT8 weights — identical
workload on both sides.

## Method

- **Software (task 6):** `python -m shd_snn.profile --model-path model.pt`, CPU
  (torch 2.11.0+cpu, same machine class as M1). Median of 10 single-sample
  (`batch=1`) wall-clock runs; peak RSS via `resource.getrusage`.
- **Hardware (task 7) — MEASURED:** cocotb co-simulation of `compute_core` on
  Icarus Verilog 12.0 (`project/m3/tb`, `make bench`). Latency = measured
  `start`→`done` clock cycles × 20 ns synthesized clock period (50 MHz,
  `synth/config.json` `CLOCK_PERIOD`). The 200×200 INT8 weight matrix is loaded
  through the `weight_wr` port; the 40 000-write SPI path is one-time setup and
  excluded from the compute-latency measurement. This is the *measured* path —
  the projected-throughput fallback in task 7 was not needed.

## Headline comparison (task 8)

| Metric | Software (CPU) | Hardware @ 50 MHz (measured) | Improvement |
|---|---|---|---|
| Execution time | 9.13 ms / sample | 1.506 ms @ 10% sparsity | **6.1× faster** |
| Throughput | 109.5 samples/sec | 664 samples/sec @ 10% sparsity | **6.1×** |
| Memory | 1397 MB peak RSS¹ | ~43 KB on-chip² | ~3×10⁴× smaller |
| Energy / inference | ~593 mJ (rough)³ | **0.223 mJ** (from synth power)⁴ | **~2660× (rough)** |

¹ Process-wide RSS, dominated by the profiler pre-materializing 8 dense input
batches (~575 MB) + the HDF5 test set. The model itself (`model.pt`) is 738 KB.
² 40 KB weight SRAM (8 banks × 5000 × 8-bit, holding the 200×200 INT8 v1 matrix)
+ 22 325 DFFs ≈ 2.8 KB of state registers. From `synth/area_report.txt`.
³ **Rough, NOT measured.** Estimated as a 65 W CPU package × 9.13 ms; no RAPL/
wall-meter measurement was taken. Order-of-magnitude only.
⁴ HW power 148.06 mW total (pre-PNR, TT corner, `synth/power_report.txt`);
energy = power × measured latency. Labeled pre-PNR.

## Latency is data-dependent (event-driven)

The accelerator visits only neurons that fired in the previous step, so latency
scales with spike activity. Measured threshold sweep (`make bench`):

| Spike regime | Mean active/step | Cycles | Latency | Throughput | Energy/inf⁴ |
|---|---|---|---|---|---|
| Quiet (activity collapses) | ~1 | 28 278 | 0.57 ms | 1768 /s | 0.084 mJ |
| Active (threshold=200) | ~30 | 99 703 | 1.99 ms | 502 /s | 0.295 mJ |
| Active (threshold=10) | ~41 | 127 053 | 2.54 ms | 394 /s | 0.376 mJ |

Closed-form cycle count: `cycles = 25 302 + 25 × Σ_steps max(1, active)`.

| Operating point | Cycles | Latency | Throughput | Energy/inf⁴ |
|---|---|---|---|---|
| Floor (0 active) | 27 802 | 0.556 ms | 1799 /s | 0.082 mJ |
| **cf09 nominal (10% → 20 active)** | **75 302** | **1.506 ms** | **664 /s** | **0.223 mJ** |
| Ceiling (all 200 active) | 525 302 | 10.51 ms | 95 /s | 1.556 mJ |

The cf09-nominal row uses the 10%-sparsity assumption from `cman_ai_analysis.md`
(20 of 200 neurons active per step). With the synthetic random-weight stimulus
the recurrent dynamics are **bistable** — activity either dies out (~1 neuron)
or settles into the active regime (~30 neurons); there is no stable 10% fixed
point, so the nominal row is the closed-form value at 10% rather than a directly
measured one. A real trained SHD workload would set its own activity profile.

## Speedup summary (task 8)

Throughput ratio (HW / SW), against 9.13 ms / 109.5 samples/sec software:

- cf09 10% operating point (1.506 ms): **6.1×**
- Measured active regime (1.99 ms): **4.6×**
- Quiet regime (0.57 ms): **16×**

Energy efficiency (HW from synthesis power; SW rough TDP estimate): **~2660×**
at the 10% point — driven mostly by the CPU's huge fixed power draw vs. a
148 mW ASIC, not just the 6× latency win. SW figure is an estimate, not a
measurement; treat the energy ratio as order-of-magnitude.

## Reproduce

```bash
# Software baseline (task 6)
cd project && .venv/bin/python -m shd_snn.profile --model-path model.pt

# Hardware latency benchmark (task 7)
cd project/m3/tb && make bench
```
