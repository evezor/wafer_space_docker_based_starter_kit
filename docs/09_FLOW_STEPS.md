# 09 — The Flow, Step by Step

This is the complete, ordered list of the steps LibreLane runs when you `make harden` —
one entry for every numbered folder you see in a run directory (`librelane/runs/RUN_<timestamp>/<NN>-<step>/`),
in the order they execute. [`04_THE_FLOW.md`](04_THE_FLOW.md) groups the journey into six
big stages; this page is the fine-grained version: what each individual step actually does.

It is a **reference**, not a tutorial — skim it when you want to know what a particular
numbered folder is, or where in the pipeline a message came from.

---

## How many steps?

For the currently pinned LibreLane image — `ghcr.io/librelane/librelane:3.1.0.dev2`, set in
[`docker/Dockerfile.harden`](../docker/Dockerfile.harden) — with this repo's
[`librelane/config.yaml`](../librelane/config.yaml), the **`Chip`** flow resolves to **83
numbered steps**.

> **The exact count tracks the pinned container version.** An earlier image resolved to 84;
> a future bump may shift it again as steps are added, merged, or split upstream. Treat the
> number as version-dependent — the **phases** below are stable even when the exact count
> drifts by one or two. To print the authoritative list for whatever image is currently
> pinned, see [Regenerating this list](#regenerating-this-list) at the bottom.

---

## How to read this list

A few patterns repeat, and knowing them makes the list far shorter than 83 things to learn:

- **`Checker.*` steps don't change the layout.** Each one reads a single metric and then
  *passes*, *defers an error*, or *hard-errors*. They are the flow's guardrails — e.g.
  `Checker.LVS` simply turns the LVS result into a pass/fail. A "deferred" error lets the
  run finish so you can see *all* problems at once, then fails at the end.
- **`OpenROAD.STAMidPNR`, `…-1`, `…-2`, `…-3` are repeated timing snapshots.** STA = Static
  Timing Analysis. The same step runs several times between place-and-route stages; the
  numeric suffixes are added automatically because the step ID repeats.
- **`Odb.*` steps edit the design database** (OpenDB) directly — adding obstructions,
  setting power connections, inserting diodes — usually as setup or cleanup around a heavier
  OpenROAD step.
- **`KLayout.Render` sits *after* the seal ring (step 66), not earlier**, because this repo's
  `config.yaml` deliberately moves it there (`KLayout.Render: null` +
  `+KLayout.SealRing: KLayout.Render`) so the rendered `chip_top.png` includes the seal ring.

---

## Lint & synthesis (1–9)

Turn RTL into a verified gate-level netlist.

| # | Step | What it does |
|---|---|---|
| 1 | `Verilator.Lint` | Lint the RTL with Verilator before synthesis |
| 2 | `Checker.LintTimingConstructs` | Error if lint found illegal timing constructs (e.g. latches) |
| 3 | `Checker.LintErrors` | Error if Verilator reported lint errors |
| 4 | `Checker.LintWarnings` | Error/flag on Verilator lint warnings |
| 5 | `Yosys.JsonHeader` | Emit a JSON hierarchy/port view of the design |
| 6 | `Yosys.Synthesis` | Synthesize RTL → gate-level netlist mapped to standard cells |
| 7 | `Checker.YosysUnmappedCells` | Error if any cells couldn't be mapped to the library |
| 8 | `Checker.YosysSynthChecks` | Error on Yosys structural check failures |
| 9 | `Checker.NetlistAssignStatements` | Error if leftover `assign` aliases remain in the netlist |

## Floorplan & pre-placement (10–26)

Lay out the die, place the pad ring and macros, and build the power grid.

| # | Step | What it does |
|---|---|---|
| 10 | `OpenROAD.CheckSDCFiles` | Verify the SDC timing-constraint files are present/valid |
| 11 | `OpenROAD.CheckMacroInstances` | Confirm every configured macro exists in the netlist |
| 12 | `OpenROAD.STAPrePNR` | Pre-layout static timing analysis on the netlist |
| 13 | `OpenROAD.Floorplan` | Create the initial floorplan (die/core area, rows) |
| 14 | `OpenROAD.DumpRCValues` | Dump per-layer R/C values used for estimation |
| 15 | `Odb.CheckMacroAntennaProperties` | Warn if macro LEFs lack antenna data |
| 16 | `Odb.SetPowerConnections` | Add global power/ground connections in the database |
| 17 | `OpenROAD.PadRing` | Assemble the I/O pad ring around the core |
| 18 | `Odb.ManualMacroPlacement` | Place macros at fixed coords (QR/ID/marker/logo IP) |
| 19 | `OpenROAD.CutRows` | Cut placement rows around placed macros |
| 20 | `OpenROAD.TapEndcapInsertion` | Insert well-tap and end-cap cells |
| 21 | `Odb.AddPDNObstructions` | Add temporary obstructions to steer the power grid |
| 22 | `OpenROAD.GeneratePDN` | Build the power distribution network (straps/rings) |
| 23 | `Odb.RemovePDNObstructions` | Remove the temporary PDN obstructions |
| 24 | `Odb.AddRoutingObstructions` | Add temporary obstructions to steer routing |
| 25 | `OpenROAD.GlobalPlacementSkipIO` | Rough global placement (IO ignored) to seed pin placement |
| 26 | `Odb.ApplyDEFTemplate` | Apply a template DEF (fixed pin/floorplan layout) |

## Placement (27–33)

Place standard cells and legalize them onto rows.

| # | Step | What it does |
|---|---|---|
| 27 | `OpenROAD.GlobalPlacement` | Global placement of all standard cells |
| 28 | `Odb.WriteVerilogHeader` | Write a power-aware Verilog header of the module |
| 29 | `Checker.PowerGridViolations` | Flag power-grid violations (ignorable if LVS passes) |
| 30 | `OpenROAD.STAMidPNR` | Mid-PnR STA snapshot (post global placement) |
| 31 | `OpenROAD.RepairDesignPostGPL` | Buffer/resize repairs after global placement |
| 32 | `Odb.ManualGlobalPlacement` | Optional manual override of specific instance placements |
| 33 | `OpenROAD.DetailedPlacement` | Legalize cells onto rows/sites |

## Clock tree & post-CTS timing (34–37)

Build the clock distribution network and fix the timing it disturbs.

| # | Step | What it does |
|---|---|---|
| 34 | `OpenROAD.CTS` | Clock tree synthesis — build a balanced clock network |
| 35 | `OpenROAD.STAMidPNR-1` | STA snapshot after CTS |
| 36 | `OpenROAD.ResizerTimingPostCTS` | Timing-driven resize/buffer after CTS |
| 37 | `OpenROAD.STAMidPNR-2` | STA snapshot after post-CTS repair |

## Routing & antenna repair (38–49)

Route the wires, then fix antenna and timing issues routing introduces.

| # | Step | What it does |
|---|---|---|
| 38 | `OpenROAD.GlobalRouting` | Coarse (global) routing of all nets |
| 39 | `OpenROAD.CheckAntennas` | Antenna-rule check after global routing |
| 40 | `OpenROAD.RepairDesignPostGRT` | Design repair after global routing |
| 41 | `Odb.DiodesOnPorts` | Insert antenna diodes on design ports |
| 42 | `Odb.HeuristicDiodeInsertion` | Heuristic diode insertion to mitigate antenna effect |
| 43 | `OpenROAD.RepairAntennas` | Repair antenna violations (diodes/rerouting) |
| 44 | `OpenROAD.ResizerTimingPostGRT` | Second timing-driven resize pass after global routing |
| 45 | `OpenROAD.STAMidPNR-3` | STA snapshot after post-GRT repair |
| 46 | `OpenROAD.DetailedRouting` | Detailed routing — real wires/vias on metal (TritonRoute) |
| 47 | `Odb.RemoveRoutingObstructions` | Remove the temporary routing obstructions |
| 48 | `OpenROAD.CheckAntennas-1` | Re-check antennas after detailed routing |
| 49 | `Checker.TrDRC` | Check detailed-routing DRC violations |

## Post-route checks & extraction (50–58)

Sanity-check the routed design, fill gaps, and extract parasitics for final timing.

| # | Step | What it does |
|---|---|---|
| 50 | `Odb.ReportDisconnectedPins` | Report disconnected pins |
| 51 | `Checker.DisconnectedPins` | Error on critical disconnected pins |
| 52 | `Odb.ReportWireLength` | Report long wires by length |
| 53 | `Checker.WireLength` | Error if any wire exceeds the length threshold |
| 54 | `OpenROAD.FillInsertion` | Fill gaps with filler/decap cells |
| 55 | `Odb.CellFrequencyTables` | Generate cell-usage frequency tables |
| 56 | `OpenROAD.RCX` | Extract parasitic RC (SPEF) from the routed layout |
| 57 | `OpenROAD.STAPostPNR` | Final multi-corner post-layout STA with parasitics |
| 58 | `OpenROAD.IRDropReport` | Static IR-drop analysis on the power grid |

## Signoff — streamout, DRC, LVS (59–83)

Stream the GDSII and run every manufacturability check a fab requires.

| # | Step | What it does |
|---|---|---|
| 59 | `Magic.StreamOut` | Stream the layout to GDSII via Magic |
| 60 | `KLayout.StreamOut` | Stream the layout to GDSII via KLayout (the primary GDS here) |
| 61 | `KLayout.XOR` | XOR the Magic vs KLayout GDS to find geometry mismatches |
| 62 | `Checker.XOR` | Error on XOR differences between the two streamouts |
| 63 | `KLayout.Antenna` | KLayout antenna check on the GDS |
| 64 | `Checker.KLayoutAntenna` | Error on KLayout antenna violations |
| 65 | `KLayout.SealRing` | Add the seal ring around the die in the GDS |
| 66 | `KLayout.Render` | Render the layout PNG (relocated here by config, after the seal ring) |
| 67 | `KLayout.Filler` | Add filler cells per design rules to the GDS |
| 68 | `KLayout.Density` | Metal-density check on the GDS |
| 69 | `Checker.KLayoutDensity` | Error on density violations |
| 70 | `Magic.DRC` | Design-rule check with Magic |
| 71 | `KLayout.DRC` | Design-rule check with KLayout |
| 72 | `Checker.MagicDRC` | Evaluate Magic DRC results (non-fatal here per config) |
| 73 | `Checker.KLayoutDRC` | Error on KLayout DRC violations |
| 74 | `Magic.SpiceExtraction` | Extract a SPICE netlist from the GDS for LVS |
| 75 | `Checker.IllegalOverlap` | Error on illegal device overlaps from extraction |
| 76 | `Netgen.LVS` | Layout-vs-schematic comparison with Netgen |
| 77 | `Checker.LVS` | Error on LVS mismatches |
| 78 | `Yosys.EQY` | (Experimental) formal RTL-vs-netlist equivalence check |
| 79 | `Checker.SetupViolations` | Flag setup-timing violations |
| 80 | `Checker.HoldViolations` | Flag hold-timing violations |
| 81 | `Checker.MaxSlewViolations` | Flag max-transition (slew) violations |
| 82 | `Checker.MaxCapViolations` | Flag max-capacitance violations |
| 83 | `Misc.ReportManufacturability` | Write the final manufacturability report (DRC/LVS/antenna) |

> The headline signoff results — `Antenna / LVS / DRC Passed` — come out of this last phase.
> See [`07_HARDENING_GUIDE.md`](07_HARDENING_GUIDE.md#what-a-clean-signoff-looks-like) for
> what a clean `manufacturability.rpt` and `metrics.json` should read.

---

## Regenerating this list

The list above is for the pinned image. If you bump LibreLane in
[`docker/Dockerfile.harden`](../docker/Dockerfile.harden), print the new authoritative,
ordered step list for the `Chip` flow (with this repo's `substituting_steps` from
`config.yaml` applied) like this:

```bash
docker compose run --rm --no-deps harden python3 -c \
  "from librelane.flows import Flow; \
   F = Flow.factory.get('Chip').Substitute({'KLayout.Render': None, '+KLayout.SealRing': 'KLayout.Render'}); \
   print('COUNT', len(F.Steps)); \
   [print(i+1, s.id) for i, s in enumerate(F.Steps)]"
```

> The `Substitute({...})` dict mirrors `meta.substituting_steps` in
> [`librelane/config.yaml`](../librelane/config.yaml) — if you change those substitutions,
> update the dict to match. No PDK is required just to list the steps.

---

## Where to go next

- The six big stages this list expands on → [`04_THE_FLOW.md`](04_THE_FLOW.md).
- How to actually run the flow and read its output → [`07_HARDENING_GUIDE.md`](07_HARDENING_GUIDE.md).
- When a step fails → [`08_TROUBLESHOOTING.md`](08_TROUBLESHOOTING.md).

---

| ◀ Previous | Up | Next ▶ |
| :--- | :---: | ---: |
| [08 · Troubleshooting](08_TROUBLESHOOTING.md) | [Documentation map](../README.md#documentation-map) | [Back to the README](../README.md) |
