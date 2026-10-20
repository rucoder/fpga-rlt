# Project Review — 2026-10-19

Scope: methodology (structure, directives, lint/sim/formal workflow, AI-readiness).
Explicitly out of scope: I²C protocol correctness — this is a learning repo; RTL bugs are the learner's material. Protocol observations appear only where they teach a methodology lesson.
Toolchain at review time: Verilator 5.052, Yosys/SBY 0.70, Z3 5.3.1.

## Verification status under the new toolchain

From the Task 4 clean-worktree verification (reports in `.superpowers/sdd/task-4-*.md`):

- First contact with the new stack was **all-red**: 7/7 lint tops failed, with warning classes new vs 5.042 promoted to errors under `-Wall` — PROCASSINIT, SYNCASYNCNET, MULTIDRIVEN, UNUUSEDSIGNAL — and both proofs failed in the Yosys front-end read phase (`syntax error, unexpected TOK_ID` on every `bind`).
- After migration: `make lint` 7/7 PASS; `make all` green (sim-tick-div, sim-sync-2ff, sim-i2c-od-pads, sby-tick-div, sby-sync-2ff). Both proofs non-vacuous by `$check`-cell count: tick_div 12, sync_2ff 4.
- `sim-i2c-bit-prim` and `sby-i2c-bit-prim` are excluded from `all` with written reasons (Makefile:119-124).
- WIP cocotb (`make sim-coco-i2c-bit-prim`, WIP RTL from commit ea2b3ae): 2/5 pass. READ-path tests time out waiting for `done` (>20000 cycles); `handshake_invariants` sees `busy` still high at/after `done` on WRITE. Classified as a genuine RTL/spec mismatch (the open `done`-semantics decision: sample-point pulse vs fully-idle), not infrastructure — it reproduces identically under 5.042 and 5.052.

All findings below are tagged `structure` / `methodology` / `workflow` / `nice-to-have`. No fixes were applied in this session; this document is the deliverable.

## Structure findings

### ST-1 — Waveform artifacts dumped at the repo root (`structure`)

Five `*.fst` files, one `dump.fst`, and four `*.surf.ron` files sit at the repo root (README.md:150 even documents `.surf.ron` files as living "in the repo"). Everything generated belongs under `build/`, which already exists and is make-cleaned (Makefile:108-110):

- Root clutter: `tb_tick_div.fst`, `tb_sync_2ff.fst`, `tb_i2c_od_pads.fst`, `tb_i2c_bit_prim.fst`, `dump.fst`, plus matching `*.surf.ron`.
- Cause: testbenches call `$dumpfile("tb_<module>.fst")` with a relative path (e.g. `sim/i2c_bit_prim/tb_i2c_bit_prim.sv:75`, and equivalents in the other tbs), and sims are invoked from the repo root. `dump.fst` is an orphan from some ad-hoc run.

Recommendation: `$dumpfile("build/sim/<module>.fst")` (with an `mkdir` or Verilator `--dump-dir`-style handling), keep `.surf.ron` beside the waves, and gitignore `*.fst` defensively. README's "Project Structure" section already claims `build/` is where generated output goes — the code should honor the doc.

### ST-2 — Two cocotb-gating mechanisms designed, only one landed (`structure`)

