`timescale 1ns / 1ps

module tb_tick_div;

    logic clk = 0;
    always #5 clk = ~clk;  // 100 MHz if you pretend timescale is ns

    logic rst_n;
    logic enable;
    logic [15:0] prescale;
    /* verilator lint_off UNUSEDSIGNAL */
    logic tick;
    logic [15:0] cnt;
    /* verilator lint_on UNUSEDSIGNAL */

    tick_div #(
        .W(16)
    ) dut (
        .clk,
        .rst_n,
        .enable,
        .prescale,
        .tick,
        .cnt
    );

    initial begin
        $dumpfile("tb_tick_div.fst");
        $dumpvars(0, tb_tick_div);

        rst_n    = 0;
        enable   = 0;
        prescale = 16'd4;

        repeat (3) @(posedge clk);
        rst_n = 1;

        // run disabled for a bit
        repeat (5) @(posedge clk);

        // enable: tick every 5 cycles (0..4)
        enable = 1;
        repeat (30) @(posedge clk);

        // change prescale live: tick every 3 cycles (0..2)
        prescale = 16'd2;
        repeat (20) @(posedge clk);

        // disable: tick stops, counter resets
        enable = 0;
        repeat (10) @(posedge clk);

        // enable again: tick every 3 cycles (0..2)
        enable = 1;
        // run ony for 1 full cycle to check proper restart
        repeat (1) @(posedge clk);
        // initiate reset
        rst_n = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);

        $finish;
    end

endmodule
