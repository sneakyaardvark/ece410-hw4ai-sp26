# M4 Benchmark: Hardware Accelerator vs. Software Baseline

Design: event-driven recurrent LIF SNN, 200 neurons, INT8 weights, 100 timesteps.
Workload: SHD audio classification, single-sample inference, NB_HIDDEN=200, NB_STEPS=100.

## Method

**Software baseline (M1):** `python -m shd_snn.profile --model-path model.pt`,
CPU (torch 2.11.0+cpu). Median of 10 single-sample (`batch=1`) wall-clock
runs; peak RSS via `resource.getrusage`.

**Hardware (M4):** cocotb co-simulation of `compute_core` on Icarus Verilog 12.0
(`project/m3/tb`, `make bench`). Latency = measured `start`→`done` clock
cycles × 20 ns clock period (50 MHz from `synth/config.json CLOCK_PERIOD`).
The 200×200 INT8 weight matrix is loaded through the direct `weight_wr` port
(not SPI, which would require ~900 real-seconds of simulation). The 40,000-cycle
weight-load phase is one-time setup and excluded from compute-latency
measurement. Raw cycle counts in `bench/benchmark_data.csv`.

## Headline comparison

| Metric | Software (CPU) | Hardware (measured) | Improvement |
|---|---|---|---|
| Execution time | 9.13 ms/sample | 1.506 ms @ 10% sparsity | **6.1× faster** |
| Throughput | 109.5 samples/sec | 664 samples/sec | **6.1×** |
| Memory | 1397 MB peak RSS¹ | ~43 KB on-chip² | ~3×10⁴× smaller |
| Energy/inference | ~593 mJ (rough)³ | 0.223 mJ (from synth)⁴ | **~2660× (rough)** |

¹ Process-wide RSS dominated by the profiler pre-materializing input batches + HDF5
test set; the model itself is 738 KB.
² 40 KB weight SRAM (8 banks × 5 tiles × 1 KB) + 22,325 DFFs ≈ 2.8 KB registers.
³ **Not measured.** Rough estimate: 65 W CPU TDP × 9.13 ms. Order-of-magnitude only.
⁴ 148.06 mW total (pre-PNR, TT corner, `synth/power_report.txt`) × 1.506 ms.

## Speedup detail

Speedup = M1 baseline time / M4 accelerator time, against 9.13 ms SW.

| Operating point | Cycles | Latency | Throughput | Speedup vs SW |
|---|---|---|---|---|
| Floor (0 active) | 27,802 | 0.556 ms | 1799/s | 16.4× |
| **10% sparsity (nominal, 20 active)** | **75,302** | **1.506 ms** | **664/s** | **6.1×** |
| Measured active (~30/step) | 99,703 | 1.99 ms | 502/s | 4.6× |
| Ceiling (200 active) | 525,302 | 10.51 ms | 95/s | 0.87× (slower) |

Closed-form: `cycles = 25,302 + 25 × Σ_steps max(1, active_count)`.

**Activity-dependent performance.** The accelerator is event-driven; it only
processes neurons that fired in the previous step. At the ceiling (all 200 neurons
active), it is slightly *slower* than software because the hardware overhead of the
SRAM FSM phases exceeds the software's dense-matrix efficiency. The break-even is
near 190 active neurons per step. The design excels in the sparse regime expected
of biological SNNs (~5–20% activity).

**Energy.** The ~2660× energy improvement is dominated by the ASIC's 148 mW fixed
power versus the CPU's ~65 W TDP. SW energy is a rough TDP estimate, not measured.
Even with a 10× overestimate of SW idle power, the HW advantage exceeds 200×.

## Reproduce

```bash
# Software baseline
cd project && .venv/bin/python -m shd_snn.profile --model-path model.pt

# Hardware latency (threshold sweep + cycle count)
cd project/m3/tb && make bench
```

Raw numbers: `bench/benchmark_data.csv`.
Roofline: `bench/roofline_final.png` (see also `report/design_justification.pdf` §8).
