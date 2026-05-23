"""cocotb testbench for snn_mac (via tb_snn_mac wrapper).

Tests:
  - reset clears accumulator and weight register
  - spike=1 adds the weight; spike=0 is a no-op
  - acc_clear resets accumulator to zero
  - acc_clear takes priority over act_valid on the same cycle
  - negative INT8 weights produce negative accumulation
  - weight register persists across acc_clear cycles
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge


async def init(dut):
    """Start clock, drive all inputs to 0, apply reset for 2 cycles."""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())  # 50 MHz

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


async def load_weight(dut, weight: int):
    """Assert weight_load for one cycle to latch weight."""
    dut.weight_load.value = 1
    dut.weight_in.value   = weight
    await RisingEdge(dut.clk)
    dut.weight_load.value = 0
    dut.weight_in.value   = 0


async def stream_spikes(dut, spikes: list[int]):
    """Drive act_valid + act_in for each binary spike in sequence."""
    dut.act_valid.value = 1
    for s in spikes:
        dut.act_in.value = s
        await RisingEdge(dut.clk)
    dut.act_valid.value = 0
    dut.act_in.value    = 0


async def clear_acc(dut):
    """Assert acc_clear for one cycle."""
    dut.acc_clear.value = 1
    await RisingEdge(dut.clk)
    dut.acc_clear.value = 0


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_reset(dut):
    """After reset, acc_out must be 0."""
    await init(dut)
    assert dut.acc_out.value.to_signed() == 0, (
        f"Expected 0 after reset, got {dut.acc_out.value.to_signed()}"
    )


@cocotb.test()
async def test_spike_one_accumulates(dut):
    """Spike=1 adds the weight each cycle: weight=5, 4 spikes → acc=20."""
    await init(dut)
    await load_weight(dut, 5)
    await stream_spikes(dut, [1, 1, 1, 1])
    await FallingEdge(dut.clk)
    expected = 5 * 4
    assert dut.acc_out.value.to_signed() == expected, (
        f"Expected {expected}, got {dut.acc_out.value.to_signed()}"
    )


@cocotb.test()
async def test_spike_zero_no_op(dut):
    """Spike=0 must not change the accumulator."""
    await init(dut)
    await load_weight(dut, 99)
    await stream_spikes(dut, [0, 0, 0])
    await FallingEdge(dut.clk)
    assert dut.acc_out.value.to_signed() == 0, (
        f"Expected 0 (no spikes), got {dut.acc_out.value.to_signed()}"
    )


@cocotb.test()
async def test_mixed_spikes(dut):
    """Only spike=1 cycles contribute: weight=7, spikes=[1,0,1,0,1] → acc=21."""
    await init(dut)
    await load_weight(dut, 7)
    await stream_spikes(dut, [1, 0, 1, 0, 1])
    await FallingEdge(dut.clk)
    expected = 7 * 3
    assert dut.acc_out.value.to_signed() == expected, (
        f"Expected {expected}, got {dut.acc_out.value.to_signed()}"
    )


@cocotb.test()
async def test_acc_clear(dut):
    """Accumulate some spikes, clear, then verify acc_out is 0."""
    await init(dut)
    await load_weight(dut, 7)
    await stream_spikes(dut, [1, 1, 1])
    await clear_acc(dut)
    await FallingEdge(dut.clk)
    assert dut.acc_out.value.to_signed() == 0, (
        f"Expected 0 after acc_clear, got {dut.acc_out.value.to_signed()}"
    )


@cocotb.test()
async def test_clear_priority_over_act_valid(dut):
    """When acc_clear and act_valid are both asserted, acc_clear wins."""
    await init(dut)
    await load_weight(dut, 10)
    await stream_spikes(dut, [1, 1, 1, 1])  # acc = 40

    # Assert both simultaneously
    dut.acc_clear.value = 1
    dut.act_valid.value = 1
    dut.act_in.value    = 1
    await RisingEdge(dut.clk)
    dut.acc_clear.value = 0
    dut.act_valid.value = 0

    await FallingEdge(dut.clk)
    assert dut.acc_out.value.to_signed() == 0, (
        f"Expected 0 (clear wins), got {dut.acc_out.value.to_signed()}"
    )


@cocotb.test()
async def test_negative_weight(dut):
    """Negative INT8 weight with spike=1 produces negative accumulation."""
    await init(dut)
    await load_weight(dut, -3)          # 0xFD in int8
    await stream_spikes(dut, [1, 1])
    await FallingEdge(dut.clk)
    expected = -3 * 2
    assert dut.acc_out.value.to_signed() == expected, (
        f"Expected {expected}, got {dut.acc_out.value.to_signed()}"
    )


@cocotb.test()
async def test_weight_held_across_activations(dut):
    """Weight register persists; loading once covers multiple spike streams."""
    await init(dut)
    await load_weight(dut, 4)
    await stream_spikes(dut, [1, 1, 1])   # acc = 12
    await clear_acc(dut)
    # No second weight_load — weight_reg should still hold 4
    await stream_spikes(dut, [1, 1])
    await FallingEdge(dut.clk)
    expected = 4 * 2   # 8
    assert dut.acc_out.value.to_signed() == expected, (
        f"Expected {expected}, got {dut.acc_out.value.to_signed()}"
    )


@cocotb.test()
async def test_max_weight_200_spikes(dut):
    """127 * 200 = 25,400 — well within int32 range."""
    await init(dut)
    await load_weight(dut, 127)
    await stream_spikes(dut, [1] * 200)
    await FallingEdge(dut.clk)
    expected = 127 * 200
    assert dut.acc_out.value.to_signed() == expected, (
        f"Expected {expected}, got {dut.acc_out.value.to_signed()}"
    )
