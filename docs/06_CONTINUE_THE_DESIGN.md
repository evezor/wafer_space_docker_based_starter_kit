# 06 — Continue the Design

You have a green simulation and (maybe) a clean GDSII from the scaffold. Now you make
the chip *yours*. This page is the "where do I look / how do I keep going" guide: exactly
which file to edit, the rules that file must obey, how to build a trustworthy test, and
how to grow from the trivial scaffold into a real design.

The single biggest thing to understand before you touch a pad is that **three different
files do three different jobs**, and people get stuck because they blur them together. So
we start there.

If a term is new, it is defined the first time it appears.

---

## This is your design now

The `wafer_space_docker_based_starter_kit` ships a deliberately trivial **core** — a
*heartbeat* toggle (a slow blink that proves the chip is clocking) plus a free-running
counter — so the whole pipeline is proven green *before* you change anything.

**Everything you design goes inside one file: `src/chip_core.sv`.**

You will rarely, if ever, touch `src/chip_top.sv`. That file is the wafer.space **pad
ring** (the band of input/output cells around the edge of the die) plus the
tapeout-required identity cells, and it instantiates *your* core through a fixed
contract. The rule is simple:

> **Change your core. Leave the top alone.**

> 🔎 Want to see exactly how the shipped example is wired — what each line does and where
> its golden-model check lives — before you start changing it? Read
> [`05_ANATOMY_OF_THE_SAMPLE.md`](05_ANATOMY_OF_THE_SAMPLE.md) first.

---

## The mental model: two layers, and the YAML is neither

Almost every "wait, how do pads work?" question dissolves once you see that a pad's
behavior is decided in **two separate places**, and that the slot YAML is *not* one of
them:

| | Where it's set | When it's fixed | What it decides |
|---|---|---|---|
| **Layer A — the physical cell** | `src/chip_top.sv` | **At tapeout. Permanent.** | The *hardware* in that pin: whether a driver/receiver/analog structure even exists. |
| **Layer B — runtime config** | `src/chip_core.sv` | **Every clock. Changeable.** | For a bidir cell only: direction, pulls, drive strength, slew. |
| The **slot YAML** (`librelane/slots/slot_*.yaml`) | — | — | **Neither.** Just *where* each pad sits on the ring (placement). |

Hold onto this: **the cell type is the hardware; `oe/ie/pu/pd/cs/sl` is the
configuration; the YAML is the seating chart.** The rest of this section unpacks each.

### Layer A — the physical cell (the real silicon)

Each pin on the die is **one** foundry I/O cell, instantiated in `chip_top.sv`. The cell
type is what physically exists and sets the *envelope* of what that pin can ever do. The
kit uses these signal cells:

| In `chip_top.sv` | Foundry cell (gf180mcu I/O) | What it physically is |
|---|---|---|
| `clk_pad` | `…io__in_s` | **Input only**, Schmitt-trigger (clean edges on a noisy clock). No output driver. |
| `rst_n_pad`, `inputs[i].pad` | `…io__in_c` | **Input only.** No `A`/`OE` pins exist — it *cannot* drive out. |
| `bidir[i].pad` | `…io__bi_24t` | **Universal digital.** Driver + receiver + enables: input, output, *or* true bidirectional. |
| `analog[i].pad` | `…io__asig_5p0` | **Analog passthrough only.** No digital buffer at all (5 V analog). |
| `dvdd/dvss/vdd/vss pads` | `…io__dvdd/dvss/vdd/vss` | Supply + ESD ring (not signals). |

The crucial consequences:

- An **input cell (`in_c`) has no output driver** — the transistors to drive the pin
  simply are not in the cell. No amount of software makes it an output.
- An **analog cell (`asig_5p0`) has no digital buffer** — it can't be used as logic I/O.
- A **bidir cell (`bi_24t`) is a superset.** It contains everything an input cell has
  *plus* a driver and enables, so it can *impersonate* an input (disable the driver) or
  act as a dedicated output, or switch direction at runtime.

