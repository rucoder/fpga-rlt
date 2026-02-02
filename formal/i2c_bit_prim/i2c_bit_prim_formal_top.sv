
// Formal verification top-level wrapper for i2c_bit_prim
//
// This module instantiates the i2c_bit_prim DUT with minimal assumptions
// and binds the property checker (i2c_bit_prim_props) to verify correctness.
//
// Assumptions:
// - start command only asserted when not busy
// - prescale held stable while busy
//
// The actual properties are defined in i2c_bit_prim_props.sv
//
module i2c_bit_prim_formal_top;

    logic clk;
    logic rst_n;

    logic [15:0] prescale;
    logic scl_sync, sda_sync;
    logic scl_pull, sda_pull;
    logic start, op_read, tx_bit;
    logic busy, done, rx_bit;

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

    // --- minimal assumptions for sanity (SBY/Yosys is fine with these) ---
    logic past_valid;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) past_valid <= 1'b0;
        else past_valid <= 1'b1;
    end

    always_ff @(posedge clk)
        if (past_valid && rst_n) begin
            // start only when not busy
            if (busy) assume (!start);

            // keep prescale stable while busy (avoids moving target)
            if ($past(busy) && busy) assume (prescale == $past(prescale));
        end

    // Bind connects to internal DUT signals via (.*)
    bind i2c_bit_prim i2c_bit_prim_props props_i (.*);
endmodule
