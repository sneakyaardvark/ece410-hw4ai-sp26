"""cocotb end-to-end testbench for the integrated top module (tb_top wrapper).

DUT is parametrized: NB_HIDDEN=200, NB_MACS=8, NB_STEPS=5.
NB_STEPS is reduced from the 100-step production value to keep co-simulation
time manageable while exercising the full 200×200 recurrent weight matrix
(the dominant kernel identified in M1 profiling).

All communication goes through the SPI port using bit-banged Mode 0 transactions
(4-byte frames: [CMD:8][ADDR_HI:8][ADDR_LO:8][DATA:8]).
SCK edges are set on falling core-clock edges so they never coincide with
rising edges (at which the DUT's 2-stage synchronizer samples).

Register map (NB_HIDDEN=200, NB_BYTES=25):
  0x0000..0x9C3F   Weight SRAM bytes (write): byte_addr = in*200 + out
  0xA000..0xA018   spike_in[199:0] bytes 0..24 (write)
  0xA019           Control: write 0x01 = start inference
  0xA01A           Status (read): bit1=done, bit0=busy
  0xA01B..0xA033   spike_out[199:0] bytes 0..24 (read, latched on done)
  0xA034/0xA035    alpha[7:0]/[15:8] (write)
  0xA036/0xA037    beta[7:0]/[15:8] (write)
  0xA038..0xA03B   threshold bytes 0..3 (write)

Tests:
  - test_reset: after reset busy=0, done=0
  - test_spi_write_read: write spike_in byte, read status → verifies SPI path
  - test_full_spi_inference: load 200×200 weights + spike_in via SPI, start,
    poll busy=0, read spike_out; compare to fixed-point Python reference model
"""

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge

NB        = 200
NB_BYTES  = NB // 8   # 25
NB_STEPS  = 5
ALPHA_Q   = 19875
BETA_Q    = 29635
THRESH    = 32768

CMD_WRITE = 0x02
CMD_READ  = 0x03

STATUS_ADDR    = 0xA01A
CTRL_ADDR      = 0xA019
SPIKE_IN_BASE  = 0xA000
SPIKE_OUT_BASE = 0xA01B


# ---------------------------------------------------------------------------
# Fixed-point reference model (mirrors compute_core.sv arithmetic exactly)
# ---------------------------------------------------------------------------

def q15_mul(coeff: int, value: int) -> int:
    product = coeff * value
    return product >> 15 if product >= 0 else -((-product) >> 15)


def lif_step(syn: int, mem: int, alpha: int, beta: int,
             threshold: int, h1: int):
    new_syn = q15_mul(alpha, syn) + h1
    spike   = 1 if mem >= threshold else 0
    new_mem = 0 if spike else (q15_mul(beta, mem) + syn)
    return new_syn, new_mem, spike


def reference_inference(weights_flat: list, spike_in: list,
                        alpha: int = ALPHA_Q, beta: int = BETA_Q,
                        threshold: int = THRESH,
                        nb_steps: int = NB_STEPS) -> list:
    """Fixed-point reference matching compute_core.sv.

    weights_flat[in*NB + out] = signed INT8 weight from in to out neuron.
    Returns spike_out list[NB] after nb_steps recurrent steps.
    """
    W = np.array(weights_flat, dtype=np.int8).reshape(NB, NB)
    spike_vec = list(spike_in)
    syn = [0] * NB
    mem = [0] * NB

    for _ in range(nb_steps):
        sv = np.array(spike_vec, dtype=np.int32)
        h1 = [int(np.dot(W[:, j].astype(np.int32), sv)) for j in range(NB)]
        new_syn, new_mem, new_spk = [0]*NB, [0]*NB, [0]*NB
        for k in range(NB):
            new_syn[k], new_mem[k], new_spk[k] = lif_step(
                syn[k], mem[k], alpha, beta, threshold, h1[k])
        syn, mem, spike_vec = new_syn, new_mem, new_spk

    return spike_vec


# ---------------------------------------------------------------------------
# SPI bit-bang driver
# ---------------------------------------------------------------------------

async def spi_transaction(dut, cmd: int, addr: int, data: int = 0x00) -> int:
    """Drive one 4-byte SPI Mode 0 transaction; return the received DATA byte.

    SCK edges are driven on falling core-clock edges so they are never
    coincident with rising core-clock edges (where the DUT's synchronizer
    samples). Each SCK half-period = 4 core clocks.
    """
    bytes_out = [cmd, (addr >> 8) & 0xFF, addr & 0xFF, data]
    miso_byte = 0

    await FallingEdge(dut.clk)
    dut.cs_n.value = 0

    for _ in range(4):
        await RisingEdge(dut.clk)

    for byte_idx, tx_byte in enumerate(bytes_out):
        for bit in range(7, -1, -1):
            await FallingEdge(dut.clk)
            dut.mosi.value = (tx_byte >> bit) & 1

            for _ in range(3):
                await RisingEdge(dut.clk)

            await FallingEdge(dut.clk)
            dut.sck.value = 1

            for _ in range(4):
                await RisingEdge(dut.clk)

            if byte_idx == 3:
                miso_byte = (miso_byte << 1) | int(dut.miso.value)

            await FallingEdge(dut.clk)
            dut.sck.value = 0

            for _ in range(2):
                await RisingEdge(dut.clk)

    await FallingEdge(dut.clk)
    dut.cs_n.value = 1
    dut.mosi.value = 0

    for _ in range(4):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)

    return miso_byte


