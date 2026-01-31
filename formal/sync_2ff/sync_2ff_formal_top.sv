module sync_2ff_formal_top;

    logic clk;
    logic rst_n;

    logic async_in;
    logic sync_out;

    sync_2ff #(
        .RST_VAL(1'b1)
    ) dut (
        .clk,
        .rst_n,
        .async_in,
        .sync_out
    );

    // Constrain reset: low at time 0, then high forever after 1st cycle.
    // (Without this, the solver can keep rst_n low forever and "prove" anything.)
    logic past_valid;
    always_ff @(posedge clk) past_valid <= 1'b1;

    always_ff @(posedge clk) begin
        if (!past_valid) begin
            assume (rst_n == 1'b0);
        end else begin
            assume (rst_n == 1'b1);
        end
    end

    // Bind properties to the DUT
    bind sync_2ff sync_2ff_props #(
        .RST_VAL(1'b1)
    ) props (
        .clk(clk),
        .rst_n(rst_n),
        .async_in(async_in),
        .sync_out(sync_out)
    );

endmodule

module sync_2ff_props #(
    parameter int W = 1,
    parameter logic RST_VAL = 1'b1
) (
    input logic clk,
    input logic rst_n,
    input logic async_in,
    input logic sync_out
);

    logic [1:0] past_ok;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) past_ok <= 2'b00;
        else past_ok <= {past_ok[0], 1'b1};
    end

    // Reset behavior
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            assert (sync_out == RST_VAL);
        end
    end

    // Main sync property: two sampled edges of delay
    always_ff @(posedge clk) begin
        if (rst_n && past_ok[1]) begin
            assert (sync_out == $past(async_in, 2));
        end
    end

endmodule
