module i2c_scl_req (
    input logic clk,
    input logic rst_n,

    // request from I2C engine:
    // 1 => want SCL high (release it)
    // 0 => want SCL low  (pull it)
    input logic want_scl_high,

    // synchronized bus level coming back from pads
    input logic scl_sync,

    // drive to pads: 1=pull low, 0=release
    output logic scl_pull,

    // status: true when we want high AND bus is actually high
    output logic scl_high_ok
);

    // Drive is purely based on what we want:
    // wanting SCL high means releasing the line.
    assign scl_pull = ~want_scl_high;

    // “ok” when bus has really gone high (handles stretching)
    assign scl_high_ok = want_scl_high & scl_sync;

endmodule
