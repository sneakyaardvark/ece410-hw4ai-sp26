# Critical Path Analysis — M3 Pre-PNR STA

## Corner: nom_tt_025C_1v80 (TT, 25 °C, 1.8 V)

**WNS:** −1653.2 ns  
**TNS:** −16,466,156 ns  
**Clock period:** 20 ns (50 MHz)

---

## What the timing report shows (and why it is misleading)

The worst-case path reported by the pre-placement static timing analysis starts at the `rst` input
and ends at a flip-flop that holds a neuron state register. The delay is 1,653 ns — roughly 80×
the clock period.

This number is not physically real. Because placement has not been run yet, the tool has no
knowledge of where logic cells will land on the die. It models every wire as if it must drive every
connected receiver simultaneously over a single long conductor. The reset signal connects to every
flip-flop in the chip — all 22,325 of them — so the tool assigns the reset wire an enormous
estimated capacitance (16.5 pF) and the resulting delay dominates everything else. When placement
and clock-tree synthesis run in the full flow, the tool inserts a tree of repeater buffers that
break the reset net into small, local segments. Each segment sees only a few dozen receivers, the
propagation delay drops to under 1 ns, and the violation disappears.

---

## The real computational bottleneck

Once the reset artifact is removed from consideration, the path that is expected to limit
performance is the synaptic state update at the heart of each LIF neuron:

```
new_syn = (alpha × syn >> 15) + h1_in
```

**What this computes.** Each neuron maintains a synaptic current `syn` that accumulates incoming
spike signals over time. At every time step the network applies a decay: it multiplies the current
value by `alpha` (approximately 0.606), which represents how quickly the neuron "forgets" older
inputs. Without this decay, a burst of spikes early in a sound clip would influence every
subsequent time step equally — the network would have no sense of recency. The decay constant is a
learned parameter; different neurons learn different forgetting rates during training.

**Why a multiplication is necessary.** Spikes themselves are binary (a neuron either fires or it
does not), so the spike-propagation step is cheap — it is just an addition. The decay step cannot
be simplified the same way. The decay constant is a continuous value between 0 and 1, and the
synaptic state is a 32-bit accumulator. Multiplying a 32-bit value by a 16-bit decay constant
requires the hardware to compute a full-width product — this takes longer than any other
arithmetic step in the per-neuron update.

**Why this path, specifically.** The chip runs one MAC array pass per time step, processing all
200 neurons in sequence. Every neuron update touches exactly this multiply. Because it sits on the
loop-carried path — the output `new_syn` is registered and fed back as the input `syn` next cycle
— its delay sets the minimum cycle time for the entire inference computation.

---

## What would fix it

**Narrower state representation.** The synaptic accumulator is currently 32 bits, and the decay
constant is 16 bits, giving a 32 × 16 multiply. Reducing the accumulator to 16 bits while
accepting a small loss in dynamic range would roughly halve the multiply width and shorten this
path substantially. The accuracy impact can be measured directly in the Python simulation before
changing any RTL.

**Pipelining the multiply.** The multiply can be split into two or more pipeline stages, each
completing within the 20 ns budget, with an intermediate register in between. This would not
reduce latency per inference but would allow the clock frequency to increase, improving throughput.
