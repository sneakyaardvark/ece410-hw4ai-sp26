# Synthesis Interpretation — compute_core (sky130A, sky130_fd_sc_hd)

**Run:** OpenLane Classic, Yosys/ABC `DELAY_0`, target 20 ns (50 MHz).

## a) Clock Period and Worst-Case Slack

Clock period: **20.0 ns** (50 MHz). Post-synthesis OpenSTA (tt_025C_1v80, ideal clock):

- **Setup WNS: −6870.77 ns** (VIOLATED). Data arrival time 6890.20 ns vs. required 19.43 ns.
- **Setup TNS: −53,717,108 ns** — every endpoint on the write-address decode path is violated.
- **Hold WNS: +0.42 ns** (MET). Worst hold path is `h1_acc[111][29]` through one `mux2_1`.

## b) Critical Path

- **Source register:** `row_cnt[1]` — bit 1 of the MAC inner-loop counter, stepping through all 200 input neurons in each tile pass
- **Sink register:** `mac_acc_out[159]` — the MSB of MAC unit 5's 32-bit INT32 accumulator, which collects the weighted spike sum for one output neuron in the current tile
- **Path:** `row_cnt` feeds the `v1_rd_addr` computation (`row_cnt × 25 + tile_cnt`), whose 13-bit result drives the 5000-entry combinational read-mux of the weight SRAM; the selected 8×INT8 weight word then enters the MAC multiply-accumulate, and the product updates `mac_acc_out[159]`

The 4-OR-NAND (`o41ai_2`) at 63.31 pF is the peak fan-out node in the SRAM read-address decode, simultaneously gating ~19,000 word-enable mux inputs with no buffer tree. It accounts for **82.8%** of the 6890 ns path delay. Dominant cell types along the path: 4-OR-NAND (`o41ai_2`), OR-of-active-low-inputs-NAND (`o2bb2ai_2`), 2-OR-NAND (`o21ai_2`).

## c) Total Cell Area and Top Three Contributors

Total chip area: **31.85 Mµm²**, **2,657,564** instances.

| Cell | Instances | Est. Area | Share |
|---|---|---|---|
| `dfxtp_2` | 340,164 | 7.24 Mµm² | 22.7% |
| `mux2_1` | 263,385 | 1.65 Mµm² | 5.2% |
| `mux4_2` | 86,462 | 0.87 Mµm² | 2.7% |

All three trace back to `v1_mem` being inferred as 320K flip-flops and its mux-based read/write interface.

## d) Constraint Failures and Warnings

Lint errors: **0**; timing constructs: **0**; inferred latches: **0**; synthesis check errors: **0**; unmapped instances: **0**. Hold **met** (+0.42 ns). Setup **massively violated** (WNS −6870.77 ns, TNS −53.7 Gns) — the root cause is a single unbuffered `o41ai_2` driving 63.31 pF with no repeater tree. The fix is replacing `v1_mem` with an SRAM macro (eliminating the 320K write-mux tree entirely) rather than inserting buffers. The `-noabc` run produced 26 "area unknown for generic cell" messages — benign, all resolved in the mapped run.
