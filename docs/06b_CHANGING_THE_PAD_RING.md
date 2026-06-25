# 06b — Changing the Pad Ring (advanced)

This is the advanced companion to [`06 — Continue the Design`](06_CONTINUE_THE_DESIGN.md).
06 is about designing your core *inside* the pad ring the kit ships. **This page is about
changing the ring itself** — giving a pad a physically different **cell** (a real type
change), or targeting a different **slot**.

> ⚠️ **You probably don't need this.** A bidir pad can already act as an input or an output
> by *configuration* — no ring change required (see
> [Allocation is yours](06_CONTINUE_THE_DESIGN.md#allocation-is-yours-bidir-is-the-universal-pad)
> in 06). Only come here when the shipped allocation genuinely can't express your design.

**Prerequisite:** read *The mental model: two layers* in 06. The one idea you must hold:

> A pad's **type** is the foundry **cell** that `chip_top.sv` instantiates (Layer A, fixed
> at tapeout). Changing a pad's type means **changing that cell** — real RTL surgery on a
> do-not-edit file, coordinated across several files, proven with sim + harden.

---

## The files that move together

A pad-ring change is never one file. These four are coupled; a change ripples across all
of them:

| File | Its job in the ring | What you change |
|---|---|---|
| `src/slot_defines.svh` | the per-type pad **counts** for your slot | bump the counts |
| `src/chip_top.sv` | instantiates one foundry **cell** per pad (the silicon) and **names** each instance | the loops follow the counts; sometimes add an instance |
| `librelane/slots/slot_*.yaml` | **places** each named instance on the ring | re-point the placement to the new name |
| `src/chip_core.sv` | the **contract**: bus widths derive from the counts; your logic indexes them | move/retie the affected bits |

(Plus `cocotb/chip_top_tb.py` and `librelane/config.yaml` if you add or rename a *port* or
a source file.)

> **The coupling rule (from 06):** `chip_top` **defines** the instance names; the YAML
> **references** them. Rename or move a pad in `chip_top` → update the YAML to match, or the
> harden can't find the pad to place.

---

## Step-by-step: change one pad from type X to type Y

**Worked example:** you've used every bidir pad and you need one of your *input* pads to
also drive out. That means upgrading one pad from the input-only `in_c` cell to the
universal `bi_24t` (bidir) cell. Pick your own X→Y; the steps are identical.

Recall the cell table from 06: `in_c` = input only · `bi_24t` = input/output/bidir ·
`asig_5p0` = analog. **Changing type = swapping which of these sits at a position.**

### Step 1 — Adjust the counts (`src/slot_defines.svh`)

One fewer input, one more bidir, in your slot's block:

```diff
- `define NUM_INPUT_PADS 12
- `define NUM_BIDIR_PADS 40
+ `define NUM_INPUT_PADS 11
+ `define NUM_BIDIR_PADS 41
```

The counts must still sum to the same number of physical ring positions — you're moving a
pad between types, not adding one.

### Step 2 — `src/chip_top.sv`: the generate loops follow the counts

The `inputs` and `bidir` generate loops are sized by those macros
(`for (i=0; i<NUM_INPUT_PADS; …)` etc.), so they now build `inputs[0..10]` and
`bidir[0..40]` automatically. The new `bidir[40]` (a `bi_24t` cell) exists; `inputs[11]` no
longer does. For a simple count shift between existing types **you hand-instantiate
nothing** — the loops do it. (You'd only add a block if you needed a cell type the ring
doesn't already have.)

### Step 3 — `librelane/slots/slot_*.yaml`: re-point the placement

Find the line that placed the pad you're converting and rename it from the old instance to
the new one. The pad stays in the same physical spot; only its name and cell change:

```diff
-     "inputs\\[11\\].pad",     # was: input-only, on the west edge
+     "bidir\\[40\\].pad",      # now: same ring position, a bi_24t
```

Leave every other line alone. (Why this works: the YAML only *places* named instances —
`bidir[40]` is the instance `chip_top` just created.)

### Step 4 — `src/chip_core.sv`: the contract widths shift

`NUM_INPUT_PADS` and `NUM_BIDIR_PADS` changed, so the port buses resize automatically (they
are parameterized). But your *logic* must follow:

- any logic that read the old top input (`input_in[11]`) moves to the new bidir bit
  (`bidir_in[40]` to read it, `bidir_out[40]` to drive it);
- the new bidir bit needs a **direction**: set `bidir_oe[40]` and keep
  `bidir_ie = ~bidir_oe` (06's oe-mask pattern already covers the whole bus);
- re-check the `_unused` fold so the bit isn't simultaneously used *and* folded.

### Step 5 — Simulate, then harden

```bash
make sim-cocotb     # elaborates the whole chip_top — catches name/width mismatches fast
make harden         # only once sim is green
```

The pad-level cocotb run is the quickest way to catch a YAML↔`chip_top` name mismatch or a
bus-width error. The **harden + precheck** are what tell you the swap is *physically* OK.

> ⚠️ **A type change is not always "free."** `in_c → bi_24t` is digital→digital and usually
> drops right in — but a `bi_24t` cell is physically larger than an `in_c`, and anything
> involving the analog `asig_5p0` cell (5 V, its own ESD and placement rules) is a bigger
> deal. Don't assume the position has room or that the result is manufacturable — that is
> exactly what `make harden` and the precheck verify. If precheck complains, free up space
> or move the pad.

---

## Changing the slot (the easy one)

Targeting a different die size / pad budget is **not** a `chip_top` edit — it's a build
selector:

```bash
make SLOT=0p5x1 …        # or set SLOT in your environment / Makefile
```

That picks the matching block in `slot_defines.svh` **and** the matching
`librelane/slots/slot_*.yaml`. Your core's parameterized port list adapts to the new
counts automatically; just make sure your logic doesn't hard-code an index beyond the new
budget. **Do not** hand-edit pad counts to "change slot" — drive it from `SLOT`.

(Per-slot budgets are listed in
[`02_WAFERSPACE_SUBMISSION.md`](02_WAFERSPACE_SUBMISSION.md).)

---

## Verification checklist

- [ ] the counts in `slot_defines.svh` sum to the ring's physical positions
- [ ] every YAML placement name resolves to a real `chip_top` instance (no orphans)
- [ ] `chip_core` drives `oe`/`ie` for any new bidir bits; no input left floating/un-tied
- [ ] `make sim-cocotb` elaborates clean
- [ ] `make harden` **and** the precheck pass (the manufacturability gate)

---

## See also

- [`06 — Continue the Design`](06_CONTINUE_THE_DESIGN.md) — the two-layer model and
  designing your core (start here).
- [`src/README.md`](../src/README.md) — the upstream notes on slots and pad types.
- [`02_WAFERSPACE_SUBMISSION.md`](02_WAFERSPACE_SUBMISSION.md) — per-slot pad budgets.

---

| ◀ Previous | Up | Next ▶ |
| :--- | :---: | ---: |
| [06 · Continue the Design](06_CONTINUE_THE_DESIGN.md) | [Documentation map](../README.md#documentation-map) | [07 · Hardening Guide](07_HARDENING_GUIDE.md) |
