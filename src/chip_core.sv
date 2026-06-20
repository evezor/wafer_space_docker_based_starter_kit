// SPDX-License-Identifier: Apache-2.0
//
// chip_core: SCAFFOLD STUB -- the ONE file you edit.
//
// What it does (trivial on purpose, so the flow is green before you write logic):
//   - A free-running counter increments every clock after reset.
//     It is gated by input pad 0: counting only while input_in[0] == 1.
//   - heartbeat: a slow toggle (counter MSB) -> a bidir OUTPUT pad, for a
//     "chip alive" LED. It lives on bit HB_BIT, OUTSIDE the counter mirror.
//   - The low MIRROR_W bits of the counter are mirrored onto bidir_out[7:0]
//     so you can watch the count on a logic analyzer.
//   - A small block of bidir pads is configured as INPUTS (oe=0) just to show
//     the direction mask; the scaffold does not consume them (folded into
//     _unused).
//   - All other pads driven to a safe default. No latches. No pulls.
//
// Pad contract (must match chip_top's instantiation):
//   OUTPUT bidir bit: oe=1, ie=0 ;  INPUT bidir bit: oe=0, ie=1 (ie = ~oe).
//
// Note on the heartbeat bit: the heartbeat is placed on an output pad OUTSIDE
// the mirror window so bidir_out[7:0] is exactly counter[7:0] and matches the
// golden vector bit-for-bit. (Putting it on bit 0 would overwrite counter[0].)
//
// To build your own design: keep this port list and the pad-config assigns,
// replace the counter/heartbeat logic below with your engine.

`timescale 1ns/1ps
`default_nettype none

module chip_core #(
    // Defaults are placeholders; chip_top always overrides all three explicitly.
    // -g2012 requires a default in the ANSI parameter port list.
    parameter NUM_INPUT_PADS  = 12,
    parameter NUM_BIDIR_PADS  = 40,
    parameter NUM_ANALOG_PADS = 2
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

    // How many low counter bits to mirror onto output pads (kept small + safe).
    localparam int MIRROR_W = 8;
    // Output pad that carries the heartbeat. Outside the mirror window [7:0] and
    // outside the demo-input block [11:8], so it never collides with either.
    localparam int HB_BIT   = 12;

    // --- input pad config: no pulls ---
    assign input_pu = '0;
    assign input_pd = '0;

    // --- bidir direction mask (static; generate-driven so no latch) ---
    // bits [7:0]  = counter mirror OUTPUTS (oe=1)
    // bits [11:8] = demo INPUTS (oe=0)   [only exist if NUM_BIDIR_PADS > 8]
    // everything else = OUTPUT (oe=1)
    wire [NUM_BIDIR_PADS-1:0] oe_mask;
    genvar bi;
    generate
        for (bi = 0; bi < NUM_BIDIR_PADS; bi = bi + 1) begin : g_oe
            assign oe_mask[bi] = ((bi >= 8) && (bi <= 11)) ? 1'b0 : 1'b1;
        end
    endgenerate
    assign bidir_oe = oe_mask;
    assign bidir_ie = ~bidir_oe;     // input-enable is the complement of oe
    assign bidir_cs = '0;
    assign bidir_sl = '0;
    assign bidir_pu = '0;
    assign bidir_pd = '0;

    // --- the design: a gated free-running counter ---
    wire count_en = input_in[0];     // input pad 0 gates the counter
    reg [23:0] counter;
    always @(posedge clk) begin
        if (!rst_n)        counter <= 24'd0;
        else if (count_en) counter <= counter + 24'd1;
    end

    wire heartbeat = counter[23];    // slow "chip alive" toggle

    // tie off genuinely-unused inputs so -Wall stays quiet (no behavior change)
    logic _unused;
    assign _unused = &{1'b0, input_in[NUM_INPUT_PADS-1:1], bidir_in, analog};

    // --- drive bidir output pads (clear-then-set => no latch) ---
    logic [NUM_BIDIR_PADS-1:0] bout;
    always @(*) begin
        bout               = '0;
        bout[MIRROR_W-1:0] = counter[MIRROR_W-1:0]; // mirror low 8 counter bits -> bidir_out[7:0]
        bout[HB_BIT]       = heartbeat;             // "chip alive" LED on an output pad outside the mirror
    end
    assign bidir_out = bout;

endmodule

`default_nettype wire
