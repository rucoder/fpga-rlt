`timescale 1ns / 1ps

module tb_sync_2ff;

    logic clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    logic rst_n;
    logic async_in;
    /* verilator lint_off UNUSEDSIGNAL */
    logic sync_out;
    /* verilator lint_on UNUSEDSIGNAL */

    // If you want reset-to-0 instead, set RST_VAL=0 here
    sync_2ff #(
        .RST_VAL(1'b1)
    ) dut (
        .clk,
        .rst_n,
        .async_in,
        .sync_out
    );

    initial begin
        $dumpfile("tb_sync_2ff.vcd");
        $dumpvars(0, tb_sync_2ff);

        // init
        rst_n    = 0;
        async_in = 1'b1; // matches pull-up / idle-high idea

        // hold reset for a couple clocks
        repeat (3) @(posedge clk);
        rst_n = 1;

        // Now poke async_in at weird times (not on posedge)
        #7 async_in = 1'b0;  // between edges
        #11 async_in = 1'b1;  // between edges
        #3 async_in = 1'b0;  // very close to next edge (in real silicon: metastability risk)
        #20 async_in = 1'b1;

        // Short pulse that may be missed if it doesn't overlap sampling edge
        #4 async_in = 1'b0;
        #3 async_in = 1'b1;

        repeat (10) @(posedge clk);
        $finish;
    end

endmodule
