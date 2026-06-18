# Tapeout IP cells (wafer.space)

This directory holds the five **wafer.space tapeout IP cells** that every chip on a
wafer.space shuttle must embed in its die corners. They are NOT your design logic —
they are the shuttle's identification and alignment cells, and a tapeout will not be
accepted without them.

| Cell | Purpose | Placed at (µm) |
|---|---|---|
| `gf180mcu_ws_ip__shuttle_id`  | Which shuttle run this die is on | `[26, 175.6]`, orient E |
| `gf180mcu_ws_ip__project_id`  | Which project (yours) on the shuttle | `[175.6, 26]`, orient N |
| `gf180mcu_ws_ip__qrcode_id`   | Machine-readable QR for die ID | `[26, 26]`, orient N |
| `gf180mcu_ws_ip__marker`      | Top-right alignment marker | `[$DIE_AREA[2]-281, $DIE_AREA[3]-281]` |
| `gf180mcu_ws_ip__logo`        | wafer.space logo | `[26, $DIE_AREA[3]-169.25]` |

#### Directory layout (per cell)

Each cell provides four LibreLane views:

    ip/<cell_name>/
      gds/<cell_name>.gds   # the physical layout (placed into your GDSII)
      lef/<cell_name>.lef   # abstract for placement/routing
      lib/<cell_name>.lib   # timing/black-box view
      vh/<cell_name>.v      # black-box Verilog stub: (* blackbox *) module <name>; endmodule

#### IMPORTANT: these are PLACEHOLDERS

The QR code and the shuttle/project IDs encode identifiers that **wafer.space
assigns to your project for a specific shuttle**. The views shipped here are
generic placeholders so the LibreLane flow runs end-to-end out of the box and you
can see a complete, signed-off GDSII.

**Before a real tapeout you MUST replace these with the official cells issued by
wafer.space for your registered project/shuttle.** Drop the wafer.space-provided
`gds/`, `lef/`, `lib/`, and `vh/` files into the matching `ip/<cell_name>/`
directory, keeping the file names. Do not hand-edit the GDS.

#### How they are wired into the flow

These cells are declared to LibreLane as macros with fixed corner placements and
are listed in `IGNORE_DISCONNECTED_MODULES` in `librelane/config.yaml` (the black-
box stubs have no signal ports, so the checkers must not flag them as
disconnected). The seal ring (auto-inserted by LibreLane's KLayout.SealRing step)
surrounds everything; the 26 µm corner offsets above are exactly the seal-ring
width.

Source of the official cells:
https://github.com/wafer-space/gf180mcu-project-template
