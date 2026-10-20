# `i2c_bit_prim` — One I²C Bit Transaction Primitive

## Purpose
Perform exactly **one I²C bit-time** with correct SDA discipline and stretch-aware SCL raising.

Supports:
- **WRITE bit** (`op_read=0`): master drives SDA low for 0, releases for 1
- **READ bit** (`op_read=1`): master releases SDA and samples it while SCL high

This brick is intended to be called by a byte-level FSM:
- 8 data bits
- 1 ACK/NACK bit

---

## Interface (current + recommended evolution)

### Inputs
- `clk`, `rst_n`
- `prescale[W-1:0]` — phase pacing (via `tick_div`)
- `scl_sync`, `sda_sync` — synchronized bus inputs (from pads)
- `start` — pulse to begin when idle/ready
- `op_read` — 1=read, 0=write
- `tx_bit` — write data bit (valid if `op_read=0`)

### Outputs
- `scl_pull`, `sda_pull` — open-drain drives: 1 pulls low, 0 releases
- `busy` — level: operation in progress
- `rx_bit` — captured SDA value (for read)

### Event outputs (strongly recommended)
To avoid ambiguity and enable simple “pipelined” control from the byte FSM, expose two pulses:

- `sample_pulse` — 1-cycle pulse at the **SCL-high sample point**
  - READ: `rx_bit` updates on this event.
  - WRITE: indicates the “high phase complete” point for the bit.
- `done_pulse` — 1-cycle pulse when primitive is **fully finished and ready** to accept the next `start`
  - Typically aligned with transition back to `IDLE`.
  - If this is the meaning of `done`, then it is valid to assert: `done_pulse -> !busy`.

If you keep a single `done`, explicitly define whether it is `sample_pulse` or `done_pulse`.

---

## I²C-level contract

### Assumptions
- `scl_sync/sda_sync` are already synchronized to `clk` (may lag physical wires by ~2 clocks).
- `start` is asserted only when ready (`!busy`), OR start-while-busy is ignored (pick and document).
- `op_read/tx_bit` are stable when `start` is accepted (the primitive latches them).
- Recommended: `prescale` stable while `busy=1`.

### Guarantees
- **SDA discipline**
  - READ: `sda_pull == 0` throughout the operation (master never drives SDA).
  - WRITE: `sda_pull == (tx_bit==0)` throughout relevant phases (pull low only for 0).
  - SDA is only changed while SCL is held low (setup phase).
- **SCL discipline / stretching**
  - The primitive requests SCL high and waits for `scl_sync` (via `scl_high_ok`) to be high before sampling.
  - It does not sample SDA while SCL is observed low.
- **Sampling**
  - `rx_bit` updates only at the sample point (`sample_pulse`).

### Timing / phases (conceptual)
A minimal 4-phase state machine:
1. `IDLE` — release bus, accept `start`
2. `SETUP_LOW` — pull SCL low, set up SDA (or release for read)
3. `RAISE_HIGH` — release SCL, wait for true high, then sample on tick
4. `FINISH_LOW` — pull SCL low again, then return to `IDLE`

---

## Reset / idle outputs
- In IDLE: release both lines (`scl_pull=0`, `sda_pull=0`) so the bus floats high.

---

## Testbench implications (very important)
There are two valid ways to test this block:

### A) Unit-test the primitive (drive `scl_sync/sda_sync` directly)
- No pads, no tri-bus.
- You explicitly control the synchronized inputs.
- Fastest + least fragile tests.

### B) System-test including pads + tri-state bus
- You drive the **wire-level** bus via open-drain sources and observe `*_sync`.
- You must respect synchronizer delay:
  - after changing slave drive, wait ~2 clocks before expecting `*_sync` to reflect it.
- This matches hardware best.

---

## Composition notes for `i2c_byte` FSM
A clean composition pattern is:
- wait `ready = !busy`
- assert `start` for 1 cycle with the next bit command
- use `sample_pulse` to shift read bits (or mark completion point)
- use `done_pulse` (or `ready`) to know the primitive is ready for the next bit

This allows a “pipeline”: you can **shift/update byte state at `sample_pulse`** while the primitive is finishing its low phase.

---

## Formal hooks (suggested)
- `READ -> sda_pull==0 while busy`
- `WRITE -> sda_pull==(tx_bit_q==0) while busy`
- `rx_bit` changes only when `sample_pulse`
- `sample_pulse -> scl_high_ok`
- `done_pulse -> !busy` (if `done_pulse` semantics chosen)