Implemented: compile-time `` `ifndef COCOTB_SIM `` blocks in `sim/i2c_bit_prim/tb_i2c_bit_prim.sv:74,92`, driven by `+define+COCOTB_SIM` from `sim/cocotb.mk:40`. Planned but never landed: a runtime `$test$plusargs("cocotb")` gate (the old `docs/COCOTB-TODO.md` plan; that doc has since been relocated during the docs restructure, and no `plusargs` exists anywhere in `sim/` or `rtl/` today).

As implemented the mechanism is self-consistent, so this is not a bug — but the repo currently has one module gated by define and a documented intent to use a different (runtime) mechanism. Pick one. The define-based gate is the better choice (zero simulator-arg coupling, dead-code elimination of standalone stimulus), so the recommendation is: declare it the pattern in AGENTS.md/docs and delete the plusargs idea.

### ST-3 — Purely combinational brick carries clock/reset ports (`structure`)

`rtl/i2c_scl_req.sv:2-3` declares `clk`/`rst_n` that the module never uses — it is two `assign` statements (lines 22-26). This costs two permanent UNUSEDSIGNAL waivers (`sim/i2c_scl_req/i2c_scl_req.vlt`, `sim/i2c_bit_prim/i2c_bit_prim.vlt` — the same waiver appears in two files) and, more importantly, blurs the bricks decomposition: a brick's port list is its contract, and a combinational brick advertising a clock invites consumers to assume statefulness. If the ports exist for a future synchronous version, say so in a header comment; otherwise drop them when the brick is next touched.

### ST-4 — Formal lint exclusions lack recorded rationale (`structure`)

`lint_config.yml` excludes `i2c_bit_prim_formal_top` and `i2c_scl_req_formal_top` from linting entirely. Unlike the `.vlt` waivers (which carry reason comments), these exclusions have no explanation of what they hide or why. The waiver discipline elsewhere in this repo is exactly the model to copy: one line of "why" next to each exclusion, or convert them to targeted waivers. (The README's Linting section, README.md:326-336, presents exclusion as the general mechanism without noting waivers are preferred.)

## Methodology findings

### ME-1 — Verilator flag sets duplicated and diverging between the two sim paths (`methodology`)

`Makefile:20-24` (`VERILATOR_OPTS_COMMON`: `--Wall --timing --trace-fst -cc -sv -exe --binary --build -O3 ... -Wno-TIMESCALEMOD`) and `sim/cocotb.mk:34-40` (`-f <lint filelist> --trace --trace-fst --trace-structs --timing +define+COCOTB_SIM`) are two hand-maintained, non-overlapping flag sets for building the same DUTs. Consequences already observed: cocotb builds don't get `-Wall` (lint warnings invisible in the cocotb path), don't get `-Wno-TIMESCALEMOD`, and do get `--trace-structs` that the standalone path lacks. Factor the common core into one variable/include so a flag decision (e.g. a new waiver, a trace toggle) lands in both paths or deliberately in exactly one.

### ME-2 — cocotb + `-f filelist` breaks make dependency tracking → silently stale models (`methodology`)

The hardest-won lesson of this session. `sim/cocotb.mk:34` feeds Verilator via `-f build/lint/lint_<TOP>.f`; make sees only the `.f` file's mtime, not the `.sv` files it lists. Result (Task 5 report): a cocotb run silently executed a 5.042-era model built from pre-WIP RTL — the banner said "Verilator 5.042" on a machine whose only Verilator was 5.052 — with no warning, and the SIM_BUILD was only refreshed after `rm -rf build/sim/tb_i2c_bit_prim`. For a verification repo, a sim that can lie about which RTL it ran is the worst failure mode possible. Mitigations: list `VERILOG_SOURCES` directly in cocotb.mk so make tracks them, or force-regenerate SIM_BUILD whenever the lint lists change. (Already a ROADMAP item — keep it there, prominently.)

General lesson: any indirection in build inputs (filelists, generated headers) needs an explicit staleness story, and simulator banners should be checked against expected tool versions as a cheap tripwire.

### ME-3 — Timescale handled by waiver instead of by rule (`methodology`)

`Makefile:24` waives TIMESCALEMOD globally, while the testbenches are inconsistent: `sim/tick_div/tb_tick_div.sv:1`, `tb_sync_2ff.sv:1`, `tb_i2c_od_pads.sv:1`, `tb_i2c_scl_req.sv:1` all carry `` `timescale 1ns / 1ps `` — but `sim/i2c_bit_prim/tb_i2c_bit_prim.sv:1` has it commented out. The waiver is doing the work a one-line convention could do. Either every tb declares a timescale and the waiver is deleted (preferred — the waiver also mutes the warning for future files that genuinely mismatch), or no tb declares one and the waiver is documented as such. Half-and-half is how the waiver became permanent.

### ME-4 — Formal-harness init discipline is a lesson worth writing down (`methodology`, positive lesson)

Two facts from this session that belong in the formal guides:

