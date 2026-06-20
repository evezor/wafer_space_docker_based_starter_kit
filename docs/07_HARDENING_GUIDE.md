# 07 — Hardening Guide

This is the complete reference for turning your RTL into a manufacturable layout. It
covers both ways to run the flow, the exact commands, what to expect in time and disk, how
to read the output, what a clean signoff looks like, and how to open the results.

If a term is new, it is defined the first time it appears.

---

## What "hardening" is (and when to do it)

**Hardening** is the process that turns your register-transfer-level (RTL) Verilog into a
**GDSII** — the geometric layout file (polygons on each layer) that a foundry uses to
manufacture the chip. The flow synthesizes your logic into standard cells, places them,
routes the wires, builds a power grid, and runs the physical signoff checks.

The kit uses **LibreLane**, an open-source RTL-to-GDSII flow.

> **Rule: never harden a design whose simulation is not green.** Hardening can take from
> tens of minutes to several hours. Catch logic bugs in the fast simulation loop first
> (see `06_CONTINUE_THE_DESIGN.md`). Harden only on green.

---

## The two paths — pick one

There are two ways to run the flow. **Both produce the same GDSII.**

| | **Path A — Docker (default, recommended)** | **Path B — Nix (advanced)** |
|---|---|---|
| What it uses | The official prebuilt **LibreLane** Docker image | A `flake.nix` plus a `nix develop` shell |
| Install | Docker Desktop (you already have it) | Install Nix (a multi-GB toolchain closure, ~7.4 GB) |
| Command | `make harden` (uses the dockerized LibreLane) | `nix develop`, then `make harden` inside the shell |
| Best for | Almost everyone; your first chip | Power users who already live in Nix, or who want the template's blessed flow |
| Reproducibility | High (pinned image) | Highest (pinned flake) |

> **Pick Path A unless you have a specific reason not to.** Again — both produce the same
> GDSII.

---

## Step 1 — Fetch the PDK (one time)

The **PDK** (Process Design Kit) is the foundry's data package: the standard-cell library,
the I/O pad cells, layer rules, and timing models for the GF180MCU process. The flow
cannot run without it. Fetch it once:

```bash
make pdk
```

> **You should see:** `ciel` (the PDK manager) downloading the **gf180mcuD** PDK, pinned at
> commit `019cf7a3e0de79bb0e4b6213758882d283c65816`, about **4 GB**. This is a one-time
> download — it lands in the local `./pdk` folder and is reused by every harden. If the
> download times out mid-stream, just run `make pdk` again; a retry usually completes
> cleanly.

---

## Step 2A — Harden (Path A, default Docker)

From the repo root. The default slot is `1x0p5`.

```bash
make pdk        # one-time (skip if already done)
make harden     # RTL -> GDSII via the prebuilt LibreLane Docker image
```

> **You should see:** LibreLane stepping through roughly 80 numbered stages (synthesis,
> floorplan, placement, routing, signoff…) and finishing by writing the final views. The
> end of a clean run reports the signoff as passed (see "What a clean signoff looks like"
> below).

To target a different slot, prefix the command with `SLOT=`:

```bash
SLOT=1x1 make harden     # harden for the full 1x1 slot instead of the default 1x0p5
```

`make` auto-runs `make defines` first, so the right per-slot pad-count macros are
generated before the build.

---

## Step 2B — Harden (Path B, advanced Nix)

Path B is the template's own flow: a Nix shell that pulls LibreLane (pinned in
`flake.lock` to the `dev` branch) and all the EDA (electronic design automation) tools
from the FOSSi Foundation binary cache — prebuilt, with no source compilation.

```bash
# enter the pinned toolchain shell
# (the first time, this materializes ~7.4 GB from the cache)
nix develop --accept-flake-config
```

> **You should see:** Nix downloading and unpacking the toolchain closure, then dropping
> you into a new shell prompt. Subsequent entries are near-instant because the closure is
> cached.

Then, **inside that shell**:

```bash
SLOT=1x0p5 PDK_ROOT=<your-pdk-path> make harden
```

> **You should see:** the same ~80-step LibreLane flow as Path A, ending in the same clean
> signoff and the same GDSII.

A convenience target, `make harden-nix`, wraps this for you if you prefer not to enter the
shell by hand.

---

## Expected cost — time, disk, memory

Set your expectations before you start a run. These numbers come from a proven reference
build.

| Resource | Expect |
|---|---|
| PDK download | ~4 GB, one-time |
| Nix closure (Path B) | ~7.4 GB, one-time |
| Build run time | Tens of minutes to **several hours**, **dominated by synthesis** of large flop arrays. A design with sizable flop-built memory can take hours of synthesis alone — the trivial scaffold is far faster. |
| Memory | Multi-GB; the static-timing (STA) and place-and-route (PnR) steps are the heaviest. |
| Final GDS size | **~100 MB+** for a dense design (the reference build was ~112 MB; the scaffold is far smaller). Keep `final/` **gitignored**. |

