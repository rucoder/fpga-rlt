module i2c_bit_prim #(
    parameter int W = 16
) (
    input logic clk,
    input logic rst_n,

    // timebase: one tick per "phase step"
    input logic [W-1:0] prescale,

    // synchronized bus inputs (from i2c_od_pads)
    input logic scl_sync,
    input logic sda_sync,

    // open-drain drives to pads
    output logic scl_pull,  // 1=pull low, 0=release
    output logic sda_pull,  // 1=pull low, 0=release

    // command
    input logic start,    // pulse when idle
    input logic op_read,  // 1=read, 0=write
    input logic tx_bit,   // used when op_read=0

    // status/result
    output logic busy,
    output logic done,   // 1-cycle pulse (bit completed)
    output logic rx_bit  // sampled SDA during SCL high
);

    // ----------------------------
    // State + latched command
    // ----------------------------
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_SETUP_LOW,   // I2C: keep SCL low, set up SDA (write) / release SDA (read)
        ST_RAISE_HIGH,  // I2C: release SCL, wait for it to actually go high, then sample SDA
        ST_FINISH_LOW   // I2C: pull SCL low again to finish the bit
    } st_t;

    st_t st_q, st_d;

    logic op_read_q;
    logic tx_bit_q;

    // busy is purely "not idle"
    assign busy = (st_q != ST_IDLE);

    // ----------------------------
    // Tick generator (pacing)
    // ----------------------------
    logic tick;
    logic [W-1:0] cnt;

    tick_div #(
        .W(W)
    ) u_div (
        .clk(clk),
        .rst_n(rst_n),
        .enable(busy),
        .prescale(prescale),
        .tick(tick),
        .cnt(cnt)
    );

    // ----------------------------
    // Stretch-aware SCL control
    // ----------------------------
    logic want_scl_high;
    logic scl_high_ok;

    i2c_scl_req u_scl_req (
        .clk(clk),
        .rst_n(rst_n),
        .want_scl_high(want_scl_high),
        .scl_sync(scl_sync),
        .scl_pull(scl_pull),
        .scl_high_ok(scl_high_ok)
    );

    // ----------------------------
    // Combinational next-state logic (the "plan")
    // ----------------------------
    always_comb begin
        // default: stay put
        st_d = st_q;

        unique case (st_q)
            ST_IDLE: begin
                // Accept a new bit command only in IDLE
                if (start) st_d = ST_SETUP_LOW;
            end

            ST_SETUP_LOW: begin
                // One "phase" with SCL low to set up SDA
                if (tick) st_d = ST_RAISE_HIGH;
            end

            ST_RAISE_HIGH: begin
                // Release SCL; wait until SCL is *actually high* (no stretch),
                // then on a tick boundary we sample SDA and move to finish-low.
                if (scl_high_ok && tick) st_d = ST_FINISH_LOW;
            end

            ST_FINISH_LOW: begin
                // Pull SCL low for one phase to complete the bit
                if (tick) st_d = ST_IDLE;
            end

            default: st_d = ST_IDLE;
        endcase
    end

    // ----------------------------
    // Combinational outputs (the "signals we drive right now")
    // ----------------------------
    always_comb begin
        // defaults: bus released
        want_scl_high = 1'b1;
        sda_pull      = 1'b0;

        unique case (st_q)
            ST_IDLE: begin
                // I2C idle: release both
                want_scl_high = 1'b1;
                sda_pull      = 1'b0;
            end

            ST_SETUP_LOW: begin
                // I2C rule: change SDA only while SCL is low
                want_scl_high = 1'b0;

                if (op_read_q) begin
                    // READ: master must release SDA
                    sda_pull = 1'b0;
                end else begin
                    // WRITE: drive 0 by pulling low; drive 1 by releasing
                    sda_pull = (tx_bit_q == 1'b0);
                end
            end

            ST_RAISE_HIGH: begin
                // Release SCL; keep SDA stable through high phase
                want_scl_high = 1'b1;

                if (op_read_q) begin
                    sda_pull = 1'b0;  // release for read
                end else begin
                    sda_pull = (tx_bit_q == 1'b0);  // hold write value
                end
            end

            ST_FINISH_LOW: begin
                // Pull SCL low again; SDA can remain as it was
                want_scl_high = 1'b0;

                if (op_read_q) begin
                    sda_pull = 1'b0;
                end else begin
                    sda_pull = (tx_bit_q == 1'b0);
                end
            end
        endcase
    end

    // ----------------------------
    // "done" as a true 1-cycle completion pulse
    // ----------------------------
    // I2C meaning: "we just completed the SCL-high sample point of this bit"
    // i.e. the cycle where we sample SDA and transition RAISE_HIGH -> FINISH_LOW.
    assign done = (st_q == ST_RAISE_HIGH) && scl_high_ok && tick;

    // ----------------------------
    // Sequential state + registers (the "commit on clock edge")
    // ----------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_q      <= ST_IDLE;
            op_read_q <= 1'b0;
            tx_bit_q  <= 1'b1;
            rx_bit    <= 1'b1;
        end else begin
            st_q <= st_d;

            // Latch command at start acceptance (IDLE -> SETUP_LOW)
            if (st_q == ST_IDLE && start) begin
                op_read_q <= op_read;
                tx_bit_q  <= tx_bit;
            end

            // Sample SDA exactly at the completion event
            if (done) begin
                rx_bit <= sda_sync;
            end
        end
    end

endmodule
