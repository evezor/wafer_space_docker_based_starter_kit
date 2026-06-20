# 06 — Continue the Design

You have a green simulation and (maybe) a clean GDSII from the scaffold. Now you make
the chip *yours*. This page is the "where do I look / how do I keep going" guide: exactly
which file to edit, the rules that file must obey, how to build a trustworthy test, and
how to grow from the trivial scaffold into a real design.

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

## The one file you edit: `src/chip_core.sv`

`chip_core` is your design. It sits entirely behind the pad ring and talks to the outside
world only through the pad contract described below. The shipped version is a tiny
heartbeat counter so the scaffold is green and harden-clean out of the box. You replace
the body with real logic while keeping the port list and pad-config contract intact.

### What *not* to touch in `chip_top.sv`

`src/chip_top.sv` is a **do-not-edit boundary**. It is copied verbatim from the
wafer.space project template and contains no design logic of its own — it is pure
plumbing between the silicon pads and your core. Specifically, do not:

- Rename the pad-ring **generate blocks** (`bidir`, `inputs`, `analog`, `*_pads`). The
  slot YAML files (`librelane/slots/slot_*.yaml`) reference these blocks by instance path
  to place pads. Rename one and the harden breaks.
- Remove the required **tapeout IP cells** (more on these in
  `02_WAFERSPACE_SUBMISSION.md`): `qrcode_id`, `shuttle_id`, `project_id`, and `marker`.
  The `logo` cell is decorative and may be removed.

The only legitimate reasons to edit `chip_top.sv` are (a) you change which slot you
target, or (b) you genuinely need a different pad *type* on some pad. Both are advanced
moves; see `src/README.md`.

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

module chip_core #(
    // Defaults are placeholders; chip_top always overrides all three explicitly.
    // iverilog -g2012 requires a default in the ANSI parameter port list.
    parameter NUM_INPUT_PADS  = 4,
    parameter NUM_BIDIR_PADS  = 46,
    parameter NUM_ANALOG_PADS = 4
)(
    `ifdef USE_POWER_PINS
    inout  wire VDD,
    inout  wire VSS,
    `endif

    input  wire clk,
    input  wire rst_n,                                  // active low

    input  wire [NUM_INPUT_PADS-1:0] input_in,
    output wire [NUM_INPUT_PADS-1:0] input_pu,
    output wire [NUM_INPUT_PADS-1:0] input_pd,

    input  wire [NUM_BIDIR_PADS-1:0] bidir_in,
    output wire [NUM_BIDIR_PADS-1:0] bidir_out,
    output wire [NUM_BIDIR_PADS-1:0] bidir_oe,
    output wire [NUM_BIDIR_PADS-1:0] bidir_cs,
    output wire [NUM_BIDIR_PADS-1:0] bidir_sl,
    output wire [NUM_BIDIR_PADS-1:0] bidir_ie,
    output wire [NUM_BIDIR_PADS-1:0] bidir_pu,
    output wire [NUM_BIDIR_PADS-1:0] bidir_pd,

    inout  wire [NUM_ANALOG_PADS-1:0] analog
);
```

> ℹ️ **Note:** the parameter defaults (`4 / 46 / 4`) are *inert placeholders*. The
> `iverilog -g2012` SystemVerilog mode rejects an ANSI parameter that has no default, so
> you must give each one a value — but `chip_top` always overrides all three explicitly
> with the values for your chosen slot. Do not delete the defaults.

The scaffold's `chip_core.sv` already matches this and is **SRAM-free** (it contains no
on-chip RAM macros). Do not add SRAM macros unless you also wire them into
`librelane/macros/*.yaml` and the power-delivery network; see `08_TROUBLESHOOTING.md`
(symptom #4) for why a stray SRAM reference breaks the harden.

---

## The pad model and the `oe` direction contract

A **pad** is one physical connection point on the edge of the die. Your slot gives you
three kinds.

### Input pads (`input_in[]`)

These are **always inputs** — data only ever flows into the core.

- The core reads data on `input_in[i]`.
- The core drives each pad's pull configuration via `input_pu[i]` / `input_pd[i]` (a
  *pull-up* gently holds the pin high, a *pull-down* holds it low). The scaffold sets both
  to `0` — **no internal pull resistors**.
- Because there are no pulls, **any input you do not drive must be tied off inside your
  core**. On the finished chip an undriven, unpulled input pin would otherwise *float*
  (sit at an undefined voltage). Adding board-level pulls is part of bring-up, which is
  beyond this kit's scope.

### Bidir pads (`bidir_*`) and the `oe` mask

A **bidir** (bidirectional) pad can act as an output *or* an input — you choose, **per
bit**, with the **output-enable** signal `bidir_oe`:

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

### Analog pads (`analog[]`)

These are reserved **5 V analog** pads. They are not wired to logic by default — there is
no digital data and no `oe`. Leave them alone unless you have a specific analog plan.

---

## How to assign functions to pads (the soft-budget rule)

The default slot for this kit is `1x1`, whose budget is **12 input + 40 bidir + 2
analog** pads. It is tempting to read the input-pad count as a hard limit. It is not.

> **The pad-category split is *soft* — only the per-slot total is hard.** Because bidir
> pads are direction-configurable, the `1x1` slot gives you about **52 assignable signal
> pads** (12 input + 40 bidir; analog separate). A bidir pad set as an input (`oe=0`) is
> just as good as a dedicated input pad.

So if your design needs ten control inputs, put a few on the input pads and route the rest
onto bidir pads configured as inputs. Assign functions to whatever pads are convenient —
just stay within the total.

(For the full per-slot numbers, see `02_WAFERSPACE_SUBMISSION.md`.)

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
  parameter with no default; the scaffold uses `= 4 / 46 / 4`, and `chip_top` overrides
  them anyway.
- **Build outputs clear-then-set, and keep the `oe` mask generate-driven.** Both idioms
  exist to keep the core latch-free and width-clean.

---

## Further study — the upstream template

The [wafer.space project template](https://github.com/wafer-space/gf180mcu-project-template)
is the canonical GF180MCU tapeout template this kit is built on. When you want the full
production setup, read it in this order:

1. `README.md` — the Nix-based flow end to end (`make clone-pdk`, `make librelane`,
   simulation).
2. `src/chip_top.sv` — the complete pad ring you copied in. Your model for the `oe` mask
   and pad assignment lives in `src/chip_core.sv`.
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
