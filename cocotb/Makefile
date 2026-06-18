# SPDX-License-Identifier: Apache-2.0
# Optional PDK-aware cocotb harness. Requires the GF180MCU PDK + wafer.space IP.
# For the everyday no-PDK loop use ../tb (Icarus) instead.

SIM      ?= icarus
TOPLEVEL_LANG ?= verilog
SLOT     ?= 1x0p5

# Run the Python runner directly (it drives both build + test).
.PHONY: sim
sim:
	python3 chip_top_tb.py

clean:
	rm -rf sim_build results.xml *.vcd *.fst
