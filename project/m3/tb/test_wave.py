"""Minimal cocotb waveform test for tb_top_wave (NB_HIDDEN=8, NB_STEPS=2).

Drives the full SPI-write → compute → SPI-read sequence in a small
configuration so the VCD file remains manageable. The three phases map
directly to the annotated regions in cosim_waveform.png:
  Phase 1 – SPI write  : load 8×8 weights + spike_in (65 transactions)
  Phase 2 – Compute    : busy=1 from start pulse until done
  Phase 3 – SPI read   : poll STATUS, read spike_out (≤2 + 1 transactions)
"""

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge

NB       = 8
NB_BYTES = NB // 8   # 1
NB_STEPS = 2
ALPHA_Q  = 19875
BETA_Q   = 29635
THRESH   = 100

CMD_WRITE = 0x02
CMD_READ  = 0x03

STATUS_ADDR    = 0xA01A
CTRL_ADDR      = 0xA019
SPIKE_IN_BASE  = 0xA000
SPIKE_OUT_BASE = 0xA01B


def q15_mul(coeff, value):
    product = coeff * value
    return product >> 15 if product >= 0 else -((-product) >> 15)


def lif_step(syn, mem, alpha, beta, threshold, h1):
    new_syn = q15_mul(alpha, syn) + h1
    spike   = 1 if mem >= threshold else 0
    new_mem = 0 if spike else (q15_mul(beta, mem) + syn)
    return new_syn, new_mem, spike


def reference_inference(weights_flat, spike_in, alpha=ALPHA_Q, beta=BETA_Q,
                        threshold=THRESH, nb_steps=NB_STEPS):
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


async def spi_transaction(dut, cmd, addr, data=0x00):
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


async def spi_write(dut, addr, data):
    await spi_transaction(dut, CMD_WRITE, addr, data)


async def spi_read(dut, addr):
    return await spi_transaction(dut, CMD_READ, addr)


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


@cocotb.test()
async def test_wave_inference(dut):
    """Phase 1: SPI write weights+spike_in. Phase 2: compute. Phase 3: SPI read."""
    rng = np.random.default_rng(7)
    weights_signed = rng.integers(-64, 64, NB * NB, dtype=np.int8).tolist()
    spike_in_bits  = rng.integers(0, 2, NB, dtype=np.int32).tolist()

    await init(dut)

    # Write LIF parameters
    await spi_write(dut, 0xA034, ALPHA_Q & 0xFF)
    await spi_write(dut, 0xA035, (ALPHA_Q >> 8) & 0xFF)
    await spi_write(dut, 0xA036, BETA_Q & 0xFF)
    await spi_write(dut, 0xA037, (BETA_Q >> 8) & 0xFF)
    await spi_write(dut, 0xA038, THRESH & 0xFF)
    await spi_write(dut, 0xA039, (THRESH >> 8) & 0xFF)
    await spi_write(dut, 0xA03A, (THRESH >> 16) & 0xFF)
    await spi_write(dut, 0xA03B, (THRESH >> 24) & 0xFF)

    # Phase 1a: load 8×8 weight matrix (64 writes)
    for addr, bval in enumerate(weights_signed):
        await spi_write(dut, addr, int(bval) & 0xFF)

    # Phase 1b: load spike_in (1 byte)
    byte_val = 0
    for b in range(8):
        if b < NB and spike_in_bits[b]:
            byte_val |= 1 << b
    await spi_write(dut, SPIKE_IN_BASE, byte_val)

    # Phase 2: start inference
    await spi_write(dut, CTRL_ADDR, 0x01)

    # Poll until busy=0
    for _ in range(50):
        status = await spi_read(dut, STATUS_ADDR)
        if (status & 0x01) == 0:
            break

    # Phase 3: read spike_out (1 byte)
    hw_byte = await spi_read(dut, SPIKE_OUT_BASE)
    hw_spikes = [(hw_byte >> b) & 1 for b in range(NB)]

    ref_spikes = reference_inference(weights_signed, spike_in_bits)
    mismatches = [k for k in range(NB) if hw_spikes[k] != ref_spikes[k]]
    assert not mismatches, (
        f"Mismatch at neurons {mismatches}. "
        f"HW={[hw_spikes[k] for k in mismatches]}, "
        f"REF={[ref_spikes[k] for k in mismatches]}"
    )
