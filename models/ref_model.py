#!/usr/bin/env python3
"""
Scaffold reference model -- the GOLDEN oracle for the heartbeat-counter chip_core.

This computes the EXACT sequence the RTL mirrors onto bidir_out[MIRROR_W-1:0], using
plain Python int math (no floats, no numpy) so it is bit-exact to the Verilog counter.

The scaffold core is a free-running counter (gated by input pad 0). With the gate held
high from the first captured step, the value visible right after the k-th count step is
(k+1), wrapped to MIRROR_W bits. This model emits that sequence.

Run with no args to (re)generate models/golden.hex deterministically:

    python3 models/ref_model.py
"""

import os

# ---- parameters: mirror the RTL EXACTLY (chip_core: MIRROR_W; tb: NSAMP) ----
MIRROR_W = 8       # low counter bits mirrored onto bidir_out
NSAMP    = 256     # number of steps captured by the testbench

GOLDEN_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "golden.hex")


def run_golden():
    """Counter value visible right after each of NSAMP increments, low MIRROR_W bits.

    The gate is held high from the first captured step, so the value after the
    k-th increment (k = 0..NSAMP-1) is (k + 1), wrapped to MIRROR_W bits.
    """
    mask = (1 << MIRROR_W) - 1
    return [(k + 1) & mask for k in range(NSAMP)]


def write_golden(samples, path=GOLDEN_PATH):
    """One hex word per line, MIRROR_W bits wide, no header (clean $readmemh)."""
    width = (MIRROR_W + 3) // 4          # hex digits to hold MIRROR_W bits
    mask  = (1 << MIRROR_W) - 1
    with open(path, "w", newline="\n") as f:
        for s in samples:
            f.write("%0*x\n" % (width, s & mask))


def main():
    samples = run_golden()
    write_golden(samples)
    print("Scaffold golden reference (heartbeat counter, bit-exact)")
    print("  MIRROR_W   = %d" % MIRROR_W)
    print("  NSAMP      = %d" % NSAMP)
    print("  output     = %s" % GOLDEN_PATH)
    print("  first 8    :", samples[:8])
    print("  last 4     :", samples[-4:])


if __name__ == "__main__":
    main()
