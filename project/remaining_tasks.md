# Remaining tasks before M4

The three highest-priority changes, most important first.

## 1. Close timing with a full place-and-route run

The OpenLane flow was stopped at `OpenROAD.STAPrePNR`, so the only timing data
is pre-placement. Its reported WNS of −1653 ns is a high-fanout reset-net
artifact (the `rst` wire modeled as driving all 22,325 DFFs over one unbuffered
conductor; see `m3/synth/critical_path.md`), not a real datapath violation.
**Action:** run OpenLane through CTS, routing, and `OpenROAD.STAPostPNR` so the
reset tree is buffered, then read post-route WNS on the *real* critical path
(the `snn_lif_cell` synaptic update). Until this runs, every "meets 20 ns / 50
MHz" claim — including the benchmark's 50 MHz and the roofline ceilings — is
unconfirmed.

## 2. Validate end-to-end accuracy with the trained weights

The cocotb benchmark and `test_top` use **random** INT8 weights with a tuned
threshold; the recurrent dynamics were bistable and no classification accuracy
was measured. M3's stated goal (load trained SHD weights, measure accuracy) is
not yet met. **Action:** write a bridge that quantizes `project/model.pt`'s `v1`
matrix to INT8, loads it via the `weight_wr` port, drives a real SHD hidden-spike
train through `compute_core`, and compares `spike_out` per step against the
PyTorch reference. Report top-1 accuracy on the SHD test set and the *measured*
per-step activity (which replaces the assumed 10% sparsity in the benchmark and
roofline).

## 3. Raise arithmetic intensity off the bandwidth roof

The roofline puts the design on the 0.40 GB/s on-chip bandwidth ceiling at
AI ≈ 0.66 SynOp/byte (`codefest/cf09/benchmarks/roofline_analysis.md`): it is
memory-bandwidth bound, fetching 8 bytes/cycle (1 byte/bank) and consuming one
`act_list` row per `S_TILE_EXEC` cycle. **Action:** widen each `v1_sram_bank`
read port to return a multi-byte burst (e.g. 4 weights/bank/access) and add a
small per-lane FIFO so `S_TILE_EXEC` consumes >1 SynOp/cycle without stalling on
SRAM latency. This moves the operating point up the sloped roof toward the ridge
(1.0 SynOp/byte) and shortens the dominant `S_TILE_EXEC` phase. Secondary, on the
critical path identified in task 1: pipeline the `snn_lif_cell` synaptic update
(`syn_product = alpha * syn_reg` → `>>> 15` → 32-bit add) into two stages, or
replace its final 32-bit ripple adder with a carry-save adder, to buy timing
slack once post-PNR delay (task 1) is known.