> A long synthesis is **not** a hang. If a run seems stuck, see `08_TROUBLESHOOTING.md`
> (symptom #6) before killing it — large flop arrays simply take a long time.

---

## Reading the run output

Each `make harden` creates a timestamped run folder. The deliverables are also copied to
the repo's top-level `./final/`.

```
librelane/runs/RUN_<timestamp>/
├── <NN>-<step>/        # one numbered folder per flow step (synthesis, floorplan, …)
├── final/              # the deliverables (also copied to repo ./final/)
│   ├── gds/chip_top.gds
│   ├── nl/  pnl/        # logical + physical netlists
│   ├── spice/  def/  lib/  sdc/
│   └── metrics.json  manufacturability.rpt  render/chip_top.png
└── ...
```

The flow runs about 80 numbered steps; the last one saves the final views. **The first
file you open after a run is `manufacturability.rpt`** — the human-readable verdict.

---

## What a clean signoff looks like

**Signoff** is the set of physical checks a fab actually requires. There are three
headline ones:

- **DRC — Design Rule Check (geometry).** Does the layout obey the foundry's manufacturing
  rules (minimum metal widths, spacings, density)? Run by Magic, KLayout, and OpenROAD's
  router. "Pass" = 0 violations from each checker.
- **LVS — Layout vs. Schematic.** Does the physical layout's extracted transistor netlist
  match the intended netlist — same devices, same nets, same connectivity? Run by Netgen.
  This is the most important check: it proves *the transistors on the die are the circuit
  you simulated.*
- **Antenna check — charge-damage protection.** During fabrication, a long bare metal wire
  can accumulate plasma-induced charge that punches through and damages a thin transistor
  gate before higher layers are added. The check finds such wires; LibreLane repairs them
  automatically (by inserting diodes or rerouting). "Pass" = 0 violating nets / 0 violating
  pins.

A clean `manufacturability.rpt` reads **exactly**:

```
* Antenna
Passed

* LVS
Passed

* DRC
Passed
```

And in `metrics.json` (the machine-readable scoreboard), these counts should all be **0**:

| Check | Tool | Clean value |
|---|---|---|
| Magic DRC / KLayout DRC / routing DRC / density | Magic, KLayout, OpenROAD | 0 / 0 / 0 / 0 |
| LVS device / net / pin diffs | Netgen | 0 / 0 / 0 |
| Antenna violating nets / pins | OpenROAD + KLayout | 0 / 0 |
| Power grid (PDN) | OpenROAD PSM | 0 |
| Unmapped cells / flow errors | LibreLane | 0 / 0 |

The exact keys to look for in `metrics.json`:

```
"magic__drc_error__count": 0
"klayout__drc_error__count": 0
"klayout__antenna_error__count": 0
"klayout__density_error__count": 0
"route__drc_errors": 0
"antenna__violating__nets": 0
"antenna__violating__pins": 0
"design__lvs_error__count": 0
"design__lvs_device_difference__count": 0
"design__lvs_net_difference__count": 0
"design__lvs_unmatched_pin__count": 0
"design__power_grid_violation__count": 0
"flow__errors__count": 0
```

> **LVS = 0 is the one that matters most.** It proves the transistors on the die *are* the
> circuit you simulated. (Routing DRC converges to zero over iterations — it is normal to
> see `route__drc_errors__iter:0: 130 → … → route__drc_errors: 0`.)

---

## Opening the results

Look at what you built.

```bash
make open-klayout    # opens the final GDS in KLayout (look at the layout)
make open-openroad   # opens the design in OpenROAD (interactive inspection)
```

> **You should see:** KLayout render the die — a pad ring framing a dense logic core with a
> top-metal power grid. There is also a ready-made picture at
> `final/render/chip_top.png`.

> ℹ️ **Note (Windows):** the GUI tools run inside a container and need a display. On
> Windows you will need an X server (e.g. VcXsrv or WSLg) with `DISPLAY` pointed at it, or
> you can open `final/gds/chip_top.gds` in a locally installed copy of KLayout. See
> `08_TROUBLESHOOTING.md` (symptom #10).

---

## The deliverables in `final/`

Everything the flow produces lands here.

| File | What it is |
|---|---|
| `gds/chip_top.gds` | **The GDSII** — what you submit to the fab. |
| `nl/*.v`, `pnl/*.v` | Logical and physical (post-layout) netlists. |
| `spice/*.spice` | Transistor-level netlist (for LVS / SPICE simulation). |
| `def/*.def` | Placement and routing in DEF (Design Exchange Format). |
| `lib/*.lib` | Timing models (Liberty) — one per process corner. |
| `sdc/*.sdc` | The timing constraints used. |
| `metrics.json` / `.csv` | All the signoff counts. |
| `manufacturability.rpt` | The all-Passed report. |
| `render/chip_top.png` | A picture of your die. |

---

## Getting your files out of the container

A common worry with Docker is that your results are "trapped" inside the container. **They
are not.** Both the sim and harden containers **bind-mount this repo** at `/work` (see
`docker-compose.yml`: `.:/work`), which means anything the tools write *under the repo
tree* is written straight to your real filesystem — the same bytes, the same files, no
copy-out step. The container and your host are looking at one directory.

So the outputs you care about are already on your machine, at these paths in the repo:

| Output | Lands on your host at | Produced by |
|---|---|---|
| The GDSII + all signoff views | `final/` | `make harden` (`--save-views-to /work/final`) |
| The full per-run output (logs, every step, reports) | `librelane/runs/RUN_<timestamp>/` | `make harden` |
| The simulation waveform | `chip_core.vcd` (repo root) | `make sim` (`$dumpfile` in `tb/tb_chip_core.sv`) |
| cocotb results | `cocotb/sim_build/`, `cocotb/results.xml` | `make sim-cocotb` |

Open any of them with your normal host tools — load `chip_core.vcd` in GTKWave, open
`final/gds/chip_top.gds` in a natively installed KLayout, read `final/manufacturability.rpt`
in your editor. No extraction needed. (`final/` and `librelane/runs/` are gitignored — that
is deliberate; they are build output, not source.)

### The PDK is a folder too — `./pdk`

The PDK is the one big *input* (rather than an output), but it is **also just a host
folder**. `docker-compose.yml` bind-mounts it into the containers at `/pdk` from
`${PDK_ROOT:-./pdk}`, so `make pdk` downloads the ~4 GB straight into `./pdk` in your repo.
You can see it, back it up, or delete it with a plain `rm -rf pdk` — there is no Docker
volume to learn or manage. It is gitignored, so it never bloats your history. To share one
download across several checkouts, set `PDK_ROOT` (in `.env` or your shell) to a path
outside the repo.

### Why there is no `docker cp` step here

If you have used Docker before you might reach for `docker cp <container>:/path ./`. That
will not work here, and you do not need it: **every target in this kit runs the container
with `--rm`** (`docker compose run --rm …`), so the container is deleted the instant the
command finishes — there is no leftover container to copy from. The bind mount is what makes
that safe: results are already on your host before the container exits.

The practical rule that follows: **write outputs under `/work`** (anywhere in the repo tree)
and they persist automatically. If you run a custom command that writes somewhere else
inside the container — `/tmp`, `/root`, `~` — that file dies with the `--rm` container.
Either redirect it under `/work`, or run an interactive container *without* `--rm` and
`docker cp` it out before removing the container by hand.

> 🐧 **Linux note:** files the container writes into the repo — including the `./pdk`
> download — may come out **root-owned** (the container runs as root unless you have set up
> the docker group). If you later cannot read or `make clean` them, fix ownership with
> `sudo chown -R $USER:$USER .`. The root cause and the proper one-time fix (the `docker`
> group) are in `08_TROUBLESHOOTING.md`, #11.

---

## The setup-timing caveat (usually fine for low-frequency designs)

The template ships a default timing constraint of **40 ns / 25 MHz** on the clock pad
(`clk_PAD`). Timing closure has two halves:

- **Setup timing** asks: does each signal arrive *before* the next clock edge? A design
  with a long combinational path (e.g. a wide multiplexer or a deep arithmetic chain) may
  **not** close setup at 25 MHz.
- **Hold timing** asks: does each signal hold steady *long enough after* the clock edge?

> **A setup failure is usually fine — it just means "run the chip slower."** For a
> low-frequency design, drive the clock well below 25 MHz in the field and the setup
> violation disappears. **Hold timing, however, must be clean (0 violations)** — that is
> the failure mode you *cannot* fix after fabrication. The flow inserts hold-fix buffers
> automatically, and a clean run reports 0 hold violations.

Closing 25 MHz later is an *architecture* change (pipeline the long path, or back a memory
with an SRAM macro), not a re-run knob. The trivial scaffold closes timing comfortably at
25 MHz.

When you check your run, make sure **hold is 0** even if setup is negative. The
pre-submission checklist in `02_WAFERSPACE_SUBMISSION.md` calls this out explicitly.

---

## If something goes wrong

Hardening surfaces a handful of recurring, well-understood problems — Windows mount paths,
process-liveness inside the Nix container, a missing `pmap`, stray SRAM references, long
synthesis, big GDS files, and PDK download timeouts. Each has a known fix in
`08_TROUBLESHOOTING.md`. Check there before you assume the flow is broken.

---

**Next:** `02_WAFERSPACE_SUBMISSION.md` — go from a clean GDSII to a submitted shuttle
entry.

---

| ◀ Previous | Up | Next ▶ |
| :--- | :---: | ---: |
| [06 · Continue the Design](06_CONTINUE_THE_DESIGN.md) | [Documentation map](../README.md#documentation-map) | [08 · Troubleshooting](08_TROUBLESHOOTING.md) |