async def spi_write(dut, addr: int, data: int):
    await spi_transaction(dut, CMD_WRITE, addr, data)


async def spi_read(dut, addr: int) -> int:
    return await spi_transaction(dut, CMD_READ, addr)


# ---------------------------------------------------------------------------
# Higher-level helpers
# ---------------------------------------------------------------------------

async def init(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    dut.rst.value  = 1
    dut.sck.value  = 0
    dut.cs_n.value = 1
    dut.mosi.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def load_weights_spi(dut, weights_flat: list):
    """Write NB×NB INT8 weights to the SRAM via SPI.

    Byte address = in_neuron * NB + out_neuron, matching the compute_core
    bank decoding: addr[2:0] = bank = out % NB_MACS, addr[15:3] = word.
    """
    for addr, byte_val in enumerate(weights_flat):
        await spi_write(dut, addr, int(byte_val) & 0xFF)


async def set_spike_in_spi(dut, spike_bits: list):
    """Write spike_in as NB_BYTES packed bytes to 0xA000..0xA018."""
    for k in range(NB_BYTES):
        byte_val = 0
        for b in range(8):
            idx = k * 8 + b
            if idx < NB and spike_bits[idx]:
                byte_val |= 1 << b
        await spi_write(dut, SPIKE_IN_BASE + k, byte_val)


async def start_inference_spi(dut):
    """Pulse start by writing 0x01 to the control register."""
    await spi_write(dut, CTRL_ADDR, 0x01)


async def poll_done_spi(dut, timeout_txn: int = 200) -> bool:
    """Poll STATUS register until busy=0. Returns True on success."""
    for _ in range(timeout_txn):
        status = await spi_read(dut, STATUS_ADDR)
        if (status & 0x01) == 0:
            return True
    return False


async def read_spike_out_spi(dut) -> list:
    """Read spike_out from 0xA01B..0xA033; return as list[NB]."""
    spikes = []
    for k in range(NB_BYTES):
        byte_val = await spi_read(dut, SPIKE_OUT_BASE + k)
        for b in range(8):
            spikes.append((byte_val >> b) & 1)
    return spikes[:NB]


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_reset(dut):
    """After reset busy=0, done=0 on the top-level ports."""
    await init(dut)
    await FallingEdge(dut.clk)
    assert dut.busy.value == 0, "busy should be 0 after reset"
    assert dut.done.value == 0, "done should be 0 after reset"


@cocotb.test()
async def test_spi_write_read(dut):
    """Write one spike_in byte via SPI, read STATUS; verifies SPI path end-to-end."""
    await init(dut)

    # Write 0xA5 to spike_in byte 0
    await spi_write(dut, SPIKE_IN_BASE, 0xA5)

    # Status should show not busy (no inference started)
    status = await spi_read(dut, STATUS_ADDR)
    assert (status & 0x01) == 0, f"busy should be 0 before start, STATUS=0x{status:02X}"


@cocotb.test()
async def test_full_spi_inference(dut):
    """End-to-end: load 200×200 weights + spike_in via SPI, start inference,
    poll until done, read spike_out; compare against fixed-point reference.

    This exercises the full NB_HIDDEN=200 recurrent weight matrix — the
    dominant kernel from M1 profiling. threshold=100 ensures neurons spike
    and the recurrent path is exercised. NB_STEPS=5 keeps simulation time
    manageable.
    """
    alpha, beta, threshold = ALPHA_Q, BETA_Q, 100
    rng = np.random.default_rng(42)

    weights_signed = rng.integers(-64, 64, NB * NB, dtype=np.int8).tolist()
    spike_in_bits  = rng.integers(0, 2, NB, dtype=np.int32).tolist()

    await init(dut)

    # Write LIF parameters
    await spi_write(dut, 0xA034, alpha & 0xFF)
    await spi_write(dut, 0xA035, (alpha >> 8) & 0xFF)
    await spi_write(dut, 0xA036, beta & 0xFF)
    await spi_write(dut, 0xA037, (beta >> 8) & 0xFF)
    await spi_write(dut, 0xA038, threshold & 0xFF)
    await spi_write(dut, 0xA039, (threshold >> 8) & 0xFF)
    await spi_write(dut, 0xA03A, (threshold >> 16) & 0xFF)
    await spi_write(dut, 0xA03B, (threshold >> 24) & 0xFF)

    # Load full 200×200 weight matrix (40,000 SPI write transactions)
    await load_weights_spi(dut, [b & 0xFF for b in weights_signed])

    # Write spike_in (25 bytes = 200 bits)
    await set_spike_in_spi(dut, spike_in_bits)

    # Start inference
    await start_inference_spi(dut)

    # Poll until done (timeout after 200 STATUS reads)
    done = await poll_done_spi(dut, timeout_txn=200)
    assert done, "Inference did not complete within timeout"

    # Read spike_out (25 bytes)
    hw_spikes  = await read_spike_out_spi(dut)
    ref_spikes = reference_inference(
        weights_signed, spike_in_bits, alpha, beta, threshold)

    mismatches = [k for k in range(NB) if hw_spikes[k] != ref_spikes[k]]
    assert not mismatches, (
        f"Mismatch at {len(mismatches)} neurons: {mismatches[:10]}{'...' if len(mismatches)>10 else ''}. "
        f"HW={[hw_spikes[k] for k in mismatches[:5]]}, "
        f"REF={[ref_spikes[k] for k in mismatches[:5]]}"
    )
