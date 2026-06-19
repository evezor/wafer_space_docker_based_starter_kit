# 05 — wafer.space Submission

You have a clean GDSII. This page bridges from "I hardened clean" to "I submitted my chip
to a wafer.space shuttle": the slot sizes and area budgets, the bond-out concept (how your
RTL signals map to physical package balls), the required tapeout cells, the seal ring, the
precheck gate, and a copy-ready pre-submission checklist.

A few facts genuinely live on the wafer.space site and change between shuttles. Those are
flagged as **"Confirm on wafer.space"** notes — follow the current instructions there
rather than anything cached here.

---

## What is wafer.space?

**[wafer.space](https://wafer.space)** is a budget silicon-manufacturing service — *"create
integrated circuits without breaking the bank."* It runs shared **GF180MCU** (GlobalFoundries
180 nm) **shuttles**: many independent designs share a single wafer, so you buy one **slot**
instead of paying for a whole run. You submit the GDSII this kit produces, and wafer.space
returns physical dies (with optional chip-on-board packaging or full undiced-wafer delivery).

- **Site / docs:** <https://wafer.space>
- **Buy a slot / current pricing:** <https://buy.wafer.space>
- **Community (Discord):** <https://discord.gg/43y2t53jpE>
- **GitHub org:** <https://github.com/wafer-space>
- **Project template (upstream):** <https://github.com/wafer-space/gf180mcu-project-template>
- **Submission precheck:** <https://github.com/wafer-space/gf180mcu-precheck>
- **Run 1 projects (descriptions + links):** <https://github.com/wafer-space/ws-run1>

> Pricing, slot sizes, and submission rules live on wafer.space and change between shuttles —
> always confirm the current details there.

---

## Where this fits

You are at the last stage. Your simulation is green, you have run `make harden` for your
slot, and `manufacturability.rpt` reads all `Passed` (see `04_HARDENING_GUIDE.md`). Now you
package and submit.

A **shuttle** is a shared manufacturing run: wafer.space produces a **multi-project wafer
(MPW)** where many independent chips share one wafer, each occupying a fixed rectangular
**slot** on a template grid.

---

## Slots and area budgets

There are four slot sizes. The kit defaults to `1x0p5`.

