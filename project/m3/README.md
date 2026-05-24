# M3 — Integration and Synthesis

## File catalog

### RTL
| File | Description |
|---|---|
| `rtl/top.sv` | Integrated top module: wires `spi_interface` (M2) to `compute_core` (M2) |

### Testbench
| File | Description |
|---|---|
| `tb/tb_top.sv` | cocotb DUT wrapper: NB_HIDDEN=200, NB_MACS=8, NB_STEPS=5 |
| `tb/tb_top_wave.sv` | Minimal waveform-capture wrapper: NB_HIDDEN=8, NB_STEPS=2, `$dumpfile` |
| `tb/test_top.py` | End-to-end cocotb tests (3/3): reset, SPI path, full 200×200 inference vs. fixed-point reference |
| `tb/test_wave.py` | Single inference test for waveform capture (NB=8) |
| `tb/plot_wave.py` | Parses `tb_top_wave.vcd`, generates annotated 3-phase waveform PNG |
| `tb/Makefile` | `make top` — full co-sim; `make wave` — waveform capture |

### Simulation artifacts
| File | Description |
|---|---|
| `sim/cosim_run.log` | Full co-simulation transcript: 3/3 PASS, NB_HIDDEN=200, Icarus Verilog 12.0 |
| `sim/cosim_waveform.png` | Annotated waveform: ① SPI Write, ② Compute (busy=1), ③ SPI Read |

### Synthesis
| File | Description |
|---|---|
| `synth/config.json` | OpenLane 2 configuration: sky130A/sky130_fd_sc_hd, 20 ns clock, AREA 0 |
| `synth/sky130_sram_stub.v` | Port-only stub for `sky130_sram_1kbyte_1rw1r_8x1024_8` (Verilator blackbox) |
| `synth/openlane_run.log` | Full OpenLane 2 stdout/stderr (flow ran to STAPrePNR) |
| `synth/area_report.txt` | Yosys cell statistics: 1,261,907 cells, 22,325 DFFs, 40 SRAM macros, 12.48 mm² |
| `synth/timing_report_trim.txt` | Pre-PNR STA: critical path traces + WNS/TNS summary (trimmed for GitHub) |
| `synth/timing_report.txt.gz` | Full pre-PNR STA report, gzip-compressed (145 MB → 9.6 MB); raw file excluded by .gitignore |
| `synth/power_report.txt` | Pre-PNR power estimate: 148 mW total (51% SRAM macro, 38% sequential) |
| `synth/critical_path.md` | Critical path identification: rst fanout → inv → 7401-sink net → DFF |

### Notes
| File | Description |
|---|---|
| `synthesis_notes.md` | Narrative: SRAM macro integration, lint fixes, results, scope |

---

## Reproducing the co-simulation

**Dependencies:** Icarus Verilog 12.0, cocotb 2.0.1, Python 3.13 (all provided by the Nix devshell).

```bash
# Enter the dev environment
direnv allow   # or: nix develop

# Full 3/3 test suite (NB_HIDDEN=200, ~15 min wall-clock)
cd project/m3/tb
make top

# Waveform capture (NB_HIDDEN=8, ~2 s)
make wave
../../.venv/bin/python plot_wave.py   # writes ../sim/cosim_waveform.png
```

The full test suite result is committed at `project/m3/sim/cosim_run.log`.
The waveform was generated from the NB_HIDDEN=8 `make wave` run.

---

## Reproducing the synthesis

**Tool:** OpenLane 2.3.10  
**PDK:** sky130A, volare SHA `0fe599b2afb6708d281543108caf8310912f54af`

```bash
# Enter the dev environment (OpenLane must be on PATH)
direnv allow

cd project/m3/synth
openlane --to OpenROAD.STAPrePNR -j 12 config.json 2>&1 | tee openlane_run.log
```

The flow was stopped at `OpenROAD.STAPrePNR` (before placement and routing) to limit runtime.
Total wall-clock time on a Ryzen 5600X: approximately 50 minutes.
Reports are committed in `project/m3/synth/`.
