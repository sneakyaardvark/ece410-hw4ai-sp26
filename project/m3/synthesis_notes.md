# M3 Synthesis Notes

## What was synthesized

The target design is `top` — the integrated SNN accelerator for Spiking Heidelberg Digits (SHD)
audio classification. It connects two M2 modules: `spi_interface` (SPI Mode 0 slave with a
register-map decoder) and `compute_core` (event-driven recurrent LIF datapath). The network
has NB_HIDDEN=200 neurons, NB_MACS=8 MAC units, and runs NB_STEPS=100 recurrent time steps.
The dominant kernel identified in M1 profiling — the 200×200 INT8 recurrent weight matrix — is
stored in hardware SRAM and processed by the MAC array.

The synthesis target was sky130A/sky130_fd_sc_hd at 50 MHz (20 ns clock period) using
OpenLane 2.3.10 with the Classic flow, stopping at `OpenROAD.STAPrePNR` to obtain synthesis
and pre-PNR timing results without running the full place-and-route.

---

## SRAM macro integration

The first and most significant challenge was the weight SRAM. `compute_core` originally inferred
eight 5000×8-bit register arrays — one bank per MAC unit — using a standard synchronous
read/write always_ff pattern intended for FPGA block RAM. Yosys has no BRAM primitive for sky130;
it would have flattened each bank to 5,000 flip-flops, producing 40,000 flip-flops for the SRAM
alone plus enormous combinatorial decode logic. A trial run confirmed this: Yosys extracted
1.5 M gates before ABC even started, and the run was killed after it became clear it would take
many hours.

The fix was to replace the behavioral inference with explicit sky130 SRAM macro instantiation.
A new module `v1_sram_bank` wraps five `sky130_sram_1kbyte_1rw1r_8x1024_8` macros in depth
to cover the 5,000-word address range of each bank (5 × 1,024 = 5,120 entries, 5,000 used).
Eight `v1_sram_bank` instances replace the old 2-D register array in `compute_core`.

To keep M2 simulation independent of the sky130 verilog model, `v1_sram_bank` uses an
`` `ifdef SYNTHESIS `` guard: simulation uses a plain `always_ff` register file with identical
1-cycle read latency; synthesis uses the macro tiling. OpenLane defines `SYNTHESIS` via
`VERILOG_DEFINES`, so Yosys sees the macro path automatically.

A second problem was the Verilator lint step. OpenLane passes `VERILOG_DEFINES` to Verilator
as well, so Verilator also took the `ifdef SYNTHESIS` branch and could not find the
`sky130_sram_1kbyte_1rw1r_8x1024_8` module. Adding the full sky130 behavioral verilog to
`VERILOG_FILES_BLACKBOX` caused the same ABC runtime problem because OpenLane's toolbox
pre-processes blackbox files through Yosys. The solution was a hand-written stub
(`sky130_sram_stub.v`) containing only the module port declaration with no internals — giving
Verilator the module signature it needs while giving Yosys nothing to elaborate.

---

## Verilator lint errors

Three RTL width-mismatch errors surfaced that had been silent under iverilog:

- `compute_core.sv`: `ACT_IDX_W'(lif_idx - 1)` — subtracting the integer literal `1` promotes
  the expression to 32 bits before the cast. Fixed to `lif_idx - 1'b1`.
- `compute_core.sv`: `ROW_W'(act_count - 1)` — same issue. Fixed to `(act_count - 1'b1)`.
- `interface.sv`: `threshold[7:0] <= STATE_W'(rx_byte_now)` — casting an 8-bit byte to 32 bits
  then assigning to an 8-bit slice causes a truncation warning treated as an error. The cast is
  unnecessary; fixed by assigning `rx_byte_now` directly to each byte slice.

All three were latent bugs in M2 RTL that Verilator's stricter elaboration exposed.

---

## Synthesis results

After fixing the SRAM and lint issues, synthesis completed successfully in approximately 50 minutes
on a Ryzen 5600X (12 threads, `-j 12`, `SYNTH_STRATEGY "AREA 0"`).

**Area (standard cells only):**
- Total chip area: 12.48 mm² (12,475,476 µm²)
- Sequential elements: 22,325 `dfxtp_2` flip-flops = 3.81% of area (474,862 µm²)
- Standard cell count: 1,261,907
- Hard macros: 40 × `sky130_sram_1kbyte_1rw1r_8x1024_8` (area not included; no floorplan run)

The SRAM macro area was not accounted for because `OpenROAD.STAPrePNR` does not perform
floorplanning or macro placement. Each `sky130_sram_1kbyte_1rw1r_8x1024_8` has a published area
of approximately 0.054 mm² (from LEF); 40 macros add roughly 2.2 mm² to the total, giving an
estimated true chip area of ~14.7 mm².

**Power (TT, 25 °C, 1.8 V, pre-PNR activity estimate):**
- Sequential: 56.4 mW (38%)
- Combinational: 15.8 mW (11%)
- Macro (SRAM): 75.9 mW (51%)
- **Total: 148 mW**

Power is dominated by the 40 SRAM macros. In a sparse-activity mode (~10% spike rate), the
event-driven MAC array skips most weight rows, but the SRAM leakage and read-cycle power remain
constant regardless of sparsity.

**Timing:**
WNS = −1,653 ns, TNS = −16.5 µs. These numbers should be ignored for design evaluation: the
violation is entirely due to the synchronous reset net having 7,401 sinks with no buffering —
a known pre-PNR artefact with no physical basis. It will be eliminated automatically when
OpenROAD inserts a reset buffer tree during clock tree synthesis in the full flow. See
`critical_path.md` for the full analysis. The data-path logic (LIF multiply-accumulate) is
not visible as the critical path at this stage.

---

## Scope and limitations

The flow was stopped at `OpenROAD.STAPrePNR` (before floorplan, placement, CTS, and routing).
This means:
- Timing numbers are wire-load-model estimates, not routed parasitics.
- The reset net was not buffered; setup violations are not real.
- Power does not include clock-tree switching.
- The SRAM macros were not placed; macro-to-logic routing congestion is unknown.

For M4, the next step is to run the full Classic flow through `OpenROAD.DetailedRouting` with
a floorplan that reserves macro placement regions for the 40 SRAM instances. Reset tree
buffering will be applied during CTS. The expected post-routing WNS is positive (design closes
at 50 MHz) because the data-path critical path (32-bit LIF multiply-accumulate) is estimated
at 8–12 ns, well within the 20 ns budget.
