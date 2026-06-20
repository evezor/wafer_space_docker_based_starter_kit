# SPDX-License-Identifier: Apache-2.0
#
# Optional PDK-aware harness: elaborates the FULL chip_top (pads + marker IP +
# chip_core). For the everyday loop use the Icarus fast path in tb/ instead.

import os
from pathlib import Path

import cocotb
from cocotb.triggers import Timer, ClockCycles
from cocotb.clock import Clock
from cocotb_tools.runner import get_runner

sim      = os.getenv("SIM", "icarus")
gl       = os.getenv("GL", False)
pdk_root = os.getenv("PDK_ROOT", Path(__file__).resolve().parent / "../gf180mcu")
pdk      = os.getenv("PDK", "gf180mcuD")
scl      = os.getenv("SCL", "gf180mcu_fd_sc_mcu7t5v0")
pad      = os.getenv("PAD", "gf180mcu_fd_io")
sram     = os.getenv("SRAM", "gf180mcu_fd_ip_sram")
slot     = os.getenv("SLOT", "1x1")            # scaffold default slot

hdl_toplevel = "chip_top"


async def start_up(dut):
    dut.input_PAD.value = 0
    if gl:
        dut.VDD.value = 1
        dut.VSS.value = 0
    cocotb.start_soon(Clock(dut.clk_PAD, 20, "ns").start())  # 50 MHz
    dut.rst_n_PAD.value = 0
    await Timer(200, "ns")
    dut.rst_n_PAD.value = 1


@cocotb.test()
async def test_heartbeat(dut):
    """Smoke test: release reset, gate the counter on, let it run."""
    await start_up(dut)
    await ClockCycles(dut.clk_PAD, 10)

    # input pad 0 gates the counter; set all input pads high to enable it.
    # (cocotb cannot write individual vector bits; drive the whole bus.)
    dut.input_PAD.value = -1
    await ClockCycles(dut.clk_PAD, 200)

    # Liveness only -- the bit-exact correctness check lives in tb/tb_chip_core.sv.
    cocotb.log.info("heartbeat = %s" % dut.bidir_PAD.value)


def chip_top_runner():
    proj_path = Path(__file__).resolve().parent
    sources, includes = [], [proj_path / "../src/"]
    defines = {
        f"SLOT_{slot.upper()}": True,
        f"PDK_{pdk.replace('-', '_')}": True,
        f"SCL_{scl}": True,
        f"PAD_{pad}": True,
        f"SRAM_{sram}": True,
    }

    if gl:
        sources.append(Path(pdk_root) / pdk / "libs.ref" / scl / "verilog" / f"{scl}.v")
        sources.append(Path(pdk_root) / pdk / "libs.ref" / scl / "verilog" / "primitives.v")
        sources.append(proj_path / f"../final/pnl/{hdl_toplevel}.pnl.v")
        defines.update({"FUNCTIONAL": True, "USE_POWER_PINS": True})
    else:
        sources.append(proj_path / "../src/chip_top.sv")
        sources.append(proj_path / "../src/chip_core.sv")

    sources += [
        Path(pdk_root) / pdk / f"libs.ref/{pad}/verilog/{pad}.v",
        proj_path / "../ip/gf180mcu_ws_ip__logo/vh/gf180mcu_ws_ip__logo.v",
        proj_path / "../ip/gf180mcu_ws_ip__marker/vh/gf180mcu_ws_ip__marker.v",
        proj_path / "../ip/gf180mcu_ws_ip__qrcode_id/vh/gf180mcu_ws_ip__qrcode_id.v",
        proj_path / "../ip/gf180mcu_ws_ip__shuttle_id/vh/gf180mcu_ws_ip__shuttle_id.v",
        proj_path / "../ip/gf180mcu_ws_ip__project_id/vh/gf180mcu_ws_ip__project_id.v",
    ]

    runner = get_runner(sim)
    runner.build(sources=sources, hdl_toplevel=hdl_toplevel, defines=defines,
                 always=True, includes=includes, waves=True)
    runner.test(hdl_toplevel=hdl_toplevel, test_module="chip_top_tb", waves=True)


if __name__ == "__main__":
    chip_top_runner()
