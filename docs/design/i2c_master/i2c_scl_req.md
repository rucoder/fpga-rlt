# `i2c_scl_req` — Stretch-aware SCL Request Helper

## Purpose
Convert an internal intent **“I want SCL high/low”** into an open-drain control `scl_pull`, while providing a synchronized observation `scl_high_ok` that accounts for **clock stretching**.

This block does **not** generate I²C timing by itself. It is a helper used by higher-level FSMs.

## Interface
- Inputs
  - `clk`, `rst_n`
  - `want_scl_high` — 1 means “release SCL, allow it to rise”; 0 means “force SCL low”
  - `scl_sync` — synchronized observation of the SCL wire (from pads/synchronizer)
- Outputs
  - `scl_pull` — open-drain control: 1 pulls low, 0 releases
  - `scl_high_ok` — indicates SCL is observed high (no stretch)

## Contract

### Assumptions
- `scl_sync` is **already synchronized** to `clk` (e.g. via `sync_2ff` / `i2c_od_pads`).
- Bus is open-drain: pulling low dominates; releasing allows pull-up to raise the line.
- External slave may hold SCL low (stretching).

### Guarantees
- Drive mapping:
  - If `want_scl_high=0` → `scl_pull=1` (force low)
  - If `want_scl_high=1` → `scl_pull=0` (release)
- Observation:
  - `scl_high_ok` asserts when SCL is observed high in the local clock domain (often mirrors `scl_sync`).

### What it does NOT guarantee
- Releasing SCL does not guarantee it becomes high (slave may stretch indefinitely).
- It does not provide a timeout. Timeouts belong in the higher-level controller if needed.

## Reset / safe defaults
- Safe default for I²C is to **release** SCL (`scl_pull=0`). This is achieved by the caller setting `want_scl_high=1` in IDLE.

## Testbench implications
To test stretching:
- Drive the SCL wire low via the slave model while master releases it.
- If pads/synchronizer are present, `scl_sync` may lag the wire by ~2 clocks.

## Formal hooks (suggested)
- Mapping property: `assert(scl_pull == ~want_scl_high)` (given your naming).
- If `want_scl_high==0`, then `scl_pull==1` always (pure combinational/registered mapping depending on implementation).
