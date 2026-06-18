# tb/ — simulation (the no-PDK fast path)

This is where you prove your logic is correct, fast, with no PDK. It runs
`chip_core` directly under Icarus Verilog inside the sim container.

#### Run it

From the repo root:

    bash scripts/sim.sh bash -lc \
      'iverilog -g2012 -Wall -o /tmp/core.vvp src/chip_core.sv tb/tb_chip_core.sv && vvp /tmp/core.vvp'

Expected output ends with:

    ==== 256 samples checked, 0 mismatches ====
    OK: scaffold chip_core matched golden

A non-zero mismatch count, a `FAIL` line, or `TIMEOUT` means red. `-Wall` must
be clean (no latch / width warnings).

#### What the test does

`tb_chip_core.sv` elaborates `chip_core` with the real 1x0p5 pad budget
(4 input / 46 bidir / 4 analog pads), checks the bidir direction mask
(outputs oe=1, demo-input block [11:8] oe=0, ie = ~oe), then runs the counter
and compares the mirrored low 8 bits against `../models/golden.hex` every clock.
It prints a single OK/FAIL verdict and exits. The DUT is never tweaked to pass —
only the testbench's capture timing is set so a correct DUT scores 0 mismatches.

#### When you change chip_core

1. Update `../models/ref_model.py` to model your new logic; regenerate
   `../models/golden.hex` and commit it.
2. Update the scenario + captured signal here to match.
3. Keep the OK/FAIL/`$finish` structure and the safety timeout.
4. Re-run the command above — it must be green before you harden.

The optional whole-padring (PDK-aware) harness lives in `../cocotb`; you rarely
need it. See its notes for when GL simulation is worth running.
