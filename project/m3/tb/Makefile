VENV_BIN      = $(realpath $(PWD)/../../.venv/bin)
export PATH  := $(VENV_BIN):$(PATH)

SIM           ?= icarus
TOPLEVEL_LANG  = verilog

M2_RTL = $(PWD)/../../m2/rtl
M3_RTL = $(PWD)/../rtl

COCOTB_MAKEFILES = $(shell cocotb-config --makefiles)

# All RTL sources for the integrated top — m2 RTL plus m3 top
TOP_SOURCES = \
	$(M2_RTL)/snn_mac.sv \
	$(M2_RTL)/snn_mac_array.sv \
	$(M2_RTL)/snn_lif_cell.sv \
	$(M2_RTL)/snn_lif_bank.sv \
	$(M2_RTL)/compute_core.sv \
	$(M2_RTL)/interface.sv \
	$(M3_RTL)/top.sv \
	$(PWD)/tb_top.sv

WAVE_SOURCES = \
	$(M2_RTL)/snn_mac.sv \
	$(M2_RTL)/snn_mac_array.sv \
	$(M2_RTL)/snn_lif_cell.sv \
	$(M2_RTL)/snn_lif_bank.sv \
	$(M2_RTL)/compute_core.sv \
	$(M2_RTL)/interface.sv \
	$(M3_RTL)/top.sv \
	$(PWD)/tb_top_wave.sv

.PHONY: top wave all

top:
	$(MAKE) -f $(COCOTB_MAKEFILES)/Makefile.sim \
		TOPLEVEL=tb_top \
		VERILOG_SOURCES="$(TOP_SOURCES)" \
		COCOTB_TEST_MODULES=test_top \
		SIM_BUILD=sim_build_top

wave:
	$(MAKE) -f $(COCOTB_MAKEFILES)/Makefile.sim \
		TOPLEVEL=tb_top_wave \
		VERILOG_SOURCES="$(WAVE_SOURCES)" \
		COCOTB_TEST_MODULES=test_wave \
		SIM_BUILD=sim_build_wave

all: top

# ----------------------------------------------------------------------------
# Include cocotb rules so `make sim` also works from this directory
# ----------------------------------------------------------------------------

include $(COCOTB_MAKEFILES)/Makefile.sim
