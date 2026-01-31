module tick_div_props #(
    parameter int W = 16
) (
    input logic         clk,
    input logic         rst_n,
    input logic         enable,
    input logic [W-1:0] prescale,
    input logic         tick,
    input logic [W-1:0] cnt
);

    logic past_valid;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) past_valid <= 1'b0;
        else past_valid <= 1'b1;
    end

    // Assumption: prescale doesn't change while enabled (common contract)
    always_ff @(posedge clk)
        if (past_valid && rst_n) begin
            if ($past(enable) && enable) begin
                assume (prescale == $past(prescale));
            end
        end

    // 1) Reset behavior
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            assert (cnt == '0);
            assert (tick == 1'b0);
        end
    end

    // 2) Disabled behavior
    always_ff @(posedge clk)
        if (rst_n) begin
            if (!enable) begin
                assert (cnt == '0);
                assert (tick == 1'b0);
            end
        end

    // 3) Step behavior when enabled
    always_ff @(posedge clk)
        if (past_valid && rst_n) begin
            // if we were enabled in the previous cycle, current outputs must match the step
            if ($past(enable)) begin
                if ($past(cnt) == $past(prescale)) begin
                    assert (cnt == '0);
                    assert (tick == 1'b1);
                end else begin
                    assert (cnt == ($past(cnt) + W'(1)));
                    assert (tick == 1'b0);
                end
            end
        end

    // 4) Tick only on wrap (and only when enabled previously)
    always_ff @(posedge clk)
        if (past_valid && rst_n) begin
            if (tick) begin
                assert ($past(enable));
                assert ($past(cnt) == $past(prescale));
            end
        end

    // A small cover: eventually we can see a tick when enabled
    always_ff @(posedge clk)
        if (past_valid && rst_n) begin
            cover (enable && tick);
        end

endmodule


module tick_div_formal;

    localparam int W = 16;

    logic clk;
    logic rst_n;

    logic enable;
    logic [W-1:0] prescale;

    logic tick;
    logic [W-1:0] cnt;

    // Free-running clock for formal
    initial clk = 1'b0;
    always #1 clk = ~clk;

    // DUT
    tick_div #(
        .W(W)
    ) dut (
        .clk,
        .rst_n,
        .enable,
        .prescale,
        .tick,
        .cnt
    );

    // Constrain reset to eventually deassert (typical)
    initial rst_n = 1'b0;
    always_ff @(posedge clk) rst_n <= 1'b1;

    // Bind properties to DUT instance
    bind tick_div tick_div_props #(
        .W(W)
    ) props (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .prescale(prescale),
        .tick(tick),
        .cnt(cnt)
    );

endmodule
