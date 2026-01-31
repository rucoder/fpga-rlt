`timescale 1ns / 1ps

module tb_i2c_od_pads;

    logic clk = 0;
    always #5 clk = ~clk;

    logic rst_n;

    logic scl_pull, sda_pull;
    logic scl_sync, sda_sync;

    // inout nets for the bus
    tri1  scl_bus;  // tri1 provides a weak pull-up in simulation
    tri1  sda_bus;

    // "slave" open-drain pull control (testbench side)
    logic slave_sda_pull;

    // Slave drives SDA low when slave_sda_pull=1, else releases
    assign sda_bus = slave_sda_pull ? 1'b0 : 1'bz;

    i2c_od_pads dut (
        .clk(clk),
        .rst_n(rst_n),
        .scl_pull(scl_pull),
        .sda_pull(sda_pull),
        .scl_sync(scl_sync),
        .sda_sync(sda_sync),
        .scl(scl_bus),
        .sda(sda_bus)
    );

    initial begin
        $dumpfile("tb_i2c_od_pads.fst");
        $dumpvars(0, tb_i2c_od_pads);

        rst_n = 0;
        scl_pull = 0;  // release
        sda_pull = 0;  // release
        slave_sda_pull = 0;

        repeat (3) @(posedge clk);
        rst_n = 1;

        // Master pulls SDA low (like beginning of START, but we won't do full protocol yet)
        #17 sda_pull = 1;
        #20 sda_pull = 0;

        // Slave pulls SDA low while master releases (simulate ACK or arbitration)
        #13 slave_sda_pull = 1;
        #30 slave_sda_pull = 0;

        // Master pulls SCL low then releases it
        #10 scl_pull = 1;
        #25 scl_pull = 0;

        repeat (10) @(posedge clk);
        $finish;
    end

endmodule
