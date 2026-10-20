# I²C Master — Architecture Draft (Brick-by-brick)

## Goal
Build a robust, verifiable I²C master from small bricks with explicit contracts.

Bricks implemented so far:
- `sync_2ff` — synchronizer
- `tick_div` — pacing tick
- `i2c_scl_req` — stretch-aware SCL control
- `i2c_bit_prim` — one bit transaction

Next bricks (planned):
- `i2c_od_pads` doc (pad layer + CDC)
- `i2c_start_stop` — generate START/STOP conditions
- `i2c_byte` — 8 bits + ACK/NACK using `i2c_bit_prim`
- `i2c_master` — transactions (address, repeated start, multi-byte read/write)

---

## Block interconnect (conceptual)

```mermaid
flowchart LR
  subgraph Pads["Pad/CDC Layer"]
    W_SCL["SCL wire (open-drain)"]
    W_SDA["SDA wire (open-drain)"]
    OD["i2c_od_pads\\n(open-drain drive + sync_2ff x2)"]
    W_SCL --- OD
    W_SDA --- OD
  end

  subgraph Core["Core (clk domain)"]
    TD["tick_div"]
    SCLREQ["i2c_scl_req"]
    BIT["i2c_bit_prim"]
    BYTE["i2c_byte (planned)"]
    SS["i2c_start_stop (planned)"]
    M["i2c_master (planned)"]
  end

  OD -->|scl_sync| SCLREQ
  OD -->|sda_sync| BIT
  OD -->|scl_sync| BIT

  M -->|transaction plan| SS
  M -->|byte/bit commands| BYTE
  BYTE -->|start/op_read/tx_bit| BIT

  BIT -->|sda_pull| OD
  SCLREQ -->|scl_pull| OD
  %% (often BIT contains SCLREQ internally; diagram is conceptual)

  TD -->|tick| BIT
  TD -->|tick| SS
  TD -->|tick| BYTE
