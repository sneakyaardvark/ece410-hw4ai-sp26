"""cocotb testbench for snn_mac_array (via tb_snn_mac_array wrapper).

Tests:
  - reset clears all 8 accumulators
  - basic dot product: 8 PEs × N spikes=1, compared against numpy reference
  - spike=0 contributes nothing to any accumulator
  - acc_clear resets all PEs between tile groups
  - simultaneous weight_load + act_valid: new weight takes effect immediately
    (verified by checking spike=[1,0]: only first weight contributes)
  - representative matrix-vector multiply: 8 outputs × 200 inputs (v1 tile size),
    random INT8 weights and binary spike activations, compared against numpy
"""

import numpy as np
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge

N        = 8
WEIGHT_W = 8
ACC_W    = 32


def pack_weights(weights: list[int]) -> int:
    """Pack N signed int8 weights into a single integer (little-endian: w[0] in LSB)."""
    assert len(weights) == N
    val = 0
    for i, w in enumerate(weights):
        val |= (w & 0xFF) << (i * 8)
    return val


def unpack_acc(raw: int) -> list[int]:
    """Unpack 256-bit acc_out into N signed int32 values (little-endian)."""
    out = []
    for i in range(N):
        word = (raw >> (i * 32)) & 0xFFFFFFFF
        if word >= (1 << 31):
            word -= (1 << 32)
        out.append(word)
    return out


async def init(dut):
    """Start clock, drive defaults, apply synchronous reset for 2 cycles."""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())

    dut.rst.value         = 1
    dut.weight_load.value = 0
    dut.weight_in.value   = 0
    dut.acc_clear.value   = 0
    dut.act_valid.value   = 0
    dut.act_in.value      = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def run_matvec(dut, weights_matrix: np.ndarray, spikes: np.ndarray):
    """Stream one tile: weights_matrix[T×N] and spikes[T] (binary), simultaneously.

    Each cycle t: weight_load=1, weight_in=weights_matrix[t], act_valid=1,
    act_in=spikes[t]. The forwarding mux in snn_mac ensures weight_in[t]
    pairs with spikes[t] with no pipeline stall.
    """
    T = len(spikes)
    assert weights_matrix.shape == (T, N)

    dut.weight_load.value = 1
    dut.act_valid.value   = 1
    for t in range(T):
        dut.weight_in.value = int(pack_weights(weights_matrix[t].tolist()))
        dut.act_in.value    = int(spikes[t])
        await RisingEdge(dut.clk)
    dut.weight_load.value = 0
    dut.act_valid.value   = 0
    dut.act_in.value      = 0


async def clear(dut):
    """Assert acc_clear for one cycle."""
    dut.acc_clear.value = 1
    await RisingEdge(dut.clk)
    dut.acc_clear.value = 0


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_reset(dut):
    """After reset all 8 accumulators must read 0."""
    await init(dut)
    await FallingEdge(dut.clk)
    result = unpack_acc(dut.acc_out.value.to_unsigned())
    assert result == [0] * N, f"Expected all zeros after reset, got {result}"


@cocotb.test()
async def test_basic_dot_product(dut):
    """Small known case: weight=3 for all PEs, 4 spikes=1 → acc=12."""
    await init(dut)
    weights = np.full((4, N), 3, dtype=np.int8)
    spikes  = np.ones(4, dtype=np.uint8)
    await run_matvec(dut, weights, spikes)
    await FallingEdge(dut.clk)
    result   = unpack_acc(dut.acc_out.value.to_unsigned())
    expected = [3 * 4] * N  # 12
    assert result == expected, f"Expected {expected}, got {result}"


@cocotb.test()
async def test_spike_zero_no_contribution(dut):
    """Spike=0 must not change any accumulator."""
    await init(dut)
    weights = np.full((4, N), 99, dtype=np.int8)
    spikes  = np.zeros(4, dtype=np.uint8)
    await run_matvec(dut, weights, spikes)
    await FallingEdge(dut.clk)
    result = unpack_acc(dut.acc_out.value.to_unsigned())
    assert result == [0] * N, f"Expected all zeros (no spikes), got {result}"


@cocotb.test()
async def test_acc_clear_between_tiles(dut):
    """Accumulate a tile, clear, accumulate a second tile; only second result remains."""
    await init(dut)
    rng = np.random.default_rng(0)

    # First tile — random weights, ~50% spikes
    w1     = rng.integers(-128, 128, (10, N), dtype=np.int8)
    spikes1 = rng.integers(0, 2, 10, dtype=np.uint8)
    await run_matvec(dut, w1, spikes1)
    await clear(dut)

    # Second tile
    w2     = rng.integers(-128, 128, (6, N), dtype=np.int8)
    spikes2 = rng.integers(0, 2, 6, dtype=np.uint8)
    await run_matvec(dut, w2, spikes2)
    await FallingEdge(dut.clk)

    result   = unpack_acc(dut.acc_out.value.to_unsigned())
    expected = (w2.astype(np.int32) * spikes2.astype(np.int32)[:, None]).sum(axis=0).tolist()
    assert result == expected, f"Expected {expected}, got {result}"


@cocotb.test()
async def test_simultaneous_weight_and_act(dut):
    """Verify weight_in is used immediately when weight_load and act_valid coincide.

    Uses spikes=[1, 0]: only the first weight row contributes. If the forwarding
    mux is absent (stale weight_reg=0 used at t=0), the result would be all zeros.
    """
    await init(dut)
    weights = np.array([[1, 2, 3, 4, 5, 6, 7, 8],
                        [8, 7, 6, 5, 4, 3, 2, 1]], dtype=np.int8)
    spikes  = np.array([1, 0], dtype=np.uint8)   # only first row active
    await run_matvec(dut, weights, spikes)
    await FallingEdge(dut.clk)

    result   = unpack_acc(dut.acc_out.value.to_unsigned())
    expected = [1, 2, 3, 4, 5, 6, 7, 8]   # weights[0] × spike=1
    assert result == expected, f"Expected {expected}, got {result}"


@cocotb.test()
async def test_representative_matvec(dut):
    """Representative v1 tile: 8 outputs × 200 inputs, random INT8 weights,
    binary spike activations (~10% firing rate). Reference from numpy INT32."""
    await init(dut)
    rng = np.random.default_rng(42)

    weights = rng.integers(-128, 128, (200, N), dtype=np.int8)
    spikes  = rng.choice([0, 1], size=200, p=[0.9, 0.1]).astype(np.uint8)

    await run_matvec(dut, weights, spikes)
    await FallingEdge(dut.clk)

    result   = unpack_acc(dut.acc_out.value.to_unsigned())
    expected = (weights.astype(np.int32) * spikes.astype(np.int32)[:, None]).sum(axis=0).tolist()
    assert result == expected, f"Expected {expected}, got {result}"
