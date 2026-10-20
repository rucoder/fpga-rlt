# AGENTS.md — guide for AI assistants working in this repo

## What this repo is

A personal SystemVerilog learning project: an I²C master built from small,
individually tested and formally verified "bricks" (`tick_div`, `sync_2ff`,
`i2c_od_pads`, `i2c_bit_prim`, `i2c_scl_req`). Not production code. The owner
is learning — methodology and clarity matter more than feature count.

## Environment (set up before any make/sim/formal work)

- Owner's shell is fish; keep scripts bash-compatible too.
- `source ./env-setup` (bash) or `source ./env-setup.fish` (fish) — git-ignored,
  templates in `env-setup.example`. Puts OSS CAD tools + Verilator on PATH.
- Python for cocotb: `.venv` (create with `make venv-setup`, then
  `source .venv/bin/activate`).
- Sanity check: `make env-check`.

## Commands

| Task | Command |
|------|---------|
| Lint all | `make lint` |
| Regenerate filelists (after adding/removing HDL files) | `make lint-lists` |
| SV testbench sim | `make sim-<module>` |
| cocotb sim | `make sim-coco-<module>` |
| Formal proof | `make sby-<module>` |
| Most sims + proofs (see Makefile `all:` for current exclusions) | `make all` |
| Rebuild tools from source | `make build-toolchain` (or single: `build-verilator`, `build-yosys`, `build-sby`, `build-z3`) |

## Naming conventions (build system auto-discovers by these patterns)

- RTL: `rtl/<module>.sv`, module name == filename, snake_case.
- Testbench: `sim/<module>/tb_<module>.sv`.
- cocotb test: `sim/<module>/test_<module>.py`.
- Formal: `formal/<module>/<module>_formal_top.sv` + `<module>.sby`.
- Waivers: `sim/<module>/<module>.vlt`, `formal/<module>/<module>.vlt`.
- Make targets use hyphens (`sim-tick-div`); module names use underscores.
- Formal harnesses: do NOT use `bind` (removed from Yosys's OSS frontend in 0.70) — instantiate checker modules directly in the formal top (see `formal/tick_div/`).

## Lint and waiver policy

New Verilator warnings are appended **commented** by `make generate-waivers`.
To activate a waiver, uncomment it and write why next to it — or better, fix
the RTL. Never blanket-suppress warnings.

## Toolchain pins (do not change without asking the owner)

- Verilator exactly **5.052**. 5.044 crashed reproducibly on this repo —
  never suggest it.
- Yosys/SBY ≥ **0.70**, Z3 ≥ **5.0**. Rebuilds: `tools/mk/toolchain.mk`
  (bump the version variable, rerun the target).

## Documentation map

`docs/README.md` is the index: `guides/` (how infra works), `design/`
(per-module design intent), `notes/` (learning notes), `ROADMAP.md`
(backlog), `reviews/` (dated project reviews).

## Guardrails

- The owner may have uncommitted work — never revert or "clean up" their changes without asking.
- Don't modify `docs/superpowers/` (specs/plans) unless working on them.
- Conventional commits: `feat:`, `fix:`, `docs:`, `test:`, `build:`.
- `make all` is not literally "everything": currently excluded is `sby-i2c-bit-prim` (bind removal; see docs/ROADMAP.md). The Makefile `all:` comments are authoritative.
