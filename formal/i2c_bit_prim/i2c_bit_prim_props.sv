module i2c_bit_prim_props;

    // These names must match signals inside i2c_bit_prim for bind(.*) to work
    logic       clk;
    logic       rst_n;

    logic [1:0] st;

    logic       tick;

    logic       want_scl_high;
    logic       scl_high_ok;

    logic       scl_pull;
    logic       sda_pull;

    logic       op_read_q;
    logic       tx_bit_q;

    logic       busy;
    logic       done;

    logic       sda_sync;
    logic       scl_sync;

    logic       rx_bit;

    // enum encoding as written in your RTL (order matters!)
    localparam logic [1:0] ST_IDLE = 2'd0;
    localparam logic [1:0] ST_SETUP_LOW = 2'd1;
    localparam logic [1:0] ST_RAISE_HIGH = 2'd2;
    localparam logic [1:0] ST_FINISH_LOW = 2'd3;

    logic past_valid;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) past_valid <= 1'b0;
        else past_valid <= 1'b1;
    end

    // 1) SDA drive policy while busy (core I2C rule)
    always_ff @(posedge clk)
        if (rst_n && busy) begin
            if (op_read_q) begin
                assert (sda_pull == 1'b0);  // read => release SDA
            end else begin
                assert (sda_pull == (tx_bit_q == 1'b0));  // write => pull low only for 0
            end
        end

    // ----------------------------
    // Pure combinational invariants
    // ----------------------------
    always_ff @(posedge clk)
        if (rst_n) begin
            // busy matches state
            assert (busy == (st != ST_IDLE));

            // done only asserted in FINISH_LOW in this design
            assert (done == (st == ST_FINISH_LOW));

            // scl_high_ok definition (comes from i2c_scl_req semantics)
            assert (scl_high_ok == (want_scl_high & scl_sync));

            // scl_pull polarity (again i2c_scl_req semantics)
            assert (scl_pull == ~want_scl_high);

            // State -> want_scl_high expectations
            if (st == ST_SETUP_LOW || st == ST_FINISH_LOW) assert (want_scl_high == 1'b0);
            if (st == ST_IDLE || st == ST_RAISE_HIGH) assert (want_scl_high == 1'b1);

            // SDA drive rule:
            // - read: always release SDA
            // - write: pull SDA only for 0, release for 1
            if (st != ST_IDLE) begin
                if (op_read_q)
                    assert (sda_pull == 1'b0);
                    else assert (sda_pull == (tx_bit_q == 1'b0));
            end
        end

    // ----------------------------
    // rx_bit updates only at sample point
    // ----------------------------
    always_ff @(posedge clk)
        if (past_valid && rst_n) begin
            if (rx_bit != $past(rx_bit)) begin
                // It may only change when we're sampling SDA
                assert ($past(st) == ST_RAISE_HIGH);
                assert ($past(scl_high_ok && tick));
                // and the sampled value must match bus view at that time:
                assert (rx_bit == $past(sda_sync));
            end
        end

    // ----------------------------
    // FSM transition discipline
    // ----------------------------
    always_ff @(posedge clk)
        if (past_valid && rst_n) begin
            // IDLE -> SETUP only on start (we don't assert start here; we just forbid other jumps)
            if ($past(st) == ST_IDLE) begin
                // allowed: stay IDLE or go to SETUP_LOW
                assert (st == ST_IDLE || st == ST_SETUP_LOW);
            end

            // SETUP_LOW advances to RAISE_HIGH only on tick; otherwise stays
            if ($past(st) == ST_SETUP_LOW) begin
                if ($past(tick))
                    assert (st == ST_RAISE_HIGH);
                    else assert (st == ST_SETUP_LOW);
            end

            // RAISE_HIGH advances to FINISH_LOW only when (scl_high_ok && tick); otherwise stays
            if ($past(st) == ST_RAISE_HIGH) begin
                if ($past(scl_high_ok && tick))
                    assert (st == ST_FINISH_LOW);
                    else assert (st == ST_RAISE_HIGH);
            end

            // FINISH_LOW returns to IDLE only on tick; otherwise stays
            if ($past(st) == ST_FINISH_LOW) begin
                if ($past(tick))
                    assert (st == ST_IDLE);
                    else assert (st == ST_FINISH_LOW);
            end
        end
endmodule
