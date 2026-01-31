module i2c_od_pads (
    input logic clk,
    input logic rst_n,

    // internal control: 1 = pull low, 0 = release
    input logic scl_pull,
    input logic sda_pull,

    // synchronized internal view of the bus pins
    output logic scl_sync,
    output logic sda_sync,

    // physical pins (for sim); on FPGA you'll map these through IOBUFs
    inout wire scl,
    inout wire sda
);

    // Open-drain drive: only drive 0, otherwise Z (release)
    assign scl = scl_pull ? 1'b0 : 1'bz;
    assign sda = sda_pull ? 1'b0 : 1'bz;

    // Raw reads from pins
    wire scl_in = scl;
    wire sda_in = sda;

    // Synchronize to clk domain
    sync_2ff #(
        .RST_VAL(1'b1)
    ) u_scl_sync (
        .clk(clk),
        .rst_n(rst_n),
        .async_in(scl_in),
        .sync_out(scl_sync)
    );

    sync_2ff #(
        .RST_VAL(1'b1)
    ) u_sda_sync (
        .clk(clk),
        .rst_n(rst_n),
        .async_in(sda_in),
        .sync_out(sda_sync)
    );

endmodule
