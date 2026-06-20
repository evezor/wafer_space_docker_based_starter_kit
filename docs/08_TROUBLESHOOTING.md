# 08 — Troubleshooting

Real problems and their fixes, drawn from a proven GF180MCU build-and-harden run. Each
entry is in **symptom → cause → fix** form so a stuck beginner can self-rescue.

If a term is new, it is defined the first time it appears.

---

## How to use this page

Find the entry whose **symptom** matches what you are seeing, read the **cause** so you
understand *why*, then apply the **fix**. The entries are grouped by where in the flow you
hit them. If nothing matches, jump to "Still stuck?" at the bottom.

---

## The table

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 1 | On **Windows**, `make sim` or the Docker wrapper fails with a weird path like `C;/work` or an "invalid mount" error | Git Bash (MSYS) rewrites the `:/work` mount path before passing it to Docker | The wrapper sets **`export MSYS_NO_PATHCONV=1`** before the `docker run` (as the scaffold's `scripts/sim.sh` already does). If you call `docker` by hand, set it yourself. |
| 2 | In the Nix harden container, `ps` / `pgrep` report only "1 process" even though a flow is clearly running | `procps`'s `ps` and `pgrep` are broken in the `nixos/nix` container | **Don't trust `ps` for liveness.** Enumerate `/proc` directly (see the command block below). A live flow shows a `python3 …librelane…` process plus an `openroad` or `yosys` child. **Never `rm -rf` a run before confirming via `/proc` that it is dead.** |
| 3 | Hardening crashes at the KLayout antenna/LVS step with a Ruby `NoMethodError` on `nil.strip` (with `pmap: command not found` printed just above it) | `pmap` (from `procps`) is **missing**; the PDK's KLayout decks call `pmap` for memory logging, get back empty output, then call `.strip` on `nil` and crash | **Path A (Docker):** `docker/Dockerfile.harden` now bakes in a `pmap` shim — rebuild with **`make build-harden`**, then re-run `make harden` (or resume with `--last-run --from KLayout.Antenna`). **Path B (Nix):** **`nix profile install nixpkgs#procps`** (also un-breaks `ps`/`pgrep`, #2), then resume `--from KLayout.Antenna`. |
| 4 | Hardening fails early with `[PDN-1030] Unable to find instance i_chip_core.sram_0` | The design has **no SRAM**, but a power-delivery (PDN) or macros config still references SRAM grids | If your design has no SRAM, **do not reference SRAM anywhere** in the hardening config: no SRAM macro block or `PDN_MACRO_CONNECTIONS` in `librelane/macros/*.yaml`, and `librelane/pdn/pdn_cfg.tcl` must **not** `source` the SRAM PDN file. **The scaffold ships clean of this** — only relevant if you add or remove SRAM. |
| 5 | Setup timing won't close at 25 MHz (negative WNS) for logic with a long path | A wide multiplexer or deep combinational path is simply longer than the 40 ns clock period | **Run the chip slower.** A setup violation means "lower the clock," which is fine for a low-frequency design. Confirm **hold is clean (0)** — that is the un-fixable-post-fab failure mode. Closing 25 MHz is an architecture change (pipeline the path, or use an SRAM macro), not a re-run knob. See `07_HARDENING_GUIDE.md`. |
| 6 | Synthesis seems to hang for a very long time | Large flop arrays synthesize slowly — a 16 Kbit memory built from flip-flops can take **hours** of synthesis | **Be patient** for big designs; the trivial scaffold is fast. To speed your own: shrink large memories or back them with an SRAM macro. You can **resume** a flow past synthesis with `--last-run --from <Step>` instead of re-running it. |
| 7 | `git` is huge / the repo bloats after a harden | The final GDS is **~100 MB+** for a dense design; a full run's output can reach ~1 GB | Keep `final/` and `librelane/runs/` **gitignored** (the scaffold's `.gitignore` already does). Never commit the GDS. |
| 8 | `make pdk` times out partway through | A transient network failure on a multi-GB download | Just **re-run `make pdk`** — a retry usually completes cleanly. The PDK is ~4 GB; the Nix closure (Path B) is ~7.4 GB. Plan for the download time. |
| 9 | A testbench "passes" but you don't trust it | The pass condition might be trivially true (it can never fail) | Make the check **strict**: compare **N > 0** samples against a golden vector and require **0 mismatches**. Never loosen a self-checking testbench just to make it pass. See `06_CONTINUE_THE_DESIGN.md`. |
| 10 | KLayout / OpenROAD GUI won't open on Windows | No X server is available for the container's GUI | Run an X server (e.g. VcXsrv or WSLg) and point `DISPLAY` at it, or open the GDS in a locally installed copy of KLayout. See the note below. |
| 11 | On **Linux**, `make build-sim` (or any `docker`/`make` command) fails with `permission denied` on `/var/run/docker.sock`, and `sudo make ...` "fixes" it | Your user is **not in the `docker` group**, so only root can reach the Docker daemon | Add yourself to the group instead of using sudo: **`sudo usermod -aG docker $USER`**, then **log out and back in**. Don't keep using `sudo` — it makes container-written files root-owned. See the note below. |
| 12 | `make pdk` / `make harden` fails with **`pull access denied for gf180-waferspace-harden, repository does not exist or may require 'docker login'`** | The local hardening image was never built, and `docker compose run` tries to **pull** the local-only tag rather than build it | Build it first: **`make build-harden`** (one-time), then re-run. Current Makefiles do this automatically via a `build-harden` dependency — if you don't have that target, `git pull` to update. See the note below. |
| 13 | After you edit `chip_core.sv`, `make sim` fails to **compile/elaborate** — e.g. `error: ... is not declared`, a port width-mismatch, an inferred-latch warning, or it can't find `generated_defines.svh` | `` `default_nettype none `` turns any undeclared net into an **error** (usually a typo); or a tool was run by hand without `make defines`; or an output bus was driven without a clear-then-set (a latch) | Declare **every** signal; run **`make defines`** before hand-invoked builds (the `make` targets do it for you); drive outputs **clear-then-set** and keep the `oe` mask generate-driven. Full rules: `06_CONTINUE_THE_DESIGN.md` ("Pitfalls to avoid"). |

