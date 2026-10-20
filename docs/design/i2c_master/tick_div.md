# `tick_div` — Programmable Tick Generator

## Purpose
Generate a **single-cycle** `tick` pulse periodically while `enable=1`. This is the pacing “heartbeat” used to advance protocol FSM phases.

## Interface
- Inputs
  - `clk` — system clock
  - `rst_n` — active-low reset
  - `enable` — when 1, run the divider; when 0, stop it (and typically reset/hold)
  - `prescale[W-1:0]` — divider setting (see *Tick period* below)
- Outputs
  - `tick` — **1-cycle pulse** indicating “phase step”
  - `cnt[W-1:0]` — counter value (debug/visibility; optional)

## Contract

### Assumptions
- `enable` is synchronous to `clk`.
- `prescale` is synchronous to `clk`.
- Recommended (for simplicity and for clean proofs): **`prescale` remains stable while `enable=1`**.

### Guarantees
- `tick` is glitch-free and asserts for **exactly one `clk` cycle**.
- When `enable=0`, `tick=0`.
- When `enable=1`, `tick` asserts periodically according to `prescale`.

### Tick period (define for your implementation)
Different implementations choose different conventions. Pick one and document it in the RTL comment and here. Common patterns:

- **Pattern A (common):** `tick` when `cnt == prescale`, then `cnt` hookup resets to 0  
  → `tick` period is `(prescale + 1)` cycles.
- **Pattern B:** `tick` when `cnt == prescale - 1`  
  → `tick` period is `prescale` cycles (requires `prescale >= 1`).

✅ Your tests and FSM timing must follow whichever convention your RTL implements.

## Reset behavior
On `!rst_n`:
- `cnt` resets (typically to 0)
- `tick` deasserted (0)

## Integration notes
- Most protocol bricks set `enable = busy` so time only advances while the operation is active.
- If you allow `prescale` to change while enabled, you must define whether the new value takes effect immediately or after returning to idle; otherwise tests become timing-fragile.

## Testbench implications
- Prefer to **wait for `tick`** rather than fixed cycle counts.
- If you change `prescale`, do it only while `enable=0` unless you intentionally test dynamic reprogramming.

## Formal hooks (suggested)
- Pulse width: `tick |-> ##1 !tick`
- Bounded liveness: if `enable=1` and `prescale` stable, `tick` occurs within a finite bound
- `cnt` monotonic modulo reset behavior while enabled (as implemented)
