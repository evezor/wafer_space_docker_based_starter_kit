# models/ — the golden reference (trust anchor)

The expected behavior of `chip_core`, written independently in plain Python.
This is the oracle the simulation checks against.

#### Files

- `ref_model.py` — computes the expected output sequence using plain integer
  math (no floats, no numpy) so it is bit-exact to the Verilog. Run it to
  regenerate the golden vector:

      python3 models/ref_model.py

- `golden.hex` — the committed expected output: one hex word per line, read by
  `tb/tb_chip_core.sv` via `$readmemh`. **Commit this file.** Regenerating it
  with no resulting git diff is itself proof you didn't change behavior.

#### The pattern (and how to extend it)

1. Model your design in `ref_model.py` (same parameters as the RTL, same
   integer math).
2. Run it once -> `golden.hex`. Commit.
3. The self-checking testbench drives the same scenario, captures the DUT
   output, and compares every value against `golden.hex`.

Bit-exact match means you can refactor or re-pipeline the RTL freely: if the
test stays green, behavior is byte-for-byte unchanged.

#### When you build your own engine

Keep these three pieces: a Python reference model, a committed golden vector, and a
self-checking testbench that demands a 0-mismatch match. Re-point them at your design's
behavior and the same discipline carries over.