> **The takeaway that fixes most confusion:** the only thing that permanently decides a
> pin's capability is **which cell `chip_top` instantiates** — not the YAML, and not the
> signals your core drives.

### Layer B — runtime configuration (changes nothing physical)

For each **bidir** pad your core drives a handful of control nets — `oe`, `ie`, `pu`,
`pd`, `cs`, `sl`. These are *inputs to a fixed cell*. Setting `bidir_oe[i]=0` does **not**
remove the driver from the silicon; it just turns it off this cycle. This layer is pure
configuration — it's "software" that happens to run on a wire.

### The slot YAML — placement only

`librelane/slots/slot_1x1.yaml` is **floorplan + ring placement**, and that's *all*:

- `DIE_AREA` / `CORE_AREA` — die and seal-ring geometry for the slot.
- `PAD_SOUTH / EAST / NORTH / WEST` — the **side and order** each pad instance sits on the
  ring. The strings like `"bidir\[0\].pad"`, `"inputs\[3\].pad"`, `"dvdd_pads\[0\].pad"`
  are **instance paths that must match the generate blocks in `chip_top.sv`** — that
  matching is the *only* thing tying the YAML to the design.

So when you see `"bidir\[0\].pad"` in the YAML, it is **not** assigning a role. It's a
pointer that says "the cell `chip_top` already built at instance `bidir[0]` goes *here* on
the edge." The label looks like a job title; it's really a seat number.

