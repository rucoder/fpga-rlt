# Design: Toolchain Update, Docs Restructure, Methodology Review

Date: 2026-10-19
Branch: `coco-bit-prim` (work happens here; WIP changes stay untouched)
Status: approved in brainstorming session

## Context

The repo is a SystemVerilog learning project (I²C master built from small proven
bricks). It works, but:

- Verilator is pinned at 5.036–5.042 (installed: self-built 5.042 at
  `~/kicad/projects/fpga/tools/verilator`) while upstream is at 5.052.
  Verilator 5.044 crashed reproducibly on this setup — no research needed,
  just skip it.
- The formal stack is also behind: Yosys 0.61+56 / SBY 0.61 (self-built in
  `~/.local/oss-cad`) vs upstream v0.70 (Oct 2026); Z3 4.15.4 (dnf) vs
  upstream 5.3.1 (major-version bump, released 2026-10-15). Owner wants
  everything at latest ("latest and greatest").
- The one-off build commands should become reusable `make` targets so future
  upgrades are "bump a version variable, rerun" (owner request).
- `docs/` is a flat pile mixing guides, learning notes, and two drifting TODO
  lists; `docs/design/` and `.zed/` are untracked.
- There are no AI-assistant markdown files (AGENTS.md/CLAUDE.md).
- The owner is migrating from an "AI agent in IDE" workflow to Claude CLI.

## Goals

1. Update the whole toolchain to latest — Verilator 5.052, Yosys/SBY 0.70,
   Z3 5.3.1 — via reusable Makefile targets, and update the version pins
   that guard them.
2. Restructure docs by purpose and add standard AI-assistant files.
3. A methodology-focused review: "how to correctly structure, write, lint,
   simulate" — **not** an RTL bug hunt. This is a learning repo; RTL bugs are
   expected and are the learner's material, not defects to flag.

## Part 1 — Toolchain update

All four tools are rebuilt/updated from source (dnf packages are too old for
Z3 5.3.1 and the Verilator pin). The builds are wrapped as reusable make
targets in a new `tools/mk/toolchain.mk` — future upgrades become "bump the
version variable, rerun the target". Build order matters only for
Yosys→SBY (SBY installs into the same prefix); the rest are independent.

1. **New file `tools/mk/toolchain.mk`** (included from the main Makefile,
   wired into `help.mk`):
   - Version variables at top: `VERILATOR_VERSION=5.052`,
     `YOSYS_VERSION=0.70`, `SBY_VERSION=0.70`, `Z3_VERSION=5.3.1`.
   - Prefix variables matching existing layout: Verilator →
     `~/kicad/projects/fpga/tools/verilator`; Yosys/SBY/Z3 → `~/.local/oss-cad`;
     source checkouts under `~/kicad/projects/fpga/tools/src/`.
   - Targets: `toolchain-check-deps`, `build-verilator`, `build-yosys`,
     `build-sby`, `build-z3`, `build-toolchain` (all four, Yosys before SBY).
   - Old Verilator install moved aside to `verilator.bak` before install
     (kept until verification passes).
2. Verilator `v5.052`: git clone, `autoconf && ./configure --prefix=… &&
   make -j && make install`.
3. Yosys `v0.70`: git clone `--recurse-submodules --branch v0.70`, then
   CMake flow (`cmake -B build -DCMAKE_BUILD_TYPE=Release
   -DCMAKE_INSTALL_PREFIX=…`, build, install). Requires CMake ≥3.28,
   C++20 compiler, bison ≥3.8, flex, python ≥3.11 — all satisfied on this
   Fedora 42 box.
4. SBY `v0.70` (release matching Yosys): git clone `--branch v0.70`,
   `make install PREFIX=~/.local/oss-cad`.
5. Z3 `5.3.1` (tag `z3-5.3.1`): release tarball, CMake build+install into
   the OSSCAD prefix so it shadows the older dnf z3 (4.15.4) when env-setup
   is sourced.
6. `tools/mk/environment.mk`:
   - Verilator: accepted range `5.036–5.042` → exactly `5.052`; remove the
     "5.044 is buggy" warning, replace with a one-line note that 5.044
     crashed on this repo and is skipped.
   - Yosys/SBY floor: `≥0.40` → `≥0.70` (keep floor semantics — git builds
     report versions like `0.70+123`).
   - Z3 floor: `≥4.8` → `≥5.0`.
7. README: update all version claims (env-check description, manual
   verification section, tool install notes) to match.

**Contingency:** Z3 5.x is weeks old. If the sby proofs fail in ways that
point at z3 (yosys-smtbmc errors, not design counterexamples), fall back to
Z3 4.15.x from source in the same prefix, record why in ROADMAP, and keep
everything else at latest. Boolector (already at
`~/kicad/projects/fpga/tools/boolector`) is the alternate solver if a
specific proof needs it.