1. **Unconstrained initial state produces step-1 counterexamples.** The sync_2ff proof CEX'd immediately until the harness gained `initial past_valid = 1'b0;` (`formal/sync_2ff/sync_2ff_formal_top.sv`, added in commit f0eb06f). `$past`-based assumptions are vacuous in cycle 0 unless the harness explicitly initializes the guard. This is now done consistently in both harnesses — good — but the *reason* lives only in git history.
2. **Proof liveness must be checked, not assumed.** Under Yosys 0.61 the tick_div proof was VACUOUS — `bind` was silently dropped, 0 `$check` cells — while sync_2ff and i2c_bit_prim binds were live. Under 0.70 the same bind is a loud parse error (removed in commit fbd7c249e). Silent vacuity is strictly worse than a crash. The `select -count t:$check` check (note: `$assert` no longer exists as a cell type in modern Yosys — everything is `$check`) should be a standing step of every proof run, or scripted into the sby wrapper.

Both are captured in `docs/guides/` and AGENTS.md's "do NOT use bind" line to varying degrees; making the `$check`-count check a routine would complete it.

### ME-5 — Waiver match strings embed Verilator message text (`methodology`)

The `.vlt` waivers match on full message text, including Verilator's parenthetical citations, e.g. `formal/sync_2ff/sync_2ff.vlt`: `-match "Variable written to in always_ff also written by other process (IEEE 1800-2023 9.2.2.4): 'past_valid'*"`. Any Verilator release that rewords a message or updates the IEEE reference silently un-waives the warning → lint goes red on the next toolchain bump (this cost time during the 5.042→5.052 migration). Prefer `-rule X -file "..."` without `-match`, or match on the minimal stable fragment (the signal name), keeping the human explanation in the comment.

### ME-6 — Toolchain build recipes are version-portable only within one build-system era (`methodology`)

`tools/mk/toolchain.mk:69-87` builds Yosys exclusively via the CMake flow, which only exists for Yosys ≥ ~0.62. Building 0.61 (needed during the bind investigation to compare front-ends) required falling back to the old Makefile flow with `ENABLE_ABC=0`. Since the whole point of `*_VERSION ?=` variables is "bump and rerun", the recipe should either detect the absence of `CMakeLists.txt` and switch to the Makefile flow, or document the supported floor next to `YOSYS_VERSION`. Related minors from the ledger: the download pipeline (`curl | tar`) lacks `--fail`/pipefail, so a silent 404 yields an empty tarball that exits 0 (the CMake guard recovers on rerun, but the failure is quiet); version comparisons mix `10#`-guarded and bare arithmetic.

## Workflow findings

### WF-1 — README module table has drifted from reality, twice (`workflow`)

`README.md:366-372` shows Formal = `-` for `i2c_bit_prim` and `i2c_scl_req`, but `formal/i2c_bit_prim/` (top, props, `.sby`) and `formal/i2c_scl_req/` (top, `.sby`) both exist. The drift is now compounded by the `all:` exclusions (Makefile:119-124): the table's ✅/`-` alphabet can no longer express "formal harness exists, proof currently excluded and why". Suggested columns: RTL / TB / cocotb / Formal (one of: `prove ✅`, `harness only (excluded: reason)`, `-`). A verification-status table that a reader can't trust is worse than no table — this is the single highest-value doc fix pending.

### WF-2 — `all` exclusions are documented at the code but not at the status surface (`workflow`)

The exclusion reasons in `Makefile:119-124` are exactly right (what, why, pointer to commit ea2b3ae and docs/ROADMAP.md). But `make all` green now silently means "3 sims + 2 proofs, two known-absent targets", and neither `README.md:300` (`make all  # Run all simulations`) nor the module table says so. Wherever green/red status is summarized (README table, ROADMAP), the exclusions should travel with it.

### WF-3 — Known-failures list is missing for humans and AI assistants (`workflow`)

Current expected-failure state: cocotb i2c_bit_prim 2/5 (READ-path `done` timeout, open spec decision), sim-i2c-bit-prim hang (same root cause), sby-i2c-bit-prim excluded (bind/Yosys 0.70). This is discoverable only by reading Makefile comments, commit ea2b3ae, and the SDD reports. AGENTS.md is otherwise an excellent assistant brief — add a short "known failures / expected red" section so a fresh assistant (or the owner in three months) doesn't re-diagnose the READ timeout from scratch. The underlying spec decision (`done` as 1-cycle sample-point pulse vs fully-idle signal) should be written down wherever it gets decided, because two testbenches and one proof hinge on it.

