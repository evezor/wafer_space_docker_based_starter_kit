# 03 — Paths to a wafer.space Die

*Optional — orientation.* This kit is **one** way to get a chip onto a
[wafer.space](https://wafer.space) shuttle: you design a whole slot and harden it yourself.
This page puts that in context — what wafer.space is, the broad paths onto a shuttle, what
**every** wafer.space die needs regardless of path, and (if you arrive from a hosted flow)
what changes when you go direct.

> **The center of gravity is wafer.space.** Whatever flow you use, the thing that gets
> manufactured is a **GDSII for a slot on a wafer.space GF180MCU shuttle.** This kit takes
> you straight there.

---

## wafer.space is the destination

[wafer.space](https://wafer.space) is a *budget silicon-manufacturing* service. It runs
shared **GF180MCU** (GlobalFoundries 180 nm) **shuttles**: many independent designs share a
single wafer, so you buy one **slot** instead of paying for a whole manufacturing run, and
you get physical dies back. (The README's [Targeting wafer.space](../README.md#targeting-waferspace)
section and [`02_WAFERSPACE_SUBMISSION.md`](02_WAFERSPACE_SUBMISSION.md) have the specifics —
slot sizes, pricing pointers, submission rules.)

Every route below ends at the same place: a clean GDSII submitted to a wafer.space shuttle.
The routes differ only in **how much of the chip you build yourself.**

---

## Two broad paths onto a shuttle

| | **Direct / full-slot** (this kit) | **Hosted / aggregated** |
|---|---|---|
| What you design | a **whole slot** — your own die | a small **tile** inside a fixed wrapper |
| Padring, power, tapeout IP | **you own it** (ships ready in `chip_top.sv`) | the platform provides it |
| Who hardens it | **you**, locally (`make harden`: Docker or Nix) | the platform's CI (you push code) |
| Who submits it | **you** send the GDSII to wafer.space | the platform aggregates many tiles and submits |
| I/O budget | the full slot (`1x1` = 12 input + 40 bidir + 2 analog, ~52 signal pads) | a small fixed bus |
| You get | maximum **control** (area, pads, analog, floorplan, timing) | maximum **convenience** (smallest, cheapest, easiest on-ramp) |
| Tools to install | Docker (or Nix) | usually none — a browser + GitHub |

Both paths can land on the **same process**: a hosted aggregator's GF180 shuttle is itself
manufactured through wafer.space. The most prominent example is **TinyTapeout** — its
[GF180 shuttle](https://github.com/TinyTapeout/ttgf-verilog-template) builds with LibreLane
and is produced *via wafer.space*. So "a hosted tile" and "a direct slot" are two ends of
the same road, not different roads.

The upstream [wafer.space project template](https://github.com/wafer-space/gf180mcu-project-template)
is the canonical *direct* path; **this kit is that template plus a Docker flow, beginner
docs, and a known-green example.**

---

## What every wafer.space die needs (regardless of path)

These are true no matter how you get there — the hosted platforms just do them *for* you,
and this kit ships them ready:

- A **GDSII** sized to a slot.
- A **padring** of foundry I/O cells around the edge (`src/chip_top.sv`).
- The required **tapeout marker IP** — `qrcode_id`, `shuttle_id`, `project_id`, `marker`
  (the `logo` cell is optional).
- Clean **signoff**: DRC (geometry legal), LVS (layout matches netlist), antenna — every
  count `0`.
- A passing **precheck** ([`gf180mcu-precheck`](https://github.com/wafer-space/gf180mcu-precheck)).
- A **bond-out / pinout** so the package or board knows which pad is which.

The full mechanics are in [`02_WAFERSPACE_SUBMISSION.md`](02_WAFERSPACE_SUBMISSION.md). The
point here: when you go direct, *these become your responsibility* — and the scaffold
already satisfies all of them, so you inherit a passing baseline and only change your logic.

---

## Which path is for you

- **Go hosted/aggregated** if you want the smallest, cheapest unit, the easiest on-ramp, no
  tools to install, and a fixed small I/O bus is enough.
- **Go direct/full-slot (this kit)** if you want a whole die, the full pad budget, **analog
  pads**, control over floorplan and timing, or you've simply outgrown a single tile.

Outgrowing a tile is the common reason people land here — which is the next section.

---

## Coming from a hosted flow (e.g. TinyTapeout)

If you've done a tile-based project, you already know the open toolchain and the
"RTL → GDSII → shared shuttle" idea. Going direct changes three things; everything else
carries over.

**1 — You now own the padring.** A hosted wrapper hands you a fixed bus and hides the pads.
Here you write `chip_core` and drive the *real* pad contract (full rules in
[`06_CONTINUE_THE_DESIGN.md`](06_CONTINUE_THE_DESIGN.md)). The TinyTapeout bus maps onto it
like this:

| Hosted wrapper (`tt_um_*`) | This kit (`chip_core`) | Note |
|---|---|---|
| `ui_in[7:0]` (dedicated inputs) | `input_in[7:0]` | `1x1` has 12 input-only pads — all 8 fit directly |
| `uo_out[7:0]` (dedicated outputs) | `bidir_out[i]` with `bidir_oe[i]=1` | no output-only pad type — an output is a bidir with `oe=1` |
| `uio_in/uio_out/uio_oe[7:0]` | `bidir_in/bidir_out/bidir_oe` | same `oe` sense (1=output) — but you also drive `bidir_ie=~oe` and `bidir_pu/pd/cs/sl` |
| `ena` | *(none)* | no mux — your die is always active; tie to `1` if wrapping a `tt_um` |
| `clk`, `rst_n` | `clk`, `rst_n` | dedicated pads — identical |
| *(none)* | `analog[1:0]` | 5 V analog pads you didn't have before |

Because the buses line up, you can keep a `tt_um_<name>` module unchanged and make
`chip_core` a thin wrapper around it (instantiate it, tie `ena=1`, add `bidir_ie=~bidir_oe`
and `pu/pd/cs/sl='0`).

**2 — You run the tools.** Push-to-CI becomes local commands: `make sim` (fast Icarus
self-check vs a golden vector, no PDK) then `make harden` (LibreLane locally). See
[`04_THE_FLOW.md`](04_THE_FLOW.md).

**3 — You submit.** You produce the GDSII, keep the tapeout marker IP, run the precheck, and
assemble the bond-out yourself — the checklist in
[`02_WAFERSPACE_SUBMISSION.md`](02_WAFERSPACE_SUBMISSION.md).

---

## Footholds

- **wafer.space** — [wafer.space](https://wafer.space) · [buy a slot](https://buy.wafer.space) · [Discord](https://discord.gg/43y2t53jpE) · [GitHub org](https://github.com/wafer-space).
- **The canonical direct template** — [gf180mcu-project-template](https://github.com/wafer-space/gf180mcu-project-template).
- **Start driving this kit** — [`01_GETTING_STARTED.md`](01_GETTING_STARTED.md) → [`04_THE_FLOW.md`](04_THE_FLOW.md) → [`06_CONTINUE_THE_DESIGN.md`](06_CONTINUE_THE_DESIGN.md).
- **A hosted on-ramp that targets wafer.space** — TinyTapeout's [GF180 template](https://github.com/TinyTapeout/ttgf-verilog-template).

---

| ◀ Previous | Up | Next ▶ |
| :--- | :---: | ---: |
| [02 · wafer.space Submission](02_WAFERSPACE_SUBMISSION.md) | [Documentation map](../README.md#documentation-map) | [04 · The Flow](04_THE_FLOW.md) |
