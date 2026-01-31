`timescale 1ns / 1ps

module tb_i2c_scl_req;

    logic clk = 0;
    always #5 clk = ~clk;

    logic rst_n;

    // bus nets with pullups
    tri1  scl;
    tri1  sda;

    // master intent
    logic want_scl_high;
    logic scl_pull;
    logic sda_pull;

    // slave stretching control
    logic slave_scl_pull;

    // synchronized bus view
    logic scl_sync, sda_sync;
    logic scl_high_ok;

    // TB slave drives SCL low when stretching
    assign scl = slave_scl_pull ? 1'b0 : 1'bz;

    // pads (master open-drain + sync back)
    i2c_od_pads dut_pads (
        .clk(clk),
        .rst_n(rst_n),
        .scl_pull(scl_pull),
        .sda_pull(sda_pull),
        .scl_sync(scl_sync),
        .sda_sync(sda_sync),
        .scl(scl),
        .sda(sda)
    );

    // our new brick under test
    i2c_scl_req dut_req (
        .clk(clk),
        .rst_n(rst_n),
        .want_scl_high(want_scl_high),
        .scl_sync(scl_sync),
        .scl_pull(scl_pull),
        .scl_high_ok(scl_high_ok)
    );

    initial begin
        $dumpfile("tb_i2c_scl_req.vcd");
        $dumpvars(0, tb_i2c_scl_req);

        rst_n          = 0;

        // idle: release both
        want_scl_high  = 1;
        sda_pull       = 0;
        slave_scl_pull = 0;

        repeat (3) @(posedge clk);
        rst_n = 1;

        // 1) Force SCL low (master pulls low)
        want_scl_high = 0;
        repeat (5) @(posedge clk);

        // 2) Request SCL high, but slave stretches for a while
        slave_scl_pull = 1;  // slave holds SCL low
        want_scl_high  = 1;  // master releases SCL
        repeat (8) @(posedge clk);

        // 3) Slave releases, SCL should become high, and scl_high_ok should go 1 (after sync latency)
        slave_scl_pull = 0;
        repeat (10) @(posedge clk);

        // 4) Pull low again (end of phase)
        want_scl_high = 0;
        repeat (5) @(posedge clk);

        $finish;
    end

endmodule
