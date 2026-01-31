// Tick divider - generates periodic single-cycle pulses
// Counts from 0 to prescale value, then generates a tick and resets.
// Used for generating slower clock enables from a fast clock (e.g., I2C SCL timing).
//
// Parameters:
//   W - Width of the counter and prescale value (default 16 bits)
//       Determines the maximum division ratio (2^W - 1)
//
// Inputs:
//   clk      - System clock
//   rst_n    - Active-low asynchronous reset
//   enable   - Enable counting; when low, counter resets and no ticks are generated
//   prescale - Number of cycles between ticks minus 1 (tick every prescale+1 cycles)
//              Example: prescale=99 generates a tick every 100 clock cycles
//
// Outputs:
//   tick - Single-cycle pulse generated every (prescale+1) cycles when enabled
//   cnt  - Current counter value, exported for debug/waveform inspection
module tick_div #(
    parameter int W = 16
) (
    input logic clk,
    input logic rst_n,

    input logic         enable,
    input logic [W-1:0] prescale, // tick every (prescale+1) cycles while enabled

    output logic         tick,  // 1-cycle pulse
    output logic [W-1:0] cnt    // exported for waveform/debug
);

    logic unused_zero;
    assign unused_zero = &{1'b0, prescale[(W-1):0]}; // prevent lint about unused prescale bits if W < max

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt  <= '0;
            tick <= 1'b0;
        end else if (!enable) begin
            cnt  <= '0;
            tick <= 1'b0;
        end else begin
            if (cnt == prescale) begin
                cnt  <= '0;
                tick <= 1'b1;
            end else begin
                // this is a fancy way to write: cnt <= cnt + 1;
                // but avoids synthesis tools complaining about width mismatch
                // here we have 2 operations
                //  Concatenation: {a, b}
                //    Joins bit-vectors end-to-end. e.g., {2'b10, 3'b101} = 5'b10101
                //  Replication: {N{value}}
                //    Creates N copies of value and concatenates them. e.g., {3{2'b01}} = 6'b010101
                // So {{(W - 1) {1'b0}}, 1'b1} creates a W-bit vector with only the LSB set to 1
                // NOTE: this could be written also as
                // cnt <= cnt + 'd1; (unsized!)
                // cnt <= cnt + W'(1); - to cast 1 to W bits
                // cnt <= cnt + $unsigned(W'(1)); - to cast 1 to W bits unsigned explicitly
                cnt  <= cnt + {{(W - 1) {1'b0}}, 1'b1};
                tick <= 1'b0;
            end
        end
    end

endmodule