| Slot | Input pads | Bidir pads | Analog pads | Notes |
|---|---:|---:|---:|---|
| `1x1` | 12 | 40 | 2 | Full slot |
| **`1x0p5`** (this kit's default) | **4** | **46** | **4** | Half slot — die **3932 × 2531 µm ≈ 9.95 mm²** |
| `0p5x1` | 4 | 44 | 6 | Tall, narrow |
| `0p5x0p5` | 4 | 38 | 4 | Quarter slot |

Exact physical dimensions, read directly from the proven slot YAML files
(`librelane/slots/slot_*.yaml`). The die area already includes a 26 µm **seal ring** on
every side (see below); the placeable **core** is the die minus a ~442 µm inset per side
for the seal ring, pad ring, and corner cells.

| Slot | Die W×H (µm) | Die area | Core W×H (µm) | Core area |
|---|---|---|---|---|
| `0p5x0p5` | 1936 × 2531 | 4.90 mm² | 1052 × 1647 | 1.73 mm² |
| **`1x0p5`** (default) | 3932 × 2531 | **9.95 mm²** | 3048 × 1647 | 5.02 mm² |
| `0p5x1` | 1936 × 5122 | 9.92 mm² | 1052 × 4238 | 4.46 mm² |
| `1x1` | 3932 × 5122 | 20.14 mm² | 3048 × 4238 | 12.92 mm² |

> **Leave area headroom.** The placeable area is the *core*, not the whole die. A proven
> `1x0p5` run packed ~66,900 standard cells into its 5.02 mm² core at only **~37.5 %
> utilization**, deliberately leaving room for routing and timing slack. Don't pack a slot
> near full — to fit more logic, raise the placement density target or step up to a larger
> slot (`1x1` gives roughly 2.6× the core area of the default `1x0p5`).

---

## Choosing your slot (and how it affects pad count)

> **Pad categories are soft; only the per-slot total is hard.** Bidir pads are
> direction-configurable, so for the default `1x0p5` you have about **54 assignable signal
> pads** regardless of how the table splits them into "input" vs "bidir." (See
> `03_CONTINUE_THE_DESIGN.md` for the soft-budget rule and how to assign functions to
> pads.)

So pick your slot by the two things that are genuinely fixed: **core area** (how much logic
fits) and **total signal pads**. The default `1x0p5` is a good first choice — wide, short,
and proven. To change slot, harden with `SLOT=<name> make harden` (see
`04_HARDENING_GUIDE.md`); you never edit pad counts by hand.

---

## The pinout / bond-out concept

Inside your RTL, signals are **logical bus indices** — e.g. `bidir_PAD[0]` might be "data
out," and `bidir_PAD[8:1]` a status bus. Those indices do **not** automatically equal the
physical **package balls** (the solder contacts on the finished package that a circuit
board connects to).

wafer.space publishes a **bond-out sheet** for each slot that maps every pad-ring position
to a physical package ball. **Your job:** build a small table mapping each logical signal →
RTL pad index → physical ball, using the bond-out sheet for your chosen slot:

| Logical signal | RTL pad index | Physical ball |
|---|---|---|
| (your signal) | `bidir_PAD[n]` | (from the wafer.space bond-out sheet for your slot) |

> ℹ️ **Confirm on wafer.space:** the bond-out sheet that maps RTL pad indices to physical
> package balls for your slot (`1x0p5` by default). Translate your logical bus indices to
> physical balls using that sheet. Do not guess the mapping.

---

## Required tapeout IP cells (do not delete)

Your `chip_top.sv` instantiates identity and marker cells that wafer.space **requires** for
a valid tapeout. Each is marked "necessary for tapeout" in the template. **Do not delete
these:**

- `qrcode_id`
- `shuttle_id`
- `project_id`
- `marker`

The `logo` cell is **optional** and may be removed. These cells (and the seal ring) are a
large part of why you leave `chip_top.sv` alone — see `03_CONTINUE_THE_DESIGN.md`.

> ℹ️ **Confirm on wafer.space:** how your *per-project* QR/ID cells are issued at
> registration. The kit ships generic-but-valid versions so the scaffold hardens out of the
> box; you swap in the wafer.space-issued cells before a real tapeout. See `ip/README.md`.

---

## The seal ring

A **seal ring** is a continuous metal frame around the edge of the die that protects the
circuitry when the wafer is cut into individual chips. For this template the seal ring is
part of the slot / pad-ring infrastructure — **you do not draw it yourself**. The hardening
flow inserts it automatically (via LibreLane's `KLayout.SealRing` step), and wafer.space
does not add it later. Just don't disturb the pad-ring generate blocks in `chip_top.sv`.

---

## Run the manufacturability precheck

The wafer.space template's own final step is the **manufacturability precheck** — an
independent set of checks on your GDS, separate from LibreLane's signoff. Run it with
[gf180mcu-precheck](https://github.com/wafer-space/gf180mcu-precheck).

LibreLane's signoff (DRC / LVS / antenna, see `04_HARDENING_GUIDE.md`) is necessary, but
the precheck is the gate wafer.space expects you to pass *before* submitting. Point it at
your hardened GDS:

```bash
# from the gf180mcu-precheck checkout, after entering its nix-shell and
# exporting the PDK variables (see that repo's README)
python3 precheck.py --input final/gds/chip_top.gds --slot 1x0p5 --cob
```

Pass the **same `--slot`** you hardened with (`1x0p5` is this kit's default; the precheck
itself defaults to `1x1`, so always set it explicitly). The precheck also **renders the
layout** to an image so you can eyeball the result.

Fix anything the precheck flags, then re-harden and re-run until it is clean.

### The `--cob` pad-mask check (chip-on-board)

precheck **1.7.0** added a pad-mask check, enabled with `--cob`. It compares your pad layer
against a **golden mask** for the selected slot and confirms the layout is compatible with
the default **CoB (chip-on-board)** padring — i.e. the north/south bond pads land exactly
where the CoB package expects them. (This pairs with project template **1.5.3**, which fixed
a padring-script regression that had nudged the north/south bond pads 0.5 µm off-center.)

> ⚠️ **The pad-mask check will soon be activated on the wafer.space submission platform.**
> Until then, run the precheck locally with `--cob` to confirm a CoB-compatible layout
> before you submit. If you re-hardened with an older template, re-harden on **1.5.3+** so
> the pads are aligned again.

> ℹ️ **Confirm on wafer.space / gf180mcu-precheck:** the exact precheck invocation and any
> wafer.space-specific options for the current shuttle. Follow the precheck repository's
> README for the up-to-date command line.

---

## Pre-submission checklist

Before you submit, confirm **all** of these:

- [ ] `make sim` is **green** (your self-checking testbench passes, 0 mismatches).
- [ ] You ran `make harden` for the **correct slot** (`SLOT=1x0p5` by default).
- [ ] `manufacturability.rpt` reads **Antenna Passed / LVS Passed / DRC Passed**.
- [ ] In `metrics.json`, the DRC / LVS / antenna / density / PDN counts are **all 0**.
- [ ] **Hold timing is clean** (0 violations). (Setup may be negative — acceptable for a
      low-frequency design; see `04_HARDENING_GUIDE.md`.)
- [ ] `final/gds/chip_top.gds` **exists** and you can open it in KLayout.
- [ ] The **`gf180mcu-precheck`** passes on your GDS (the template's terminal gate),
      including the **`--cob` pad-mask check** for your slot.
- [ ] Required tapeout IP cells are present (`qrcode_id`, `shuttle_id`, `project_id`,
      `marker`).
- [ ] You have a logical-signal → physical-ball pinout table built from the bond-out sheet.
- [ ] You have read the **current** wafer.space submission instructions (format, naming,
      deadlines) on their site.

---

## The actual submission

The exact submission format, file-naming rules, and shuttle deadlines live on wafer.space
and **change over time** — always follow the current instructions there rather than
anything cached here.

> ℹ️ **Confirm on wafer.space:** the submission portal URL, the accepted file format, the
> file-naming rules, and the current shuttle deadline. These are external and shuttle-
> specific; do not rely on any value cached in this repo.

---

## You're done

Once you have submitted a clean, precheck-passing GDS for the correct slot, your part is
complete. **Fabrication, packaging, delivery, and bringing up the physical chip on a board
are handled by wafer.space and the foundry, and are beyond this kit's scope.**

If you get stuck anywhere along the way, see `06_TROUBLESHOOTING.md`.

---

| ◀ Previous | Up | Next ▶ |
| :--- | :---: | ---: |
| [04 · Hardening Guide](04_HARDENING_GUIDE.md) | [Documentation map](../README.md#documentation-map) | [06 · Troubleshooting](06_TROUBLESHOOTING.md) |
