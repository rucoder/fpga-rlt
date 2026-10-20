// `timescale 1ns / 1ps

module tb_i2c_bit_prim;

    logic clk;
    initial clk = 0;
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
    // ---------- heartbeat monitor: periodic state print while running ----------
    int mon_cnt;
    always @(posedge clk) begin
        mon_cnt <= mon_cnt + 1;
        if (mon_cnt % 100 == 0)
            $display("[MON] t=%0t start=%b st_q=%0d tick=%b sample=%b sclOK=%b | scl=%b sda=%b slaveSclP=%b slaveSdaP=%b busy=%b done=%b",
                     $time, start, dut.st_q, dut.u_div.tick, dut.sample_now, dut.scl_high_ok,
                     scl, sda, slave_scl_pull, slave_sda_pull, busy, done);
    end

    // ---------- watchdog: a stuck wait() fails the test, never hangs ----------
    initial begin
        repeat (100000) @(posedge clk);
        $display("TB TIMEOUT: stimulus thread stuck (last stage marker above)");
        $fatal(1);
    end

    // ---------- standalone stimulus (disabled under cocotb) ----------
    initial begin
        // Never race the reset: wait for release before the first kick
        wait (rst_n);
        repeat (2) @(posedge clk);

        // ---- WRITE bit = 0 (master pulls SDA low) ----
        op_read = 0;
        tx_bit  = 0;
        $display("[TB] WRITE0 kick @ %0t", $time);
        kick();
        wait (done);
        wait (!busy);          // walk FINISH_LOW back to idle before next kick
        @(posedge clk);

        // ---- WRITE bit = 1 (master releases SDA) ----
        tx_bit = 1;
        $display("[TB] WRITE1 kick @ %0t", $time);
        kick();
        wait (done);
        @(posedge clk);

        // ---- READ bit with slave driving 0, and clock stretching ----
        wait (!busy);          // WRITE1's FINISH_LOW must complete first
        @(posedge clk);
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

        $display("[TB] READ0 kick @ %0t", $time);
        kick();
        wait (done);
        $display("[TB] READ0 done @ %0t rx=%b", $time, rx_bit);
        wait (!busy);          // walk FINISH_LOW back to idle before next kick
        @(posedge clk);

        // release SDA and read 1 (bus high)
        slave_sda_pull = 0;
        $display("[TB] READ1 kick @ %0t", $time);
        kick();
        wait (done);
        wait (!busy);          // walk FINISH_LOW back to idle before next kick
        @(posedge clk);

        $finish;
    end
`endif

endmodule
