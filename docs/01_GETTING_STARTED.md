# 01 · Getting Started

This page takes you from "nothing installed" to a **green example simulation** — proof that the whole kit works on your machine — and then to your **first real chip layout**, the GDSII you submit in the next chapter. Every step has a success signal so you always know whether it worked.

> New to the words *PDK*, *RTL*, *GDSII*, *shuttle*? Read [`00_ASIC_FOR_BEGINNERS.md`](00_ASIC_FOR_BEGINNERS.md) first. It is a quick, tool-free primer.

---

## What you'll achieve

By the end of this page you will have simulated a real (tiny) chip design on your own machine, seen it pass its self-check, and hardened it into a manufacturable layout. The simulation part takes about **10 minutes** and a few GB of disk. The hardening part (making the actual layout you submit) downloads several more GB and runs for a while — do it once the simulation is green.

| Part | Roughly how long | What you get |
|---|---|---|
| Install Docker + git | 10–20 min (one-time) | The tools that run everything |
| Clone + build sim image | ~5 min (one-time) | A container with Icarus + Python + cocotb |
| Run the example sim | seconds | **A green light: the kit works** |
| Fetch PDK + harden the sample | 30 min – a few hours | A clean, manufacturable GDSII — ready to submit |

---

## Prerequisites

You need just a few things. The whole point of this kit is that you do **not** install any chip-design software directly — Docker runs all of it inside containers.

| You need | Why | Notes |
|---|---|---|
| **Docker** | Runs all the chip tools in containers so you install nothing by hand | Docker Desktop on Windows/macOS (enable the **WSL2** backend on Windows); Docker **Engine** on a headless Linux server. |
| **WSL2** (Windows only) | Docker's Linux backend; also where `make` runs | Install via `wsl --install` in an admin PowerShell, then reboot. |
| **git** | To clone this repo | Any recent version. |
| **make** | The front door — every command in this kit is `make <target>` | Preinstalled on most Linux/WSL and macOS. If missing: Linux/WSL `sudo apt-get install -y make`; macOS `xcode-select --install`. On Windows, run `make` from inside WSL, not PowerShell. |
| **Disk space** | Images + PDK + a build run are large | Keep **~30 GB** free. The PDK is ~4 GB; a final GDS can be 100 MB+. |

---

## Step 1 — Install Docker Desktop

