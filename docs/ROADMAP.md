# Roadmap

Prioritized backlog. Nothing here blocks anything; check items off as done.

## Toolchain

- [x] Reusable source-build make targets (`tools/mk/toolchain.mk`) — added 2026-10-19
- [ ] Second-opinion lint/analysis front-end: evaluate **slang** (compiler/elaborator + lint) and/or **Verible** (formatter + style linter + LSP) and/or **svlint** — catch "compiles but not what I meant" classes: implicit nets, width mismatches, incomplete case, blocking/nonblocking misuse, unintended signed math
- [ ] Build glue (**Edalize** / **FuseSoC**) — only if the Makefile grows into its own project
- [ ] Harden `toolchain.mk` further: waiver `.vlt -match` strings embed Verilator message text (a rewording silently deactivates them — fails loud at next lint, but still); consider `-lint-off` pragma placement instead

## Cocotb testbenches

- [ ] I²C **monitor + scoreboard**: print START/STOP, addr+R/W, each byte, ACK/NACK, timestamps — "logic-analyzer style" output instead of bit-staring at waves (~30 lines with cocotbext-i2c building blocks)
- [ ] Gate the legacy SV testbench `$finish` on cocotb presence (the `+cocotb` plusarg / `$test$plusargs` idea from the old COCOTB-TODO) so one testbench serves both flows — note: `sim/cocotb.mk` currently passes `+define+COCOTB_SIM` instead; unify on one mechanism
- [ ] Use cocotb's `regression` target semantics for dependency-aware re-runs
- [ ] Fix cocotb dependency tracking: sources passed via `-f build/lint/lint_*.f` make the model silently stale across RTL edits (make can't see through filelists). Either list `VERILOG_SOURCES` directly in `sim/cocotb.mk` or force `SIM_BUILD` rebuild when lint filelists regenerate
- [x] Migrate to cocotb 2.1.x — done 2026-10-20. The apparent 2.1 "regressions" were testbench races all along: posedge-aligned one-edge pulses, missing idle-waits between ops, and a test-to-test state leak. Suite 5/5 deterministic; the SV tb passes end-to-end
- [ ] README "Current Modules" table: replace per-column ✓/- with a status column that can say "harness exists, excluded from `all`: reason" (docs/reviews/2026-10-19 WF-1)

## Formal verification

- [ ] `i2c_bit_prim`: bounded liveness — assume "if `want_scl_high` stays 1, `scl_sync` becomes 1 within N ticks", then prove "done within M ticks" (from `notes/FORMAL-VERIFICATION-STRATEGY.md`)
- [ ] SBY `cover` mode for trace generation: "one valid IDLE→START→…→STOP trace", "a trace where ACK=0" — short targeted waves instead of full sims
- [ ] Smaller/focused dumps: trigger-on-fail style FST windowing (FST already default)
- [ ] Re-enable `sby-i2c-bit-prim`: migrate `i2c_bit_prim_props` off `bind` (removed in Yosys 0.70 OSS frontend) — needs FORMAL-gated debug outputs on the DUT for internal signals (`st`, `tick`, `tx_bit_q`, …), coordinated with the in-flight DUT refactor on this branch

## Hardware bring-up (later)

- [ ] sigrok/PulseView + built-in I²C decoder for logic-analyzer day
