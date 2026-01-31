// Two-stage flip-flop synchronizer for clock domain crossing
// Reduces metastability risk when synchronizing asynchronous signals
// into a clock domain. Uses two sequential flip-flops to allow
// metastability to settle before the signal is used.
//
// Parameters:
//   RST_VAL - Reset value for both flip-flops (default 1'b1)
//             Set to 1'b1 for open-collector/open-drain signals (e.g., I2C)
//             where the idle state is pulled high, or for active-low signals
//
// Inputs:
//   clk      - Clock for the destination domain
//   rst_n    - Active-low asynchronous reset
//   async_in - Asynchronous input signal from another clock domain
//
// Outputs:
//   sync_out - Synchronized output signal, safe to use in clk domain
module sync_2ff #(
    parameter logic RST_VAL = 1'b1
) (
    input  logic clk,
    input  logic rst_n,
    input  logic async_in,
    output logic sync_out
);

    logic sync_ff1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_ff1 <= RST_VAL;
            sync_out <= RST_VAL;
        end else begin
            sync_ff1 <= async_in;
            sync_out <= sync_ff1;
        end
    end

endmodule
