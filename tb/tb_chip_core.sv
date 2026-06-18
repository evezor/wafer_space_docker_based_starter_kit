// SPDX-License-Identifier: Apache-2.0
//
// tb_chip_core: self-checking test for the scaffold chip_core (1x0p5: 4/46/4).
//
//   - Elaborates chip_core with the real 1x0p5 pad budget, every port connected.
//   - Asserts the bidir direction mask matches the stub's contract
//     (output bits oe=1, demo-input block [11:8] oe=0, ie = ~oe everywhere).
//   - Releases reset, gates the counter ON (input pad 0 = 1), and every clock
//     captures the low 8 bits the core mirrors onto bidir_out[7:0], comparing
//     each against models/golden.hex (produced by models/ref_model.py).
//   - Prints "OK"/"FAIL" and $finish with a clean verdict line.
//
// The DUT is never adjusted to fit; only this TB's capture timing is set so a
// correct DUT yields NSAMP checks / 0 mismatches.

`timescale 1ns/1ps
`default_nettype none

module tb_chip_core;

    // ----- pad budget (1x0p5) -----
    localparam NIN   = 4;
    localparam NBI   = 46;
    localparam NAN   = 4;

    // ----- scenario constants (mirror models/ref_model.py EXACTLY) -----
    localparam NSAMP = 256;     // counter steps captured
    localparam MIRROR_W = 8;    // low counter bits the core mirrors

    // ----- DUT I/O: inputs are reg, outputs are wire -----
    reg              clk = 1'b0;
    reg              rst_n = 1'b0;

    reg  [NIN-1:0]   input_in = '0;
    wire [NIN-1:0]   input_pu;
    wire [NIN-1:0]   input_pd;

    reg  [NBI-1:0]   bidir_in = '0;
    wire [NBI-1:0]   bidir_out;
    wire [NBI-1:0]   bidir_oe;
    wire [NBI-1:0]   bidir_cs;
    wire [NBI-1:0]   bidir_sl;
    wire [NBI-1:0]   bidir_ie;
    wire [NBI-1:0]   bidir_pu;
    wire [NBI-1:0]   bidir_pd;

    wire [NAN-1:0]   analog;

    chip_core #(
        .NUM_INPUT_PADS (NIN),
        .NUM_BIDIR_PADS (NBI),
        .NUM_ANALOG_PADS(NAN)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .input_in(input_in), .input_pu(input_pu), .input_pd(input_pd),
        .bidir_in(bidir_in), .bidir_out(bidir_out), .bidir_oe(bidir_oe),
        .bidir_cs(bidir_cs), .bidir_sl(bidir_sl), .bidir_ie(bidir_ie),
        .bidir_pu(bidir_pu), .bidir_pd(bidir_pd),
        .analog(analog)
    );

    // ----- clock: 50 MHz -----
    always #10 clk = ~clk;

    // ----- the independent oracle (path relative to /work run cwd) -----
    reg [MIRROR_W-1:0] gold [0:NSAMP-1];
    initial $readmemh("models/golden.hex", gold);

    integer checks = 0;
    integer fails  = 0;
    integer k;
    reg [MIRROR_W-1:0] got;

    initial begin
        $dumpfile("chip_core.vcd");
        $dumpvars(0, tb_chip_core);

        // ---- reset, then release ----
        rst_n    = 1'b0;
        input_in = '0;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ---- direction-mask assertions (match the stub) ----
        if (bidir_oe[7:0]  !== 8'hFF) begin
            fails = fails + 1;
            $display("FAIL: bidir_oe[7:0]=%h (expected FF -- output mirror)", bidir_oe[7:0]);
        end
        if (bidir_oe[11:8] !== 4'h0) begin
            fails = fails + 1;
            $display("FAIL: bidir_oe[11:8]=%h (expected 0 -- demo input block)", bidir_oe[11:8]);
        end
        if (bidir_ie !== ~bidir_oe) begin
            fails = fails + 1;
            $display("FAIL: bidir_ie != ~bidir_oe (ie=%h oe=%h)", bidir_ie, bidir_oe);
        end

        // ---- gate the counter ON and capture the mirror each clock ----
        input_in[0] = 1'b1;        // count_en = 1
        for (k = 0; k < NSAMP; k = k + 1) begin
            @(posedge clk);        // one count step
            #1;                    // let the comb. output mirror settle
            got = bidir_out[MIRROR_W-1:0];
            checks = checks + 1;
            if (got !== gold[k]) begin
                fails = fails + 1;
                $display("frame %0d: got %0d expected %0d", k, got, gold[k]);
            end
        end

        $display("==== %0d samples checked, %0d mismatches ====", checks, fails);
        if (fails == 0) $display("OK: scaffold chip_core matched golden");
        else            $display("FAIL");
        $finish;
    end

    // ----- safety timeout -----
    initial begin
        #5_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
