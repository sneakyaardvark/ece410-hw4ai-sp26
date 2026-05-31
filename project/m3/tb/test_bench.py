"""cocotb latency benchmark for the event-driven compute_core.

Drives compute_core directly (no SPI), loading the 200x200 INT8 weight matrix
through the weight_wr port, then measures the start->done compute latency in
clock cycles for a full NB_STEPS=100 inference. Because the datapath is
event-driven (MAC work scales with the number of neurons that fired in the
previous step), latency is data-dependent. We sweep the spike threshold to
characterise the activity-vs-latency relationship and locate a realistic
(~10% activity) operating point.

Clock period is 20 ns (50 MHz), matching synth/config.json CLOCK_PERIOD.
"""

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

NB        = 200
CLK_NS    = 20            # 50 MHz, matches synthesized clock period
ALPHA_Q   = 19875
BETA_Q    = 29635


async def reset(dut):
    dut.rst.value          = 1
    dut.weight_wr_en.value = 0
    dut.weight_wr_addr.value = 0
    dut.weight_wr_data.value = 0
    dut.start.value        = 0
    dut.spike_in.value     = 0
    dut.alpha.value        = ALPHA_Q
    dut.beta.value         = BETA_Q
    dut.threshold.value    = 32768
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def load_weights(dut, weights_flat):
    """Stream the NB*NB INT8 weight matrix one byte per clock via weight_wr.

    byte_addr = in*NB + out  (matches compute_core bank/word decoding).
    """
    dut.weight_wr_en.value = 1
    for addr, byte_val in enumerate(weights_flat):
        dut.weight_wr_addr.value = addr
        dut.weight_wr_data.value = int(byte_val) & 0xFF
        await RisingEdge(dut.clk)
    dut.weight_wr_en.value = 0
    await RisingEdge(dut.clk)


async def run_inference(dut, spike_in_bits, threshold):
    """Pulse start, count clock cycles until done. Returns cycle count."""
    dut.threshold.value = threshold

    sv = 0
    for i, b in enumerate(spike_in_bits):
        if b:
            sv |= (1 << i)
    dut.spike_in.value = sv

    # Pulse start for one cycle (sampled in S_IDLE)
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    cycles = 1   # the cycle in which start was consumed (S_IDLE -> busy)
    while True:
        await RisingEdge(dut.clk)
        cycles += 1
        if dut.done.value == 1:
            break
    return cycles


@cocotb.test()
async def bench_latency(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await reset(dut)

    rng = np.random.default_rng(42)
    # Signed INT8 weights. Magnitude chosen so the recurrent membrane reaches
    # the threshold range we sweep, letting us map activity -> latency.
    weights = rng.integers(-50, 51, NB * NB, dtype=np.int8)
    await load_weights(dut, [int(w) & 0xFF for w in weights])

    # ~10% initial spike density (20 of 200 neurons), fixed across the sweep.
    spike_in = np.zeros(NB, dtype=int)
    spike_in[rng.choice(NB, size=20, replace=False)] = 1
    spike_in = spike_in.tolist()

    # Sweep threshold: high threshold -> sparse spiking -> low latency;
    # low threshold -> dense spiking -> high latency. The membrane settles to
    # roughly a few thousand for this weight scale, so the spiking transition
    # lives in the low-thousands range.
    thresholds = [100000, 10000, 5000, 3000, 2000, 1000, 500, 200, 100, 10]

    dut._log.info("=" * 64)
    dut._log.info("compute_core latency benchmark  (NB_HIDDEN=200, NB_STEPS=100)")
    dut._log.info("clock period = %d ns (%.0f MHz)", CLK_NS, 1000.0 / CLK_NS)
    dut._log.info("=" * 64)
    dut._log.info("%12s %10s %12s %14s %12s",
                  "threshold", "cycles", "time_us", "mean_active", "samples/s")

    results = []
    for thr in thresholds:
        await reset(dut)
        # reload weights after reset (state regs cleared, SRAM persists in
        # behavioural model, but reset does not touch SRAM -> still loaded).
        cycles = await run_inference(dut, spike_in, thr)
        time_us = cycles * CLK_NS / 1000.0
        # Back-compute mean per-step active count from the cycle total:
        # cycles ~= overhead(=~25301) + 25 * sum_over_steps(active).
        mean_active = max(0.0, (cycles - 25301) / 2500.0)
        sps = 1.0 / (cycles * CLK_NS * 1e-9)
        dut._log.info("%12d %10d %12.2f %14.1f %12.1f",
                      thr, cycles, time_us, mean_active, sps)
        results.append((thr, cycles, time_us, mean_active, sps))

    dut._log.info("=" * 64)
    # Report the operating point closest to ~10% activity (20 neurons).
    best = min(results, key=lambda r: abs(r[3] - 20.0))
    dut._log.info("Operating point closest to ~10%% activity (20 neurons):")
    dut._log.info("  threshold   = %d", best[0])
    dut._log.info("  cycles      = %d", best[1])
    dut._log.info("  latency     = %.3f ms", best[2] / 1000.0)
    dut._log.info("  throughput  = %.1f samples/sec", best[4])
    dut._log.info("=" * 64)