Established anatomy of the sim-i2c-bit-prim hang — record it verbatim in the known-failures list: `sim/i2c_bit_prim/tb_i2c_bit_prim.sv` hangs at its FIRST READ `wait (done)` (line 128); the two WRITE waits before it (lines 99, 105) complete. Root cause is the DUT's READ path never asserting `done` — the same signature as the cocotb `read_correctness_no_stretch` >20000-cycle timeout (`sim/i2c_bit_prim/test_i2c_bit_prim.py:79`): two independent witnesses, one bug. The METHODOLOGY lesson is in how each testbench fails: the SV testbench has no watchdog — bare `wait (done)` + a never-reached `$finish` (tb_i2c_bit_prim.sv:141) + a free-running clock (`always #5 clk = ~clk`, line 7) = an infinite hang silently burning host CPU, which is why the target is excluded from `all` rather than merely red. cocotb's `wait_done_pulse` times out at 20000 cycles and fails gracefully with a diagnosable message. Standalone testbenches need the same safety: a max-cycle watchdog (fork/join_any, or an initial-block cycle counter that `$fatal`s) so an unmet expectation becomes a named failure instead of a hang.

## Nice-to-haves

- **NT-1**: `rtl/tick_div.sv:36-37` — the `unused_zero` dummy-concatenation trick to sink unused bits is clever but opaque; a one-line comment (or an inline `unused` lint waiver) would teach the pattern instead of puzzling the reader. (`nice-to-have`)
- **NT-2**: `sim/cocotb.mk:32` prints `$(info PYTHONPATH=...)` on every invocation — demote to a `V=1`-style debug echo. (`nice-to-have`)
- **NT-3**: `compile_commands.json` and `veridian.yml` at the root are fine, but the README "Project Structure" tree (README.md:213-232) doesn't mention them, nor `env-setup*`, `AGENTS.md`, `CLAUDE.md`. A one-line "root files" note would complete the map. (`nice-to-have`)

## What's already good

Deserving of explicit praise:

- **The bricks decomposition.** Five small modules, each with its own `rtl/` + `sim/` + `formal/` triple, auto-discovered by naming convention (`rtl/tick_div.sv` → `make sim-tick-div` / `make sby-tick-div`). This is why the toolchain bump was survivable at all: each proof and waiver is scoped to one brick, so breakage localized instead of compounding.
- **The waiver discipline — and it actually worked under fire.** Waivers are generated commented (`Makefile:100-106`), must be uncommented with a written reason to activate, and carry those reasons (`formal/tick_div/tick_div.vlt`: "inherent formal reset-gen pattern", "inherent to harness — rst_n is async-reset in DUT..."). During the 5.042→5.052 migration this is precisely what let the owner distinguish real new problems (PROCASSINIT — fixed in RTL with the clean `logic clk; initial clk = 0;` idiom) from harness-inherent noise (SYNCASYNCNET/MULTIDRIVEN — waived with reasons). Most professional repos don't have this.
- **The formal strategy documentation.** The Yosys bind investigation (`.superpowers/sdd/yosys-bind-investigation.md`) is a model learning artifact: repro matrix, culprit commit identified (fbd7c249e, first release v0.70), fix options with the dead ends marked DEAD, and a recommendation that was then verified end-to-end with non-vacuity counts. The `mode prove` + k-induction choices and the documented `--nopresat` solver workaround in `formal/tick_div/tick_div.sby` show real understanding, not cargo-culting.
- **Honest exclusion comments.** `Makefile:119-124` states exactly what is excluded from `all` and why, with pointers. Commit ea2b3ae similarly records WIP with an honest status ("READ still times out") rather than a hopeful message.
- **AGENTS.md as an assistant brief.** Environment, commands, naming conventions, the bind prohibition, toolchain pins with the 5.044-crash warning, and owner guardrails ("never revert uncommitted work without asking") — this is more AI-ready than most commercial repos.

## Appendix — accumulated minors (from the session ledger)

Folded in from `.superpowers/sdd/progress.md` for the record, all `nice-to-have` severity:

1. `curl | tar` in `tools/mk/toolchain.mk` lacks `--fail`/pipefail → silent 404 (covered in ME-6).
2. Waiver strings embedding message text (covered in ME-5).
3. Empty-version-string `10#` arithmetic edge; `VERILATOR_MAJOR` compared without `10#` (cosmetic inconsistency in version checks).
4. An early fix-report quoted evidence paraphrased rather than verbatim — a reporting-hygiene reminder for future verification records: paste banners verbatim.
