// `timescale 1ns / 1ps

module tb_i2c_bit_prim;

    logic clk = 0;
    always #5 clk = ~clk;

    logic rst_n;

    // bus nets
    tri1  scl;
    tri1  sda;

    // master-side sync view
    logic scl_sync, sda_sync;

    // drives from master primitive
    logic scl_pull, sda_pull;

    // fake slave controls
    (* keep *)logic slave_scl_pull;  // stretch
    (* keep *)logic slave_sda_pull;  // drive SDA low (open-drain)

    // connect slave open-drain to bus
    assign scl = slave_scl_pull ? 1'b0 : 1'bz;
    assign sda = slave_sda_pull ? 1'b0 : 1'bz;

    // pads
    i2c_od_pads u_pads (
        .clk(clk),
        .rst_n(rst_n),
        .scl_pull(scl_pull),
        .sda_pull(sda_pull),
        .scl_sync(scl_sync),
        .sda_sync(sda_sync),
        .scl(scl),
        .sda(sda)
    );

    // DUT
    logic start, op_read, tx_bit;
    logic busy, done, rx_bit;
    logic [15:0] prescale;

    i2c_bit_prim #(
        .W(16)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .prescale(prescale),
        .scl_sync(scl_sync),
        .sda_sync(sda_sync),
        .scl_pull(scl_pull),
        .sda_pull(sda_pull),
        .start(start),
        .op_read(op_read),
        .tx_bit(tx_bit),
        .busy(busy),
        .done(done),
        .rx_bit(rx_bit)
    );

    // helper: pulse start for 1 cycle
    task automatic kick;
        begin
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
        end
    endtask

    initial begin
`ifndef COCOTB_SIM
        $dumpfile("tb_i2c_bit_prim.fst");
        $dumpvars(0, tb_i2c_bit_prim);
`endif

        rst_n = 0;
        start = 0;
        op_read = 0;
        tx_bit = 1;
        prescale = 16'd1;  // fast ticks for demo

        slave_scl_pull = 0;
        slave_sda_pull = 0;

        repeat (3) @(posedge clk);
        rst_n = 1;
    end

`ifndef COCOTB_SIM
    // ---------- standalone stimulus (disabled under cocotb) ----------
    initial begin
        // ---- WRITE bit = 0 (master pulls SDA low) ----
        op_read = 0;
        tx_bit  = 0;
        kick();
        wait (done);
        @(posedge clk);

        // ---- WRITE bit = 1 (master releases SDA) ----
        tx_bit = 1;
        kick();
        wait (done);
        @(posedge clk);

        // ---- READ bit with slave driving 0, and clock stretching ----
        op_read = 1;

        // prepare slave to output 0 (pull low)
        slave_sda_pull = 1;

        // stretch SCL for a while after master releases it
        fork
            begin
                // stretch during the raise-high phase
                // start stretching slightly after kick
                @(posedge clk);
                @(posedge clk);
                slave_scl_pull = 1;
                repeat (6) @(posedge clk);
                slave_scl_pull = 0;
            end
        join_none

        kick();
        wait (done);
        @(posedge clk);

        // release SDA and read 1 (bus high)
        slave_sda_pull = 0;
        kick();
        wait (done);
        @(posedge clk);

        $finish;
    end
`endif

endmodule
