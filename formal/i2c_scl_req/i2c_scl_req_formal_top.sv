module i2c_scl_req_props (
    input logic clk,
    input logic rst_n,
    input logic want_scl_high,
    input logic scl_sync,
    input logic scl_pull,
    input logic scl_high_ok
);
    always_ff @(posedge clk) begin
        if (rst_n) begin
            assert (scl_pull == ~want_scl_high);
            assert (scl_high_ok == (want_scl_high & scl_sync));
        end
    end
endmodule


module i2c_scl_req_formal_top;
    logic clk;
    logic rst_n;

    logic want_scl_high;
    logic scl_sync;

    logic scl_pull;
    logic scl_high_ok;

    i2c_scl_req dut (
        .clk(clk),
        .rst_n(rst_n),
        .want_scl_high(want_scl_high),
        .scl_sync(scl_sync),
        .scl_pull(scl_pull),
        .scl_high_ok(scl_high_ok)
    );

    // Simple clock/reset constraints for formal
    logic past_valid;
    always_ff @(posedge clk) past_valid <= 1'b1;

    always_ff @(posedge clk) begin
        if (!past_valid)
            assume (rst_n == 1'b0);
            else assume (rst_n == 1'b1);
    end

    bind i2c_scl_req i2c_scl_req_props props (
        .clk(clk),
        .rst_n(rst_n),
        .want_scl_high(want_scl_high),
        .scl_sync(scl_sync),
        .scl_pull(scl_pull),
        .scl_high_ok(scl_high_ok)
    );
endmodule
