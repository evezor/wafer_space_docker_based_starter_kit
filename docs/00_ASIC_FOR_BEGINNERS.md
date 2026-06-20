# 00 · ASIC for Beginners

A pure-concepts primer. No tools, no commands — just the words you need so every other doc in this kit reads clearly. Skim it once, then come back whenever a later doc uses a term you don't recognize.

---

## You can do this

Making a custom chip used to require a multi-million-dollar tool license and a PhD. That is no longer true. The tools in this kit are free and open-source, the process (GF180MCU) is openly documented, and **wafer.space** runs shared manufacturing "shuttles" so you only pay for a small slice of a wafer. This primer explains the words. You do not need to memorize them — just skim, then come back when a later doc uses a term you don't recognize.

---

## What is an ASIC / custom chip?

**ASIC** stands for **Application-Specific Integrated Circuit**. It is a chip you design to do one specific thing, etched permanently into silicon.

Here is the key difference from a microcontroller: a microcontroller is a chip you *program* — you write software and it runs on fixed hardware. An ASIC is a chip you *wire* — you design the hardware itself. Once it is made, its logic is fixed; you cannot reprogram what the transistors do. That sounds scary, but it is exactly why simulation (proving it works *before* you build it) is so important, and why this kit makes simulation the easy, fast, repeatable step.

## What is a PDK?

A **PDK (Process Design Kit)** is the rulebook plus the parts catalog for one specific factory process. It tells the design tools how big transistors are, which metal layers exist, and what geometry is legal to draw.

This kit uses **GF180MCU** — GlobalFoundries' **180 nanometer** process, which has an open-source PDK. "180 nm" is the size of the smallest features the factory can make. By modern phone-chip standards that is old and large — which is exactly what you want for a first chip: it is cheap, rugged, forgiving, and **5 V** tolerant. (For reference, this kit pins the PDK to a specific known-good version, the `gf180mcuD` variant, so everyone gets identical, reproducible results.)

## What is RTL?

**RTL** stands for **Register-Transfer Level**. It is your design, written as code, in a **hardware description language** (HDL). This kit uses **SystemVerilog**.

RTL describes **registers** (memory bits that hold a value) and the logic between them. It *looks* like programming, but it is not a sequence of instructions that run one after another. It describes **hardware that all runs at once** — every gate, every wire, simultaneously, on every clock tick. Learning to think "in parallel" instead of "step by step" is the main mental shift of digital design, and the example chip in this kit is small enough to make that shift gently.

