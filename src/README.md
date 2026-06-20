# src/ — the RTL

Three real files plus this README. Read them top to bottom once; the comments
are the tutorial.

| File                | What it is                                  | Edit it? |
|---------------------|---------------------------------------------|----------|
| `chip_top.sv`       | The padring. Instantiates one foundry I/O   | **NO** — copied from the |
|                     | cell per pad and a single `chip_core`. Also | wafer.space template. Touch |
|                     | instantiates the required wafer.space       | only to change slot/pad type. |
|                     | tapeout marker IP (qrcode/shuttle/project/  |          |
|                     | marker/logo).                               |          |
| `slot_defines.svh`  | Pad-count table per wafer.space slot. Select | **NO** — pick a slot via a |
|                     | a slot with a `SLOT_*` define.              | `SLOT_*` define instead. |
| `chip_core.sv`      | **Your design.** Sits behind the padring.   | **YES — this is the file** |
|                     | Ships as a trivial heartbeat counter.       | **you edit.** |

#### The pad contract (what chip_core must always provide)

`chip_top` wires each pad cell to `chip_core` like this:

- **Inputs** (`input_in[i]`): data into the core. The core drives each pad's
  pull config via `input_pu` / `input_pd` (scaffold: both 0 = no pulls).
- **Bidir** (`bidir_*`): each bit is independently an OUTPUT or an INPUT.
  - OUTPUT bit: `bidir_oe[i]=1`, `bidir_ie[i]=0`, data on `bidir_out[i]`.
  - INPUT  bit: `bidir_oe[i]=0`, `bidir_ie[i]=1`, data read from `bidir_in[i]`.
  - **You must drive `bidir_ie = ~bidir_oe` yourself** — the pad cell does not.
  - `bidir_cs/sl/pu/pd` are drive/slew/pull config (scaffold: all 0).
- **Analog** (`analog[i]`): straight-through analog pads, no digital control.
  The scaffold does not use them.
- `clk` and `rst_n` (active-low) come from dedicated pads.

#### Editing chip_core safely

1. Keep the **port list and parameters exactly as shipped** — `chip_top`
   instantiates them by name.
2. Keep the **pad-config assigns** (`input_pu/pd`, `bidir_oe/ie/cs/sl/pu/pd`):
   set `bidir_oe[i]` per bit, always drive `bidir_ie = ~bidir_oe`.
3. Build outputs in a **clear-then-set `always @(*)`** (assign `'0` first, then
   the used bits) so there are no latches and every bit has a defined value.
4. Fold unused inputs into the `_unused` net so `-Wall` stays quiet.
5. Re-run the simulation (../tb) — it must stay green — then re-harden.

#### Changing slots

Default slot is `1x1` (12 input / 40 bidir / 2 analog pads). To target a
different slot, define a different `SLOT_*` macro at build time (see
`slot_defines.svh` for the options) and update the docs/Makefiles to match.
You do **not** edit the pad counts by hand.

#### Where this comes from

`chip_top.sv`, `slot_defines.svh`, and the pad ring are the wafer.space project
template's, copied in unchanged. You own `chip_core.sv`. For the upstream, full
production flow, see https://github.com/wafer-space/gf180mcu-project-template.
