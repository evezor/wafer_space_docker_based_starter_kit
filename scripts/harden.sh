#!/usr/bin/env bash
# scripts/harden.sh — Path A hardening. Runs the SAME librelane invocation the
# Nix flow (Path B) uses, but inside the prebuilt LibreLane Docker image (which
# already contains librelane — so NO `nix develop`).
#
# Usage:  bash scripts/harden.sh             # uses defaults (SLOT=1x1)
#         SLOT=1x0p5 bash scripts/harden.sh  # override the slot
set -euo pipefail

# Design knobs (defaults match a gf180mcuD / slot 1x1 wafer.space shuttle).
PDK=${PDK:-gf180mcuD}
SCL=${SCL:-gf180mcu_fd_sc_mcu7t5v0}
PAD=${PAD:-gf180mcu_fd_io}
SRAM=${SRAM:-gf180mcu_fd_ip_sram}
SLOT=${SLOT:-1x1}

# macros_5v.yaml goes with the 5V SRAM; otherwise macros_3v3.yaml.
if [ "${SRAM}" = "gf180mcu_fd_ip_sram" ]; then MACROS=5v; else MACROS=3v3; fi

# Generate the per-slot RTL defines first (same content as `make defines`).
bash scripts/gen_defines.sh

export MSYS_NO_PATHCONV=1   # Windows/Git-Bash mount-path fix (see sim.sh)

# The librelane command line — identical to the Makefile's LIBRELANE_CMD.
LIBRELANE_CMD="SRAM_DEFINE=SRAM_${SRAM} librelane \
    librelane/slots/slot_${SLOT}.yaml \
    librelane/macros/macros_${MACROS}.yaml \
    librelane/config.yaml \
    --pdk ${PDK} --pdk-root /pdk --manual-pdk \
    --scl ${SCL} --pad ${PAD} \
    --save-views-to /work/final"

exec docker compose run --rm \
    -e SLOT="${SLOT}" -e PDK="${PDK}" -e SCL="${SCL}" -e PAD="${PAD}" -e SRAM="${SRAM}" \
    harden bash -lc "${LIBRELANE_CMD}"
