#!/usr/bin/env bash
# scripts/sim.sh — run any command inside the simulation container with this repo
# mounted at /work. This is the ONE place the Docker invocation lives, so nobody
# has to remember the Windows<->Linux path-mount incantation.
#
# Examples:
#   bash scripts/sim.sh iverilog -V
#   bash scripts/sim.sh bash -lc 'iverilog -g2012 -o /tmp/a.vvp src/*.sv tb/*.sv && vvp /tmp/a.vvp'
#   bash scripts/sim.sh make sim
set -euo pipefail

# git prints the repo root as a Windows path (C:/Users/...) which Docker Desktop
# mounts directly. MSYS_NO_PATHCONV stops Git Bash from rewriting the :/work part.
REPO_WIN="$(git rev-parse --show-toplevel)"
export MSYS_NO_PATHCONV=1

exec docker run --rm -i \
    -v "${REPO_WIN}:/work" \
    -w /work \
    gf180-waferspace-sim "$@"