---

## Environment / Docker / Windows issues (#1)

On Windows, the simulation and hardening run inside Docker, and the repo is mounted into
the container. Git Bash (the MSYS shell that ships with Git for Windows) tries to be
helpful by rewriting Unix-looking paths into Windows form — which mangles the Docker mount
path and produces errors like `C;/work` or "invalid mount."

The fix is already baked into `scripts/sim.sh`:

```bash
export MSYS_NO_PATHCONV=1
```

If you ever invoke `docker run ... -v ...:/work ...` by hand from Git Bash, set the same
variable first.

> **You should see:** with `MSYS_NO_PATHCONV=1` set, the `/work` mount resolves correctly
> and the container starts without a path error.

---

## Linux Docker permissions — "needs sudo" (#11)

On Linux the Docker daemon socket (`/var/run/docker.sock`) is root-owned, so out of the box
only `root` can talk to it. A fresh install therefore makes `make build-sim` (and every other
`docker`/`make` command) fail with a **permission denied** error, and `sudo make ...` looks
like the fix.

**Don't reach for `sudo`.** The containers live-mount this repo at `/work` and write into it
(including the `./pdk` download); running them as root makes those files **root-owned**, which
causes confusing "permission denied" failures later when your normal user tries to read or
clean them. The correct, one-time fix is to add your user to the `docker` group:

```bash
sudo usermod -aG docker $USER
# then LOG OUT and back in (group membership is only picked up on a new login)
```

> **You should see:** after re-logging in, `docker run hello-world` works **without** `sudo`,
> and so do all the `make` targets. Full official steps (including rootless mode) are at
> <https://docs.docker.com/engine/install/linux-postinstall/>.

If you already ran things with `sudo` and now have root-owned files in the repo (including
`./pdk`), fix ownership with `sudo chown -R $USER:$USER .` (and re-run `make pdk` if the
`./pdk` download got tangled).

---