What the slot standard genuinely *fixes* (the **hard** constraints) is only: the die/seal
geometry, the ring positions, and **where the power/ground pads must sit** (the
dvdd/dvss/vdd/vss pads are interleaved deliberately for power delivery and ESD — see the
comments in the YAML). Everything about *signal* pads is yours to allocate (see
[Allocation is yours](#allocation-is-yours-bidir-is-the-universal-pad) below).

---

## The core contract (copy verbatim — do not rename)

`src/chip_top.sv` instantiates your core as `i_chip_core` with these **exact** parameter
and port names. Keep them identical or the design will not elaborate (i.e. the tools will
fail to assemble your RTL into a module hierarchy):

```systemverilog
chip_core #(
    .NUM_INPUT_PADS (NUM_INPUT_PADS),
    .NUM_BIDIR_PADS (NUM_BIDIR_PADS),
    .NUM_ANALOG_PADS(NUM_ANALOG_PADS)
) i_chip_core (
    `ifdef USE_POWER_PINS .VDD(VDD), .VSS(VSS), `endif
    .clk(clk_PAD2CORE), .rst_n(rst_n_PAD2CORE),
    .input_in(input_PAD2CORE), .input_pu(input_CORE2PAD_PU), .input_pd(input_CORE2PAD_PD),
    .bidir_in(bidir_PAD2CORE), .bidir_out(bidir_CORE2PAD), .bidir_oe(bidir_CORE2PAD_OE),
    .bidir_cs(bidir_CORE2PAD_CS), .bidir_sl(bidir_CORE2PAD_SL), .bidir_ie(bidir_CORE2PAD_IE),
    .bidir_pu(bidir_CORE2PAD_PU), .bidir_pd(bidir_CORE2PAD_PD),
    .analog(analog_PAD)
);
```

The naming convention is self-documenting: `*_PAD2CORE` is data flowing *in* from a pad,
`*_CORE2PAD*` is control or data the core drives *out* to a pad.

Your `chip_core` must therefore declare exactly this port list (this is what the scaffold
ships, so just keep it):

```systemverilog
`default_nettype none

// "module chip_core ( ... )" — everything inside the parentheses is the PORT LIST:
// the list of wires that cross the edge of your design. It only NAMES the wires and
// says which way each flows. It does NOT define any pad's behavior — that happens in
// the module body further down (the assign/always lines). The physical pads live in
// chip_top.sv; these are just the wires that connect to them.
module chip_core #(
    // ---- parameters: compile-time numbers chip_top fills in for your slot ----
    parameter NUM_INPUT_PADS  = 12,   // how many input pads this slot has (1x1 = 12)
    parameter NUM_BIDIR_PADS  = 40,   // how many bidir pads this slot has (1x1 = 40)
    parameter NUM_ANALOG_PADS = 2     // how many analog pads this slot has (1x1 = 2)
)(
    // How to read every line below:
    //   input  = the wire comes FROM the pad ring INTO your core (you READ it)
    //   output = your core DRIVES the wire OUT to the pad ring   (you SET it)
    //   inout  = bidirectional electrical net (only power & analog use this)
    //   [N-1:0] = a BUNDLE of N wires ("a bus"), one wire per pad, indexed 0..N-1
    //   The ORDER of these lines is just readability — it has no electrical meaning.

    `ifdef USE_POWER_PINS
    inout  wire VDD,    // power net  (bidirectional; only present in the layout build)
    inout  wire VSS,    // ground net
    `endif

    input  wire clk,    // 1 wire IN: the clock, from the clock pad over in chip_top
    input  wire rst_n,  // 1 wire IN: reset, active LOW (0 = reset, 1 = run)

    // ---- INPUT pads: data only ever flows IN (these pads can't drive out) ----
    input  wire [NUM_INPUT_PADS-1:0] input_in,  // 12 wires IN:  value sensed at each input pad. input_in[3] == input pad 3.
    output wire [NUM_INPUT_PADS-1:0] input_pu,  // 12 wires OUT: your pull-up   on/off for each input pad
    output wire [NUM_INPUT_PADS-1:0] input_pd,  // 12 wires OUT: your pull-down on/off for each input pad

    // ---- BIDIR pads: each wire's pad can be an input OR an output; you choose ----
    input  wire [NUM_BIDIR_PADS-1:0] bidir_in,  // 40 wires IN:  value sensed at each bidir pad. bidir_in[5] == bidir pad 5.
    output wire [NUM_BIDIR_PADS-1:0] bidir_out, // 40 wires OUT: the value to drive WHEN that pad is set to output
    output wire [NUM_BIDIR_PADS-1:0] bidir_oe,  // 40 wires OUT: direction switch. 1 = pad outputs, 0 = pad inputs.
    output wire [NUM_BIDIR_PADS-1:0] bidir_cs,  // 40 wires OUT: drive-strength setting, per pad
    output wire [NUM_BIDIR_PADS-1:0] bidir_sl,  // 40 wires OUT: slew-rate (edge speed) setting, per pad
    output wire [NUM_BIDIR_PADS-1:0] bidir_ie,  // 40 wires OUT: input-enable, per pad (you must drive it = ~bidir_oe)
    output wire [NUM_BIDIR_PADS-1:0] bidir_pu,  // 40 wires OUT: pull-up   setting, per pad
    output wire [NUM_BIDIR_PADS-1:0] bidir_pd,  // 40 wires OUT: pull-down setting, per pad

    // ---- ANALOG pads: straight-through analog, no logic, no direction ----
    inout  wire [NUM_ANALOG_PADS-1:0] analog    // 2 wires: analog passthrough, one per analog pad
);
```

> 🧭 **How to read this block (the part that trips everyone up).**
>
> - **Is this where I define a pad's function?** **No.** This is a *declaration* — it
>   just lists the wires and their direction. You assign a pad's function later, in the
>   body, by *driving* these wires (e.g. `assign bidir_oe = ...;` decides direction;
>   `assign bidir_out = ...;` decides what an output pad shows).
> - **What does `bidir_in` mean?** "The values currently sensed at the bidir pads,
>   flowing into the core." It's an `input` (into your core) and it's a bus of 40 wires.
> - **What pad does a wire map to?** **By bit index.** `bidir_out[5]` is bidir pad 5,
>   `input_in[3]` is input pad 3, and so on. *Which physical edge of the die* pad 5 sits
>   on is set by the slot YAML — but the wire-to-pad number is always just the index.

> ℹ️ **Note:** the parameter defaults (`12 / 40 / 2`) are *inert placeholders*. The
> `iverilog -g2012` SystemVerilog mode rejects an ANSI parameter that has no default, so
> you must give each one a value — but `chip_top` always overrides all three explicitly
> with the values for your chosen slot. Do not delete the defaults.

The scaffold's `chip_core.sv` already matches this and is **SRAM-free** (it contains no
on-chip RAM macros). Do not add SRAM macros unless you also wire them into
`librelane/macros/*.yaml` and the power-delivery network; see `08_TROUBLESHOOTING.md`
(symptom #4) for why a stray SRAM reference breaks the harden.

---

## Driving each pad type from your core

Now the practical part: given the cell at each pin (Layer A), what must your core drive
(Layer B)? Each pad category maps to one cell from the table above.

### Input pads (`input_in[]`) — the `in_c` cell

These are **always inputs** — and now you know *why*: the `in_c` cell has no output
driver. Data only ever flows into the core.

- The core reads data on `input_in[i]`.
- The core drives each pad's pull configuration via `input_pu[i]` / `input_pd[i]` (a
  *pull-up* gently holds the pin high, a *pull-down* holds it low). The scaffold sets both
  to `0` — **no internal pull resistors**.
- Because there are no pulls, **any input you do not drive must be tied off inside your
  core**. On the finished chip an undriven, unpulled input pin would otherwise *float*
  (sit at an undefined voltage). Adding board-level pulls is part of bring-up, which is
  beyond this kit's scope.

### Bidir pads (`bidir_*`) — the `bi_24t` cell and the `oe` mask

A **bidir** pad can act as an output *or* an input — you choose, **per bit**, with the
**output-enable** signal `bidir_oe`:

- `bidir_oe[i] = 1` makes bit *i* an **output**. The core drives the data on
  `bidir_out[i]`.
- `bidir_oe[i] = 0` makes bit *i* an **input**. The core reads data from `bidir_in[i]`.

There is one rule the pad cell does **not** enforce for you, so you must:

> **Always drive `bidir_ie = ~bidir_oe`.** The *input-enable* (`ie`) must be the exact
> complement of the output-enable. For each bit: an OUTPUT is `oe=1, ie=0`; an INPUT is
> `oe=0, ie=1`.

The scaffold builds this mask with a `for`-generate loop. Copy that pattern — a
generate-driven continuous `assign` keeps the mask *static* (a fixed direction set at
elaboration), which avoids accidentally inferring a latch:

```systemverilog
wire [NUM_BIDIR_PADS-1:0] oe_mask;
genvar bi;
generate
    for (bi = 0; bi < NUM_BIDIR_PADS; bi = bi + 1) begin : g_oe
        assign oe_mask[bi] = ((bi >= 8) && (bi <= 11)) ? 1'b0 : 1'b1;
    end
endgenerate
assign bidir_oe = oe_mask;
assign bidir_ie = ~bidir_oe;     // input-enable is the complement of oe
assign bidir_cs = '0;            // drive-strength config
assign bidir_sl = '0;            // slew-rate config
assign bidir_pu = '0;            // pull-up config (off)
assign bidir_pd = '0;            // pull-down config (off)
```

The extra control buses `bidir_cs` (drive strength), `bidir_sl` (slew rate), `bidir_pu`,
and `bidir_pd` (pulls) all stay at `'0` for the scaffold. Drive them unconditionally too.

(The `oe` does not have to be *static*. A true bidirectional bus — e.g. an SRAM-style data
port — flips `bidir_oe[i]` at runtime. Keep the generate pattern for direction bits that
never change; drive `oe`/`ie` from your logic for bits that do.)

### Analog pads (`analog[]`) — the `asig_5p0` cell

These are reserved **5 V analog** pads — a straight passthrough with no digital buffer and
no `oe`. They are not wired to logic by default. Leave them alone unless you have a
specific analog plan.

---

## Allocation is yours: bidir is the universal pad

The default slot for this kit is `1x1`, whose template ships **12 input + 40 bidir + 2
analog** pads. It is tempting to read those category counts as a hard, handed-down budget.
They are not.

> **The slot standard fixes only the die geometry and the power-pad positions. The split
> of the *signal* pads into input / bidir / analog is the template's default *allocation*,
> not a rule.** Because the `bi_24t` cell is a superset, a bidir pad set to `oe=0` is every
> bit as good as a dedicated input pad.

Two levels of freedom follow from this:

1. **Within the shipped allocation (no `chip_top` edit, the common case).** The `1x1`
   template already gives you ~**52 assignable signal pads** (12 input + 40 bidir; analog
   separate). Need ten control inputs? Put a few on the input pads and configure the rest
   of your bidir pads as inputs (`oe=0`). Assign functions to whatever pads are convenient
   — just stay within the total.

2. **Changing the allocation itself (a `chip_top` edit, advanced).** Because no rule binds
   a ring position to a cell type, you *can* re-mix the cells — e.g. make a position the
   YAML calls "bidir" hold an `in_c` cell, or instantiate `bi_24t` at every signal
   position for maximum flexibility. That means editing the generate blocks in
   `chip_top.sv` **and** the matching instance names in the slot YAML — a step-by-step
   procedure in [`06b — Changing the Pad Ring`](06b_CHANGING_THE_PAD_RING.md).

For most designs you never need level 2 — level 1 (drive bidir pads as inputs) covers it.

(For the full per-slot pad numbers, see `02_WAFERSPACE_SUBMISSION.md`.)

---

## What *not* to touch in `chip_top.sv`

`src/chip_top.sv` is a **do-not-edit boundary** for everyday work. It is copied verbatim
from the wafer.space project template and contains no design logic of its own — it is pure
plumbing between the silicon pads and your core. Specifically, do not:

- Rename the pad-ring **generate blocks** (`bidir`, `inputs`, `analog`, `*_pads`). The
  slot YAML files reference these blocks by instance path to place pads (Layer A ↔ YAML
  coupling). Rename one and the harden breaks.
- Remove the required **tapeout IP cells** (more on these in
  `02_WAFERSPACE_SUBMISSION.md`): `qrcode_id`, `shuttle_id`, `project_id`, and `marker`.
  The `logo` cell is decorative and may be removed.

The only legitimate reasons to edit `chip_top.sv` are (a) you change which slot you
target, or (b) you genuinely need a different pad *cell* on some position. Both are covered
next.

---

## Advanced: changing the pad ring itself

Everything above keeps `chip_top.sv` untouched. The two moves that *do* edit it — giving a
pad a physically different **cell** (a real type change), or targeting a different
**slot** — are a separate, step-by-step procedure, because they ripple across
`chip_top.sv`, the slot YAML, `slot_defines.svh`, and your core's contract in lockstep.

> 📄 See **[`06b — Changing the Pad Ring`](06b_CHANGING_THE_PAD_RING.md)** for the full
> walkthrough. Neither move is needed for a first design — and remember a bidir pad can
> already act as an input or output by configuration (see
> [Allocation is yours](#allocation-is-yours-bidir-is-the-universal-pad)), so most needs
> never require a ring change at all.

---

## The inner loop: edit → sim → fix → repeat

This is where you live day to day. It is seconds per cycle, no PDK required.

```bash
# 1. Edit your design.
$EDITOR src/chip_core.sv

# 2. Simulate. Repeat until green.
make sim
```

> **You should see:** your testbench pass. For the shipped scaffold the run ends with:
>
> ```
> ==== 256 samples checked, 0 mismatches ====
> OK: scaffold chip_core matched golden
> ```
>
> If it fails, the simulator prints the offending sample and signal. Fix `chip_core.sv`
> and re-run. Stay in this loop — it is fast.

---

## Adding a self-checking test (with a golden model)

The most important habit in this whole kit: **prove it in simulation against a golden
reference before you ever spend hours hardening.** A "self-checking" testbench compares
your RTL's output, bit for bit, against a known-correct answer and fails loudly on any
mismatch — so a passing run actually *means something*.

The gold standard (literally) is a **golden vector** test, exactly like the scaffold's own
`chip_core` test. A *golden vector* is a file of expected outputs produced by an
independent reference model.

1. Write a tiny reference model of the expected behavior in `models/` (Python is easy; see
   `models/ref_model.py`). Have it emit expected outputs to a hex file, e.g.
   `models/my_golden.hex`.
2. Write a self-checking testbench in `tb/` that loads that file with `$readmemh`, runs
   your RTL, and compares **every** sample, printing a running mismatch count.
3. Make the pass condition **strict**: 0 mismatches over `N > 0` samples. Never loosen a
   self-checking test just to make it pass — a test you can cheat is worse than no test.

You can run any specific testbench directly through the Docker wrapper (the wrapper builds
your RTL with Icarus Verilog and runs it):

```bash
bash scripts/sim.sh bash -lc \
  'iverilog -g2012 -o /tmp/t.vvp src/chip_core.sv tb/tb_chip_core.sv && vvp /tmp/t.vvp'
```

> **You should see:** an `... OK` line reporting `0 mismatches`. If you see any mismatch
> count above zero, your RTL and your reference model disagree — investigate before you
> trust the design.

---

## A second, optional layer: the pad-level cocotb sim

The fast Icarus loop above tests `chip_core` in isolation. There is a second, **optional**
harness — `make sim-cocotb` — that elaborates the *whole* `chip_top`: your core **plus** the
padring and the tapeout IP, driven through the real pad signals from Python (cocotb is a
Python test framework).

- **What it proves:** that your core is wired correctly *through the pads* — useful after you
  touch the pad contract or add pins. It is a pad-level **smoke test**; the bit-exact
  correctness check still lives in the Icarus golden test above.
- **Cost:** it needs the **PDK** (it pulls in the pad-cell models), so it is slower and is
  **not** part of the fast inner loop. Run it occasionally, not on every edit.

```bash
make sim-cocotb     # needs the PDK; elaborates the full chip_top via cocotb
```

The harness is `cocotb/chip_top_tb.py`; when you add RTL files, register them there too (see
the outer loop below).

---

## The outer loop: register new RTL, then harden

As your design grows you will split it across more `.sv` files. When you add a new file,
register it in **two** places:

1. `librelane/config.yaml` → the `VERILOG_FILES:` list. This is the list the hardening
   flow reads to turn RTL into a layout.
2. The cocotb sources list in `cocotb/chip_top_tb.py`. This is the pad-level simulation
   (cocotb is a Python-based test framework that drives the *whole* `chip_top`, pads and
   all).

Then re-run `make sim`, and **only once it is green**, run `make harden`. The full
hardening walkthrough is in `07_HARDENING_GUIDE.md`.

---

## Growing from the scaffold — add your first engine

Here is a concrete recipe for replacing the heartbeat counter with your own logic, the
first time. Say you want an 8-bit counter you can preload from input pads.

1. **Keep the module header and all the pad-config assigns** (`input_pu/pd`,
   `bidir_oe/ie/cs/sl/pu/pd`). Only the *behavioral* part below them changes.

2. **Write your logic in a clear-then-set output block.** Always clear the whole output
   vector to `'0` first, then set the bits you use. This guarantees no latch and a defined
   value on every bit:

   ```systemverilog
   reg [7:0] my_count;
   always @(posedge clk) begin
       if (!rst_n)        my_count <= 8'd0;
       else if (input_in[0]) my_count <= my_count + 8'd1;  // count while input pad 0 is high
   end

   logic [NUM_BIDIR_PADS-1:0] bout;
   always @(*) begin
       bout            = '0;              // clear everything first (no latch)
       bout[7:0]       = my_count;        // then drive the bits you use
   end
   assign bidir_out = bout;
   ```

3. **Fold every genuinely-unused input into the `_unused` net** so the `-Wall` warning
   flag stays quiet without you having to disable warnings:

   ```systemverilog
   logic _unused;
   assign _unused = &{1'b0, bidir_in, analog, input_in[NUM_INPUT_PADS-1:1]};
   ```

4. **Update your golden model and testbench** to expect the new behavior, then run the
   inner loop (`make sim`) until green.

5. **Only then** register any new files (outer loop above) and `make harden`.

That is the entire rhythm of the project: small edits, fast self-checking sims, and
hardening only on green.

---

## Pitfalls to avoid (SystemVerilog gotchas the template enforces)

These are the rules the template's lint and build steps will hold you to. Following them
keeps your harden clean.

- **`make defines` must run before any build.** The RTL does
  `` `include "generated_defines.svh" ``, and that file is generated. The `make` targets
  run this for you; if you invoke a tool by hand, run `make defines` first.
- **`` `default_nettype none `` is in force.** Declare every net explicitly — an undeclared
  signal is an error, not an implicit wire. This catches typos early.
- **Do not rename the pad-ring generate blocks** in `chip_top.sv` (`bidir`, `inputs`,
  `analog`, `*_pads`) — the slot YAMLs reference them by instance path.
- **Keep the tapeout IP instances** in `chip_top.sv` (`qrcode_id`, `shuttle_id`,
  `project_id`, `marker`) — they are required for tapeout. Only `logo` is optional.
- **Give core parameters inert default values.** `iverilog -g2012` rejects an ANSI
  parameter with no default; the scaffold uses `= 12 / 40 / 2`, and `chip_top` overrides
  them anyway.
- **Build outputs clear-then-set, and keep the `oe` mask generate-driven.** Both idioms
  exist to keep the core latch-free and width-clean.

---

## Productionize: from the sample to *your* registered project

Editing `chip_core.sv` makes the *design* yours; a few repo-level steps make the *project*
yours, for a real submission:

1. **Fork the kit** (or copy it) and give your project a name — the name you'll register
   with wafer.space.
2. **Register your project** with wafer.space (see
   [`02_WAFERSPACE_SUBMISSION.md`](02_WAFERSPACE_SUBMISSION.md) and the site). Registration is
   what issues your per-project identity cells — the QR code and the shuttle/project IDs.
3. **Swap in the issued tapeout IP.** The kit ships *generic placeholder* identity cells so
   the flow hardens out of the box; before a real tapeout you replace them with the ones
   wafer.space issues for your registered project/shuttle. Exact steps — which files, which
   directories, keep the names — are in [`../ip/README.md`](../ip/README.md).
4. **Leave the rest of `chip_top.sv` alone** — padring, seal ring, and cell placements are
   already correct for your slot.

Everything else — sim, harden, precheck, submit — is the same loop you already ran on the
sample. The full submission mechanics are in
[`02_WAFERSPACE_SUBMISSION.md`](02_WAFERSPACE_SUBMISSION.md).

---

## Further study — the upstream template

The [wafer.space project template](https://github.com/wafer-space/gf180mcu-project-template)
is the canonical GF180MCU tapeout template this kit is built on. When you want the full
production setup, read it in this order:

1. `README.md` — the Nix-based flow end to end (`make clone-pdk`, `make librelane`,
   simulation).
2. `src/chip_top.sv` — the complete pad ring you copied in, and the cell instantiations
   that decide each pin's type (Layer A). Your model for the `oe` mask and pad
   configuration lives in `src/chip_core.sv` (Layer B).
3. `librelane/` — the production hardening config (slots, macros, power-delivery network,
   timing constraints).

When your design is ready, run it through
[gf180mcu-precheck](https://github.com/wafer-space/gf180mcu-precheck) before submitting.
The precheck is wafer.space's independent manufacturability gate — see
`02_WAFERSPACE_SUBMISSION.md`.

---

**Next:** `07_HARDENING_GUIDE.md` — turn your green RTL into a manufacturable GDSII.

---

| ◀ Previous | Up | Next ▶ |
| :--- | :---: | ---: |
| [05 · Anatomy of the Sample](05_ANATOMY_OF_THE_SAMPLE.md) | [Documentation map](../README.md#documentation-map) | [07 · Hardening Guide](07_HARDENING_GUIDE.md) |
