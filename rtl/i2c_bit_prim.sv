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
    output logic done,   // 1-cycle pulse
    output logic rx_bit  // sampled SDA during SCL high
);

    // ----------------------------
    // tick generator
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
    // stretch-aware SCL control
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
    // FSM
    // ----------------------------
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_SETUP_LOW,   // ensure SCL low; set SDA for write or release for read
        ST_RAISE_HIGH,  // request SCL high; wait for scl_high_ok; then sample SDA on tick
        ST_FINISH_LOW   // pull SCL low, finish op
    } st_t;

    st_t  st;

    // latch command so it doesn't change mid-op
    logic op_read_q;
    logic tx_bit_q;

    // busy/done
    assign busy = (st != ST_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st        <= ST_IDLE;
            op_read_q <= 1'b0;
            tx_bit_q  <= 1'b1;
            rx_bit    <= 1'b1;
        end else begin
            unique case (st)
                ST_IDLE: begin
                    if (start) begin
                        op_read_q <= op_read;
                        tx_bit_q  <= tx_bit;
                        st        <= ST_SETUP_LOW;
                    end
                end

                // Wait one tick in SCL-low setup phase
                ST_SETUP_LOW: begin
                    if (tick) st <= ST_RAISE_HIGH;
                end

                // Request SCL high. When it is actually high (no stretch),
                // wait for a tick boundary then sample SDA and move on.
                ST_RAISE_HIGH: begin
                    if (scl_high_ok && tick) begin
                        rx_bit <= sda_sync;
                        st     <= ST_FINISH_LOW;
                    end
                end

                // Pull SCL low for one tick, then go idle
                ST_FINISH_LOW: begin
                    if (tick) st <= ST_IDLE;
                end

                default: st <= ST_IDLE;
            endcase
        end
    end

    // combinational outputs for SDA + want_scl_high + done pulse
    always_comb begin
        // defaults: bus released
        want_scl_high = 1'b1;
        sda_pull      = 1'b0;
        done          = 1'b0;

        unique case (st)
            ST_IDLE: begin
                // idle bus: release both
                want_scl_high = 1'b1;
                sda_pull      = 1'b0;
            end

            ST_SETUP_LOW: begin
                // SCL must be low while we set up SDA
                want_scl_high = 1'b0;  // => scl_pull=1
                if (op_read_q) begin
                    // READ: release SDA so slave can drive
                    sda_pull = 1'b0;
                end else begin
                    // WRITE: tx_bit=0 => pull low; tx_bit=1 => release
                    sda_pull = (tx_bit_q == 1'b0);
                end
            end

            ST_RAISE_HIGH: begin
                // Release SCL; keep SDA stable
                want_scl_high = 1'b1;

                if (op_read_q) begin
                    sda_pull = 1'b0;  // release
                end else begin
                    sda_pull = (tx_bit_q == 1'b0);
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

                // pulse done while in this state (you can also pulse on transition)
                done = 1'b1;
            end
        endcase
    end
endmodule