## "pull access denied for gf180-waferspace-harden" (#12)

```
Image gf180-waferspace-harden pull access denied for gf180-waferspace-harden,
repository does not exist or may require 'docker login'
```

`gf180-waferspace-harden` is a **local** image tag — it is built on your machine from
`docker/Dockerfile.harden`, and lives on no public registry. When the image hasn't been built
yet, `docker compose run` (used by `make pdk` / `make harden`) tries to **pull** that tag
instead of building it, and the pull fails with the message above. (`sudo` is unrelated — it
fails the same way with or without it.)

The fix is simply to build the image first:

```bash
make build-harden     # one-time: docker compose build harden
```

Current Makefiles wire this in automatically — `pdk`, `harden`, and the `open-*` targets all
depend on `build-harden`, so a clean checkout never hits this. If your tree has no
`build-harden` target, you're on an older copy; `git pull` to update.

> **You should see:** `make build-harden` build (or reuse a cached) `gf180-waferspace-harden`
> image, after which `make pdk` and `make harden` proceed without the pull error.

---

## Process-liveness & monitoring in the Nix container (#2, #3)

Inside the `nixos/nix` container used for Path B hardening, the usual process tools are
unreliable. **Do not trust `ps` or `pgrep`** to tell you whether a long run is still alive.
Instead, inspect `/proc` (the kernel's per-process directory) directly:

```bash
for p in /proc/[0-9]*; do tr '\0' ' ' < $p/cmdline; echo; done \
  | grep -E 'openroad|librelane|make'
```

> **You should see:** for a live flow, a `python3 …librelane…` process plus an `openroad`
> or `yosys` child. If you see those, the run is working — be patient. If you see nothing,
> the flow has exited.

> ⚠️ **Never `rm -rf` a run directory before confirming via `/proc` that the flow is
> actually dead.** Deleting a running flow's directory corrupts the run.

If hardening crashes at the KLayout antenna or LVS step with a Ruby `NoMethodError` on
`nil.strip` (#3) — usually with `sh: pmap: command not found` printed just above it — the
cause is a missing `pmap` (a memory-reporting tool from the `procps` package that the PDK's
KLayout decks call for logging). The fix depends on which path you hardened with.

**Path A (Docker)** — the default `make harden`. The official LibreLane image ships no
`pmap` either, so the scaffold's `docker/Dockerfile.harden` bakes in a tiny `pmap` shim. If
you hit this crash, you're running an image built **before** that fix — rebuild it, then
re-run:

```bash
make build-harden     # rebuild the harden image (now with the pmap shim)
make harden           # re-run (or resume — see below)
```

**Path B (Nix)** — install `procps` into your profile, which also fixes the `ps`/`pgrep`
breakage above:

```bash
nix profile install nixpkgs#procps
```

> **You should see:** `pmap` available on the `PATH`, after which you can resume the flow
> from the failed step instead of re-running the whole thing — append to the **same**
> librelane command you ran:
>
> ```bash
> #   ... --save-views-to /work/final  --last-run --from KLayout.Antenna
> ```

---

## Hardening / LibreLane issues (#4)

If hardening fails early with `[PDN-1030] Unable to find instance i_chip_core.sram_0`, the
config is referencing an **SRAM** (on-chip static RAM macro) that does not exist in your
design. **PDN** is the *power-delivery network* — the on-die grid of power and ground
wires.

The scaffold is **SRAM-free** and ships clean of this. The error only appears if you add or
remove SRAM and leave a dangling reference. If your design has no SRAM, make sure nothing
mentions SRAM:

- No SRAM macro block or `PDN_MACRO_CONNECTIONS` in `librelane/macros/*.yaml`.
- `librelane/pdn/pdn_cfg.tcl` must **not** `source` the SRAM PDN file.

> **You should see:** with all SRAM references removed, the floorplan and PDN steps complete
> without the `PDN-1030` error.

If you *do* add SRAM, you must wire the macro into both the macros YAML and the PDN — see
`06_CONTINUE_THE_DESIGN.md` for the "add new RTL" rules.

---

## Resource & patience issues (#6, #7, #8)

Several "failures" are really just the flow being big and slow. Know these up front so a
long run does not look like a hang:

- **Synthesis can take hours** for large flop arrays (#6). The scaffold is fast. Confirm
  the run is alive (see #2) rather than killing it. To resume past a completed step instead
  of re-running, use `--last-run --from <Step>`.
- **The final GDS is large** (#7) — ~100 MB+ for a dense design, with full run output near
  1 GB. Keep `final/` and `librelane/runs/` gitignored (the scaffold already does) and
  never commit the GDS. The value you commit is *source + config*, not generated layout.
- **Downloads are multi-GB** (#8). The PDK is ~4 GB; the Nix closure is ~7.4 GB. If
  `make pdk` times out, just re-run it.

---

## Timing issues (#5)

If setup timing won't close at 25 MHz, that is usually fine — see #5 in the table and the
full explanation in `07_HARDENING_GUIDE.md`. The short version:

- **Setup** violations mean "run the chip slower." Acceptable for a low-frequency design.
- **Hold** violations are **not** acceptable — they cannot be fixed after fabrication, so
  confirm hold is 0 before you submit.

---

## Simulation issues (#9)

If a testbench passes but you don't trust it, the pass condition is probably too weak. Make
it strict: compare **more than zero** samples against a committed golden vector and require
**0 mismatches**. A test you can cheat is worse than no test. The recommended
golden-model pattern is in `06_CONTINUE_THE_DESIGN.md`.

---

## RTL compile / lint errors after editing `chip_core.sv` (#13)

The moment you change `chip_core.sv`, the fast Icarus build (`make sim`) becomes your lint
gate. Three failures are common the first time — all are *your RTL*, not the kit:

- **`error: <name> is not declared`.** `` `default_nettype none `` is in force, so an
  undeclared signal is a hard error (not an implicit 1-bit wire). It is almost always a typo
  or a missing `logic`/`wire` declaration. Declare every net explicitly.
- **A width mismatch or an inferred *latch* warning.** Usually an output bus driven on only
  some paths. Drive outputs **clear-then-set**: assign the whole vector to `'0` first, then
  set the bits you use (and keep the `oe` mask generate-driven). Every bit then has a defined
  value with no latch.
- **It can't find `generated_defines.svh` (or a `SLOT_*` macro is undefined).** The RTL
  `` `include``s a *generated* file. The `make` targets run `make defines` for you; if you
  invoked `iverilog` by hand, run **`make defines`** first.

> **You should see:** after fixing, `make sim` compiles and runs to the
> `==== … 0 mismatches ====` / `OK` banner. These rules are spelled out in
> `06_CONTINUE_THE_DESIGN.md` ("Pitfalls to avoid").

---

## Windows GUI viewing (#10)

`make open-klayout` and `make open-openroad` launch GUI tools inside a container, which need
a display.

> ℹ️ **Note (Windows):** install and run an X server (such as VcXsrv, or use WSLg on
> Windows 11), point the `DISPLAY` environment variable at it, then re-run the
> `make open-*` target. Alternatively — and often simpler — install KLayout natively on
> Windows and open `final/gds/chip_top.gds` directly. GUI viewing is optional; the flow is
> Linux/macOS-first, and a ready-made render is always written to
> `final/render/chip_top.png`.

---

## Still stuck?

- **LibreLane documentation** — the flow's own reference:
  <https://librelane.readthedocs.io>
- **wafer.space** — the community and site for shuttle-specific questions (submission
  format, slots, bond-out sheets). See `02_WAFERSPACE_SUBMISSION.md`.
- **The upstream template** — a known-good reference tree to diff your repo against:
  <https://github.com/wafer-space/gf180mcu-project-template>

When in doubt, compare your config against the template: most harden failures come from a
local edit that drifted away from the proven baseline.

---

| ◀ Previous | Up | Next ▶ |
| :--- | :---: | ---: |
| [07 · Hardening Guide](07_HARDENING_GUIDE.md) | [Documentation map](../README.md#documentation-map) | [Back to the README](../README.md) |
