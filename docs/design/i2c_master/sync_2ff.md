# `sync_2ff` — 2-Flip-Flop Synchronizer

## Purpose
Bring a **single-bit asynchronous** input into the local clock domain with reduced metastability risk.

This is the standard 2FF CDC (clock domain crossing) synchronizer.

## Interface
- Inputs
  - `clk`
  - `rst_n` (active-low reset)
  - `async_in` — may toggle at any time relative to `clk`
- Output
  - `sync_out` — synchronized version of `async_in` in `clk` domain

## Contract

### Assumptions
- `async_in` can change at any time.
- This module is for **single-bit level** signals or pulses that are wide enough to be sampled.

### Guarantees
- `sync_out` changes **only on `posedge clk`** (after reset released).
- Latency: typically **~2 clock cycles** from an `async_in` change to `sync_out` reflecting it.
- A pulse on `async_in` that is captured by FF1 will appear at `sync_out` for **at least one full clock cycle** (delayed).

### What it does NOT guarantee
- It does not guarantee a very narrow pulse will be captured. (If the pulse does not overlap a sampling edge, it is missed.)
- It does not provide a multi-bit CDC protocol or guarantee of coherence across multiple signals.

## Reset behavior
On `!rst_n`, outputs reset to a known value (often `0`).
For I²C pad synchronizers, 0 is fine because it is an internal representation, not the actual bus level.

## Testbench implications
If your TB drives the **asynchronous** side (e.g. SCL/SDA wires) and observes the **synchronized** side:
- Expect **~2 clocks of delay** between changing the wire and seeing `*_sync` reflect it.
- This is not an I²C timing rule — it’s a CDC modeling effect.

## Formal hooks (suggested)
- `sync_out` only changes on `posedge clk` (except reset).
- Structure check: ensure there are two flops in series (often easiest by inspection + simple properties).