### Verification

The working tree has uncommitted WIP (`rtl/i2c_bit_prim.sv`,
`sim/i2c_bit_prim/test_i2c_bit_prim.py`). To keep "tool update broke X"
separate from "WIP is broken":

- Verify in a clean `git worktree` at HEAD: `make env-check`, `make lint`,
  `make all`, `make sby-tick-div sby-sync-2ff`. These exercise the full new
  stack: Verilator for lint/sim, Yosys+SBY+Z3 for the formal proofs (this is
  where a Z3 5.x incompatibility would surface — see contingency above).
- Separately, in the real working tree, run the WIP cocotb test under the
  new stack and report its status as review input. No edits to WIP files.

If new-tool versions surface *new* lint warnings or proof behavior vs the
old stack: record as review findings; waive or fix only through the
documented waiver process, no blanket suppression.

## Part 2 — Docs restructure

### Moves (git mv, history preserved)

| From | To |
|------|-----|
| `docs/LINTER.md` | `docs/guides/LINTER.md` |
| `docs/COCOTB.md` | `docs/guides/COCOTB.md` |
| `docs/BRICK-5-SINGLE-BIT.md` | `docs/notes/BRICK-5-SINGLE-BIT.md` |
| `docs/FORMAL-VERIFICATION-STRATEGY.md` | `docs/notes/FORMAL-VERIFICATION-STRATEGY.md` |
| `docs/TOOLS-TODO.md` + `docs/COCOTB-TODO.md` | merged into `docs/ROADMAP.md` (then deleted) |
| `docs/design/i2c_master/*` | unchanged; **committed** (currently untracked) |
| `.zed/settings.json` | unchanged; **committed** (currently untracked) |

### New files

- `docs/README.md` — index: one line per document, what it's for.
- `AGENTS.md` — the AI contract, distilled from README: environment setup
  (env-setup must be sourced, fish-first), make targets, module auto-discovery
  naming conventions, lint/waiver workflow, docs map, guardrails (don't touch
  WIP or the Verilator pin without asking).
- `CLAUDE.md` — thin pointer: "Read AGENTS.md — it applies to this repo."
- `README.md` — links updated to new paths; Documentation section points at
  `docs/README.md`.

### ROADMAP.md merge

TOOLS-TODO's six numbered items, COCOTB-TODO's notes (distilled — the raw
cocotb Makefile-variable dump becomes part of the cocotb item, not copied
wholesale), and FORMAL-VERIFICATION-STRATEGY's TODO (formal top for
`i2c_bit_prim`, bounded liveness check) become one prioritized checkbox list.

## Part 3 — Methodology review

Deliverable: `docs/reviews/2026-10-19-project-review.md`.

Focus — how the craft is done, not whether the I²C works:

- **Project/file structure**: layout, naming conventions, auto-discovery
  patterns, whether the bricks decomposition serves learning.
- **SV writing methodology**: idiomatic use of constructs, timescale/lint
  directives, pragma/waiver discipline, reset conventions consistency.
- **Simulation setup**: Verilator flags, cocotb Makefile variable usage
  (vs. what cocotb actually supports), FST tracing setup, testbench
  structure.
- **Lint/formal workflow**: waiver hygiene, sby script idioms, whether the
  formal strategy matches stated goals in `docs/notes/`.
- **AI-readiness**: does the post-restructure repo give an assistant what it
  needs (AGENTS.md quality, discoverability).

Findings tagged: `structure` / `methodology` / `workflow` / `nice-to-have`,
each citing `file:line`. RTL protocol-correctness observations only if they
teach a methodology lesson. No fixes applied this session.

## Out of scope

- Finishing the WIP branch (the "specification mismatch" stays open).
- Implementing any ROADMAP item (svlint, cocotb monitor, sby cover, …).
- Any RTL change.

## Success criteria

- `make env-check` passes with the new pins (Verilator 5.052, Yosys/SBY
  ≥0.70, Z3 ≥5.0 — or the documented Z3 fallback).
- `tools/mk/toolchain.mk` exists; `make build-verilator` / `build-yosys` /
  `build-sby` / `build-z3` / `build-toolchain` rebuild each component from
  the pinned versions.
- Clean worktree at HEAD: lint + all sims + existing formal proofs pass
  under the new stack (or new-tool findings are documented in the review).
- WIP files byte-identical before/after the session.
- New docs structure in place, all links resolve, untracked design docs and
  `.zed/` committed.
- Review doc exists with methodology findings.