> 📚 **Never written Verilog/SystemVerilog?** You'll write your logic in it, so if the language
> is new, spend an hour with one of these first — they teach the "parallel hardware" mindset
> with instant feedback: [HDLBits](https://hdlbits.01xz.net/) (interactive Verilog exercises),
> [nandland](https://nandland.com/) (beginner Verilog/FPGA tutorials), and
> [ZipCPU's tutorials](https://zipcpu.com/tutorial/). The example chip is deliberately tiny so
> you can also learn by reading and editing it.

## The journey of a design

Your RTL goes through a pipeline of automated tools to become a physical layout. Here is each stage in one plain sentence:

1. **RTL** — you write the design as SystemVerilog code.
2. **Synthesis** — software (**Yosys**) translates your RTL into a **netlist**: a list of real **standard cells** (pre-designed AND/OR/flip-flop building blocks from the PDK) and the wires between them.
3. **Floorplan** — the tools decide the overall shape and size of the chip and where the big blocks go.
4. **Placement** — the tools (**OpenROAD**) decide exactly where on the die each standard cell sits.
5. **Clock-tree synthesis (CTS)** — the tools build a carefully balanced network so the clock signal reaches every flip-flop at almost the same instant.
6. **Routing** — the tools draw the metal wires that connect every cell.
7. **GDSII** — the tools emit the final layout file.

Steps 3–6 together are called **place-and-route (PnR)**.

**GDSII** (a `.gds` file) is the final output: an exact geometric blueprint of every shape on every layer. **This is what you send to the fab.**

## The signoff checks

Before a layout can be manufactured, it must pass a set of automated **signoff** checks. Each one proves something specific:

| Check | Plain-English: what it proves |
|---|---|
| **DRC** (Design Rule Check) | The geometry is *manufacturable* — no shapes too small or too close together for the factory to make. |
| **LVS** (Layout vs Schematic) | The drawn layout is *electrically identical* to the verified netlist. Nothing got lost in translation. This is the one that matters most. |
| **Antenna** | No metal wire is so long during manufacturing that built-up static charge could damage a transistor gate. |
| **Density** | Each layer has enough (but not too much) metal, as the factory requires for even, reliable manufacturing. |
| **PDN / power-grid** | The power and ground mesh actually reaches every cell, so the whole chip is powered. |

> A clean result on all of these — every count is **0** — is what "manufacturable" means. The example chip in this kit passes all of them, and so will your design if you follow [`07_HARDENING_GUIDE.md`](07_HARDENING_GUIDE.md).

## What is a tapeout? A shuttle? wafer.space?

A **tapeout** is the moment you finalize the GDSII and hand it off to be made. The name is a holdover from when designs were literally shipped to the factory on magnetic tape.

A **shuttle** (also called a **multi-project wafer**, or MPW) is a single manufacturing run shared by many small designs. Instead of paying for an entire wafer yourself, you share one with many other designers and pay only for your slice. That is what makes a custom chip affordable for a hobbyist.

**wafer.space** is a service that runs GF180MCU shuttles for hobbyists and small teams. You submit your GDSII for a **slot** of a given size. This kit targets the `1x1` (full) slot by default — the full slot menu and submission details are in [`02_WAFERSPACE_SUBMISSION.md`](02_WAFERSPACE_SUBMISSION.md).

> ℹ️ **Confirm on wafer.space:** the exact submission portal URL, the accepted submission format, and the current shuttle deadline. These live on the wafer.space site, not in this repo.

## Standard cells and pads

**Standard cells** are the LEGO bricks of digital chips: tiny, pre-characterized logic gates (AND, OR, NOT…) and flip-flops that the PDK provides. You never draw a transistor by hand — synthesis assembles your design out of these ready-made cells. This kit uses the `gf180mcu_fd_sc_mcu7t5v0` standard-cell library (a 7-track, 5 V library — the proven default).

**Pads** are the big metal squares around the edge of the die where the chip connects to the outside world: power, ground, and signals. Thin wires are bonded from these pads to the legs of the chip's package. This kit uses the `gf180mcu_fd_io` pad library, which provides 5 V I/O pads.

Each wafer.space slot gives you a fixed budget of pads. The default `1x1` slot, for example, provides **12 input pads, 40 bidirectional ("bidir") pads, and 2 analog pads** (plus power, ground, clock, and reset). A **bidir** pad can act as an input or an output — your design controls which, at runtime.

## Digital vs analog — why this kit is digital-only

Chips come in two broad flavors. **Digital** circuits work in clean 1s and 0s (on/off). **Analog** circuits work with continuous voltages — think audio amplifiers or radio front-ends. Analog design is a deep, specialized craft with very different tools.

This kit is **digital-only**. Everything here — the RTL, the simulation, the synthesis, the place-and-route — assumes you are building digital logic. The slot does expose a few analog pads, but wiring up real analog circuitry is out of scope for a beginner kit. Sticking to digital keeps the whole flow automated and reliable, which is exactly what you want for your first chip.

---

## Glossary

One-liners for the terms used across these docs, alphabetized.

- **Antenna** — a signoff check that no wire is long enough during manufacturing to build up gate-damaging charge.
- **ASIC** — Application-Specific Integrated Circuit; a chip designed (wired) to do one fixed thing.
- **BCLK** — the build/board clock; the clock signal that drives the chip's flip-flops.
- **bidir pad** — a pad that can act as an input *or* an output, with the direction chosen by your design at runtime.
- **cocotb** — a Python framework for writing chip testbenches; this kit uses it for the optional, PDK-aware, pad-level test.
- **CTS** — Clock-Tree Synthesis; building a balanced network so the clock reaches every flip-flop at the same instant.
- **die** — a single chip's worth of silicon cut from the wafer.
- **DRC** — Design Rule Check; proves the geometry is manufacturable.
- **GDS / GDSII** — the final layout file; an exact geometric blueprint of every shape on every layer. What you send to the fab.
- **golden model / golden vector** — a separate, simple reference (often Python) that computes the *expected* output, used to check your design bit-for-bit.
- **HDL** — Hardware Description Language; the kind of language RTL is written in (here, SystemVerilog).
- **Liberty / `.lib`** — a file describing the timing and power behavior of standard cells, used by the timing tools.
- **LibreLane** — the open-source flow that orchestrates synthesis, place-and-route, and signoff (it drives OpenROAD, Yosys, Magic, KLayout, and Netgen).
- **LVS** — Layout vs Schematic; proves the drawn layout is electrically identical to the netlist.
- **netlist** — a list of cells and the wires connecting them; the output of synthesis.
- **OpenROAD** — the open-source place-and-route engine.
- **pad** — a large metal square at the die edge where the chip connects to the outside world.
- **PDK** — Process Design Kit; the rulebook plus parts catalog for one factory process.
- **PDN** — Power Distribution Network; the on-chip mesh of power and ground wires.
- **PnR** — Place-and-Route; the floorplan → placement → CTS → routing stages together.
- **RTL** — Register-Transfer Level; your design written as HDL code.
- **SCL** — Standard-Cell Library; the catalog of pre-built logic cells (here, `gf180mcu_fd_sc_mcu7t5v0`).
- **SDC / timing constraint** — a file telling the tools how fast the clock must run, so they can check timing.
- **seal ring** — a protective ring of metal around the die edge required for manufacturing.
- **shuttle / MPW** — a shared manufacturing run; you pay for one slot, not a whole wafer.
- **SPEF** — a file describing the parasitic resistance and capacitance of the routed wires, used for accurate timing.
- **standard cell** — a pre-designed logic gate or flip-flop from the PDK; the building block of digital chips.
- **synthesis** — translating RTL into a netlist of standard cells (done by Yosys).
- **tapeout** — finalizing the GDSII and handing it off to be manufactured.
- **tri-state** — a wire that can be driven high, driven low, or left floating (high-impedance); how a bidir pad "turns off" its output.
- **WNS / setup / hold** — timing terms. *Setup* and *hold* are the two timing rules a flip-flop must satisfy; **WNS** (Worst Negative Slack) is how much the worst path misses the setup deadline (0 or positive means timing is met).

---

## Where to go next

You now have the vocabulary. Time to get your hands on the kit: go to [`01_GETTING_STARTED.md`](01_GETTING_STARTED.md) to install the prerequisites and get the example chip simulating green on your machine.

---

| ◀ Previous | Up | Next ▶ |
| :--- | :---: | ---: |
| [Project README](../README.md) | [Documentation map](../README.md#documentation-map) | [01 · Getting Started](01_GETTING_STARTED.md) |