Download Docker Desktop from [docker.com](https://www.docker.com/products/docker-desktop/) and install it for your operating system.

- **Windows:** During or after install, make sure the **WSL2 backend** is enabled (Docker Desktop → Settings → General → "Use the WSL 2 based engine"). See Step 1b below to install WSL2 itself.
- **macOS:** Install the build that matches your chip (Apple Silicon or Intel). No extra backend setup needed.
- **Linux:** Docker Desktop works, but on a **headless server (no GUI)** you do **not** want Desktop — install **Docker Engine** instead, straight from Docker's package repos: <https://docs.docker.com/engine/install/>. Pick your distro on that page.

After installing, start Docker (Desktop reports when it is running; Engine starts via `sudo systemctl enable --now docker`).

> 🐧 **Linux post-install — do this or you'll be stuck typing `sudo` (and breaking file ownership).** By default only `root` can talk to the Docker daemon, so plain `docker`/`make` commands fail with a *permission denied* error and `sudo make ...` looks like the fix. **It isn't** — running the containers as root makes every file they write into the repo (including the `./pdk` download) root-owned, which causes confusing failures later. Instead, add yourself to the `docker` group once, then **log out and back in**:
>
> ```bash
> sudo usermod -aG docker $USER
> ```
>
> Full official steps (including rootless mode): <https://docs.docker.com/engine/install/linux-postinstall/>. After re-logging in, `docker run hello-world` should work **without** `sudo`.

```bash
docker --version
```

> **You should see:** a version line such as `Docker version 27.x.x, build ...`. If the command is not found, Docker is not installed or not on your PATH.

### Step 1b — Install WSL2 (Windows only)

On Windows, Docker runs on top of **WSL2** (Windows Subsystem for Linux). It is also where you will run `make`. Open **PowerShell as Administrator** and run:

```powershell
wsl --install
```

> **You should see:** WSL downloading and installing a Linux distribution (Ubuntu by default), then a prompt to reboot. After rebooting, open the "Ubuntu" app once to finish setup. Run all the `make` commands in this kit from inside that WSL/Ubuntu shell.

---

## Step 2 — Install git

You need git to download (clone) this repository.

```bash
git --version
```

> **You should see:** a version line such as `git version 2.4x.x`. If git is missing: on Windows/WSL run `sudo apt-get update && sudo apt-get install -y git`; on macOS run `xcode-select --install`; on Linux use your package manager.

---

## Step 3 — Clone the repo

Get the code and move into it.

```bash
git clone https://github.com/evezor/wafer_space_docker_based_starter_kit.git
cd wafer_space_docker_based_starter_kit
```

> **You should see:** git report `Cloning into 'wafer_space_docker_based_starter_kit'...` and finish without errors, leaving you inside the new directory. Run `ls` to confirm you see `README.md`, `Makefile`, `src/`, and `docs/`.

> 💡 Run `make` with no target at any time to print the list of available commands.

> ⚙️ **Optional — persistent settings via `.env`.** Every knob has a sensible default, so
> you can skip this. To make a choice *stick* across commands — a different slot, or a shared
> PDK location — copy the template once:
> ```bash
> cp .env.example .env
> ```
> docker-compose auto-loads `.env`. For example, set `SLOT=1x0p5` there and every
> `make harden` targets the half slot without typing `SLOT=…`. A per-command override
> (`SLOT=1x0p5 make harden`) still works and takes precedence.

---

## Step 4 — Build the sim image

This builds the simulation container (Icarus Verilog + Python + cocotb). It is a one-time step; it takes a few minutes the first time and is instant after that.

```bash
make build-sim
```

> **You should see:** Docker pulling a base image (Ubuntu 22.04) and installing Icarus Verilog 11.0, Python, and cocotb 1.9.2, ending with the local image tagged `gf180-waferspace-sim`. Re-running is instant once cached. (You can confirm the image exists with `docker images`.)

---

## Step 5 — Run the example sim to green

This is the moment of truth. It runs the self-checking testbench against the example chip.

```bash
make sim
```

> **You should see:** the testbench run and print a pass banner, then exit with code 0. The last two lines are:
> ```
> ==== 256 samples checked, 0 mismatches ====
> OK: scaffold chip_core matched golden
> ```
> This is the green light. **If this passes, your environment is correct.** (`make test` is an alias for `make sim` and does exactly the same thing.)

> 💾 The run also drops a waveform at `chip_core.vcd` in the repo root. Because the repo is mounted into the container, that file is already on your real filesystem — open it directly in GTKWave. For why your outputs are never trapped in the container (and the one thing that *isn't* on your host), see [`07_HARDENING_GUIDE.md`](07_HARDENING_GUIDE.md#getting-your-files-out-of-the-container).

---

## Checkpoint — what success looks like

- `make build-sim` finished without errors and the image exists (`docker images` lists `gf180-waferspace-sim`).
- `make sim` printed the `OK: scaffold chip_core matched golden` banner and exited 0.
- You did **not** need to install Verilog, Python, or any EDA tool directly.

If `make sim` failed, jump to [`08_TROUBLESHOOTING.md`](08_TROUBLESHOOTING.md). The most common first-run issue on Windows is the path-mount one (the sim wrapper sets `MSYS_NO_PATHCONV=1` to fix Docker mangling mount paths under Git Bash).

---

## Step 6 — Fetch the PDK

Everything up to here needed **no PDK**. To make an actual layout you first download the GF180MCU PDK. This is a multi-GB, one-time download.

```bash
make pdk
```

> **You should see:** `make pdk` download the GF180MCU PDK (the `gf180mcuD` variant, pinned to commit `f6bfbd4`) via the `ciel` PDK manager into the `./pdk` folder in your repo (~4 GB — be patient). If it times out mid-download, just re-run it; it resumes.

---

## Step 7 — Harden the sample

Now turn the example RTL into a real layout for the default `1x1` slot. This produces the GDSII you'll submit in the next chapter — a clean, manufacturable layout of the sample chip.

```bash
make harden
```

> **You should see:** the full RTL→GDSII flow run (synthesis, place, route, signoff — this can take a while, and synthesis on a big design can take much longer than on this tiny example). On success a layout appears at `final/gds/chip_top.gds` and the manufacturability report reads `Antenna Passed`, `LVS Passed`, `DRC Passed`. The full walkthrough of this step — including the advanced Nix path (`make harden-nix`) and how to read every report — is [`07_HARDENING_GUIDE.md`](07_HARDENING_GUIDE.md).

<p align="center">
  <img src="../images/sample_chip_top.png" alt="Rendered chip_top GDS layout of the hardened sample for the 1x1 slot" width="600"><br>
  <sub><i>What you just made — the <code>chip_top</code> render of the hardened sample for the default <code>1x1</code> slot, also written to <code>final/render/chip_top.png</code>.</i></sub>
</p>

> ℹ️ **A note on patience:** big downloads and synthesis runs are normal and can look like a hang when they are not. The PDK is ~4 GB and a full Nix toolchain closure is ~7 GB; synthesis on large designs can take *hours* (the example takes only minutes). If a step seems stuck, give it time before assuming it failed.

---

## Where to go next

- **You now have a submittable chip.** Take the hardened sample to a wafer.space shuttle: [`02_WAFERSPACE_SUBMISSION.md`](02_WAFERSPACE_SUBMISSION.md).
- For the bigger picture — how this kit fits among the ways to get a die onto a wafer.space shuttle — see [`03_PATHS_TO_A_WAFERSPACE_DIE.md`](03_PATHS_TO_A_WAFERSPACE_DIE.md).
- To understand the pipeline you just ran, read [`04_THE_FLOW.md`](04_THE_FLOW.md); when you're ready to design your own, [`06_CONTINUE_THE_DESIGN.md`](06_CONTINUE_THE_DESIGN.md).

---

| ◀ Previous | Up | Next ▶ |
| :--- | :---: | ---: |
| [00 · ASIC for Beginners](00_ASIC_FOR_BEGINNERS.md) | [Documentation map](../README.md#documentation-map) | [02 · wafer.space Submission](02_WAFERSPACE_SUBMISSION.md) |
