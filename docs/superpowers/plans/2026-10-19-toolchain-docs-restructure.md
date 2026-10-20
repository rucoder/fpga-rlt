# Toolchain Update, Docs Restructure & Methodology Review — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the whole toolchain from source at latest versions via reusable Makefile targets, restructure the docs with AI-assistant files, and deliver a methodology-focused project review.

**Architecture:** New `tools/mk/toolchain.mk` holds version-pinned source-build targets for Verilator/Yosys/SBY/Z3; verification runs in a clean git worktree so uncommitted WIP on `rtl/i2c_bit_prim.sv` stays untouched and unconfounded; docs get reorganized by purpose (guides/notes/design/reviews) with `AGENTS.md` as the AI contract.

**Tech Stack:** GNU Make, git, CMake, autoconf, gcc 15 (Fedora 42), fish + bash.

**Spec:** `docs/superpowers/specs/2026-10-19-toolchain-docs-restructure-design.md`

## Global Constraints

- Verilator pinned to exactly **5.052** (5.044 crashed reproducibly on this repo — never suggest it).
- Yosys/SBY version: **v0.70** (tag format `v0.70`). Z3: **5.3.1** (tag format `z3-5.3.1`).
- Install prefixes: Verilator → `~/kicad/projects/fpga/tools/verilator`; Yosys/SBY/Z3 → `~/.local/oss-cad`; source trees → `~/kicad/projects/fpga/tools/src/`.
- The uncommitted WIP (`rtl/i2c_bit_prim.sv`, `sim/i2c_bit_prim/test_i2c_bit_prim.py`) must be byte-identical when the session ends.
- Do not blanket-suppress lint warnings; waivers need written explanations (existing repo policy).
- Z3 contingency: if proofs fail with yosys-smtbmc/z3 errors (not design counterexamples), rebuild Z3 4.15.x into the same prefix instead and record why in `docs/ROADMAP.md`.
- Conventional commit messages (`feat:`, `build:`, `docs:`, `test:`), each ending with `Co-Authored-By: Claude <noreply@anthropic.com>`.
- All `git`/`make` commands below run from the repo root `/home/mikem/kicad/projects/fpga/i2c_master` unless stated otherwise. The interactive user shell is fish, but agent shells are bash — use bash syntax, and `source ./env-setup` (not the fish variant).

---

### Task 1: Reusable toolchain build targets (`tools/mk/toolchain.mk`)

**Files:**
- Create: `tools/mk/toolchain.mk`
- Modify: `Makefile:5-8` (add include)
- Modify: `tools/mk/help.mk:27-29` (add Toolchain section)

**Interfaces:**
- Consumes: nothing.
- Produces: make targets `toolchain-check-deps`, `build-verilator`, `build-yosys`, `build-sby`, `build-z3`, `build-toolchain`; version variables `VERILATOR_VERSION=5.052`, `YOSYS_VERSION=0.70`, `SBY_VERSION=0.70`, `Z3_VERSION=5.3.1`. Task 2 runs these targets; Tasks 3/7 reference them in docs.

- [ ] **Step 1: Create `tools/mk/toolchain.mk`**

```make
# tools/mk/toolchain.mk - Rebuild the toolchain from source, pinned versions
#
# Usage:
#   make toolchain-check-deps   # verify build prerequisites
#   make build-verilator        # build + install a single tool
#   make build-yosys
#   make build-sby
#   make build-z3
#   make build-toolchain        # all four, Verilator -> Yosys -> SBY -> Z3
#
# To upgrade a tool later: bump its *_VERSION variable and rerun the target.
# Source trees live in TOOLCHAIN_SRC; installs go to the prefixes that
# env-setup puts on PATH.

# Versions
VERILATOR_VERSION ?= 5.052
YOSYS_VERSION     ?= 0.70
SBY_VERSION       ?= 0.70
Z3_VERSION        ?= 5.3.1

# Locations (must match env-setup / env-setup.fish)
TOOLS_ROOT       ?= $(HOME)/kicad/projects/fpga/tools
VERILATOR_PREFIX ?= $(TOOLS_ROOT)/verilator
OSSCAD_PREFIX    ?= $(HOME)/.local/oss-cad
TOOLCHAIN_SRC    ?= $(TOOLS_ROOT)/src

NPROC := $(shell nproc)

.PHONY: toolchain-check-deps
toolchain-check-deps:
	@for tool in git cmake autoconf make python3 bison flex g++ curl; do \
		if command -v $$tool >/dev/null 2>&1; then \
			echo "✓ $$tool ($$($$tool --version 2>/dev/null | head -n1))"; \
		else \
			echo "✗ $$tool NOT FOUND - install it and retry"; \
			exit 1; \
		fi; \
	done

# ------------ Verilator (autoconf flow) ------------

.PHONY: src-verilator
src-verilator:
	@mkdir -p $(TOOLCHAIN_SRC)
	@if [ ! -d $(TOOLCHAIN_SRC)/verilator-$(VERILATOR_VERSION) ]; then \
		git clone https://github.com/verilator/verilator \
			$(TOOLCHAIN_SRC)/verilator-$(VERILATOR_VERSION); \
	fi
	cd $(TOOLCHAIN_SRC)/verilator-$(VERILATOR_VERSION) && \
		git fetch --tags --force && \
		git checkout v$(VERILATOR_VERSION) && \
		autoconf

.PHONY: build-verilator
build-verilator: toolchain-check-deps src-verilator
	@if [ -d "$(VERILATOR_PREFIX)" ] && [ ! -e "$(VERILATOR_PREFIX).bak" ]; then \
		mv $(VERILATOR_PREFIX) $(VERILATOR_PREFIX).bak; \
		echo "== old install kept at $(VERILATOR_PREFIX).bak =="; \
	fi
	cd $(TOOLCHAIN_SRC)/verilator-$(VERILATOR_VERSION) && \
		./configure --prefix=$(VERILATOR_PREFIX) && \
		make -j$(NPROC) && \
		make install
	@echo "== Verilator installed =="
	$(VERILATOR_PREFIX)/bin/verilator --version

# ------------ Yosys (CMake flow, ABC via submodule) ------------
# Needs: CMake >= 3.28, C++20 compiler (gcc >= 13), bison >= 3.8, flex,
# python >= 3.11.

.PHONY: src-yosys
src-yosys:
	@mkdir -p $(TOOLCHAIN_SRC)
	@if [ ! -d $(TOOLCHAIN_SRC)/yosys-$(YOSYS_VERSION) ]; then \
		git clone --recurse-submodules https://github.com/YosysHQ/yosys \
			$(TOOLCHAIN_SRC)/yosys-$(YOSYS_VERSION); \
	fi
	cd $(TOOLCHAIN_SRC)/yosys-$(YOSYS_VERSION) && \
		git fetch --tags --force && \
		git checkout v$(YOSYS_VERSION) && \
		git submodule update --init --recursive

.PHONY: build-yosys
build-yosys: toolchain-check-deps src-yosys
	cd $(TOOLCHAIN_SRC)/yosys-$(YOSYS_VERSION) && \
		cmake -B build . --fresh \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_INSTALL_PREFIX=$(OSSCAD_PREFIX) && \
		cmake --build build --parallel $(NPROC) && \
		cmake --install build --strip
	@echo "== Yosys installed =="
	$(OSSCAD_PREFIX)/bin/yosys -V

# ------------ SymbiYosys (plain make install) ------------

.PHONY: src-sby
src-sby:
	@mkdir -p $(TOOLCHAIN_SRC)
	@if [ ! -d $(TOOLCHAIN_SRC)/sby-$(SBY_VERSION) ]; then \
		git clone https://github.com/YosysHQ/sby \
			$(TOOLCHAIN_SRC)/sby-$(SBY_VERSION); \
	fi
	cd $(TOOLCHAIN_SRC)/sby-$(SBY_VERSION) && \
		git fetch --tags --force && \
		git checkout v$(SBY_VERSION)

.PHONY: build-sby
build-sby: toolchain-check-deps src-sby
	cd $(TOOLCHAIN_SRC)/sby-$(SBY_VERSION) && \
		make install PREFIX=$(OSSCAD_PREFIX)
	@echo "== SBY installed =="
	$(OSSCAD_PREFIX)/bin/sby --version

# ------------ Z3 (release tarball, CMake flow) ------------

.PHONY: src-z3
src-z3:
	@mkdir -p $(TOOLCHAIN_SRC)
	@if [ ! -d $(TOOLCHAIN_SRC)/z3-$(Z3_VERSION) ]; then \
		curl -L https://github.com/Z3Prover/z3/archive/refs/tags/z3-$(Z3_VERSION).tar.gz \
			| tar xz -C $(TOOLCHAIN_SRC); \
	fi

.PHONY: build-z3
build-z3: toolchain-check-deps src-z3
	cd $(TOOLCHAIN_SRC)/z3-$(Z3_VERSION) && \
		cmake -B build . --fresh \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_INSTALL_PREFIX=$(OSSCAD_PREFIX) && \
		cmake --build build --parallel $(NPROC) && \
		cmake --install build
	@echo "== Z3 installed =="
	$(OSSCAD_PREFIX)/bin/z3 --version

# ------------ All together ------------
# Run without -j: each tool already builds internally with $(NPROC) jobs.

.PHONY: build-toolchain
build-toolchain: build-verilator build-yosys build-sby build-z3
	@echo "== Toolchain build complete =="
	@echo "Verilator: $$($(VERILATOR_PREFIX)/bin/verilator --version)"
	@echo "Yosys:     $$($(OSSCAD_PREFIX)/bin/yosys -V)"
	@echo "SBY:       $$($(OSSCAD_PREFIX)/bin/sby --version)"
	@echo "Z3:        $$($(OSSCAD_PREFIX)/bin/z3 --version)"
```

- [ ] **Step 2: Include it from the main Makefile**

In `Makefile`, after line 6 (`include tools/mk/environment.mk`), the include block becomes:

```make
# Include modular makefiles
include tools/mk/environment.mk
include tools/mk/toolchain.mk
include tools/mk/python.mk
include tools/mk/help.mk
```

- [ ] **Step 3: Add help entries in `tools/mk/help.mk`**

Between the "Setup:" block (line 7-9) and "Simulation:", insert:

```make
	@echo "Toolchain (source builds, see tools/mk/toolchain.mk):"
	@echo "  toolchain-check-deps - Check build prerequisites"
	@echo "  build-toolchain      - Build+install Verilator/Yosys/SBY/Z3 from pinned versions"
	@echo "  build-verilator / build-yosys / build-sby / build-z3 - Single tool"
```

- [ ] **Step 4: Verify make parses the new file**

Run: `make help`
Expected: help text now shows the "Toolchain" section; no syntax errors.

Run: `make toolchain-check-deps`
Expected: nine `✓` lines (git, cmake, autoconf, make, python3, bison, flex, g++, curl). If any `✗`, install it (`sudo dnf install ...`) before Task 2.

- [ ] **Step 5: Commit**

```bash
git add tools/mk/toolchain.mk Makefile tools/mk/help.mk
git commit -m "build: Add reusable source-build targets for Verilator/Yosys/SBY/Z3

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Build and install the new toolchain

**Files:**
- None in-repo (builds run outside the repo; installs go to `~/kicad/projects/fpga/tools/verilator` and `~/.local/oss-cad`).

**Interfaces:**
- Consumes: `build-*` targets from Task 1.
- Produces: Verilator 5.052, Yosys 0.70, SBY v0.70, Z3 5.3.1 on the PATH defined by `env-setup`. Task 3's `env-check` and Tasks 4-5's verification runs depend on these binaries.

**Expect:** 30-60 min total. Run each build as a background task if the harness supports it; they are independent of each other (Yosys→SBY ordering is handled by target prerequisites only in `build-toolchain`; when running individually, run `build-yosys` before `build-sby`).

- [ ] **Step 1: Build Yosys v0.70**

Run: `make build-yosys`
Expected final output:

```
== Yosys installed ==
Yosys 0.70 (or "Yosys 0.70+<n> ...")
```

- [ ] **Step 2: Build SBY v0.70**

Run: `make build-sby`
Expected final output:

```
== SBY installed ==
SBY v0.70
```

- [ ] **Step 3: Build Z3 5.3.1**

Run: `make build-z3`
Expected final output:

```
== Z3 installed ==
Z3 version 5.3.1 - 64 bit
```

- [ ] **Step 4: Build Verilator 5.052**

Run: `make build-verilator`
Expected final output (old 5.042 tree moved to `verilator.bak` first):

```
== old install kept at /home/mikem/kicad/projects/fpga/tools/verilator.bak ==
...
== Verilator installed ==
Verilator 5.052 ... rev v5.052
```

- [ ] **Step 5: Confirm PATH resolution order**

Run: `source ./env-setup && verilator --version && yosys -V && sby --version && z3 --version`
Expected: Verilator 5.052, Yosys 0.70, SBY v0.70, Z3 5.3.1 — all resolving from the prefixes above, not `/usr/bin`.

**Z3 contingency (only if Task 4 later fails proofs with solver errors):** `make build-z3 Z3_VERSION=4.15.4` reinstalls Z3 4.15.4 into the same prefix; record the fallback in `docs/ROADMAP.md` under "Toolchain".

---

### Task 3: Update version pins (`environment.mk` + README claims)

**Files:**
- Modify: `tools/mk/environment.mk:19-65`
- Modify: `README.md:50`, `README.md:54-112` (tool version headers), `README.md:172`, `README.md:292`

**Interfaces:**
- Consumes: installed binaries from Task 2.
- Produces: `make env-check` enforcing Verilator exactly 5.052, Yosys ≥0.70, Z3 ≥5.0. Task 4 relies on env-check passing.

- [ ] **Step 1: Tighten the Verilator check in `environment.mk`**

Replace the block at lines 45-60 (from `if [ "$$VERILATOR_MAJOR" -eq 5 ]` through the `else ... Major version` line) with:

```make
		if [ "$$VERILATOR_MAJOR" -eq 5 ] && [ "$$VERILATOR_MINOR" -eq 52 ]; then \
			echo "  ✓ Version is compatible (5.052)"; \
		elif [ "$$VERILATOR_MAJOR" -eq 5 ] && [ "$$VERILATOR_MINOR" -eq 44 ]; then \
			echo "  ✗ 5.044 crashed reproducibly on this repo - rebuild 5.052: make build-verilator"; \
			exit 1; \
		else \
			echo "  ✗ Unsupported Verilator $$VERILATOR_VERSION - use exactly 5.052 (make build-verilator)"; \
			exit 1; \
		fi; \
```

**Important — leading zeros:** the version vars must be parsed octal-safe. `052` treated as octal ≠ 52, so the check would wrongly reject 5.052. Replace the existing minor extraction (line 44) with:

```make
		VERILATOR_MINOR=$$((10#$$(echo $$VERILATOR_VERSION | cut -d. -f2))); \
```

Also update the not-found message (line 64): `echo "  Please install verilator (version 5.036-5.042)";` → `echo "  Please install verilator 5.052 (make build-verilator)";`

- [ ] **Step 2: Add Yosys/Z3 floor checks in `environment.mk`**

In the yosys block, after the `YOSYS_VERSION=...` line (line 19-20), add:

```make
		YOSYS_MINOR=$$((10#$$(echo $$YOSYS_VERSION | cut -d. -f2 | cut -d+ -f1))); \
		if [ "$$YOSYS_MINOR" -lt 70 ]; then \
			echo "  ✗ Too old (need ≥0.70): make build-yosys"; \
			exit 1; \
		fi; \
```

In the z3 block, after the `Z3_VERSION=...` line (line 30-31), add:

```make
		Z3_MAJOR=$$((10#$$(echo $$Z3_VERSION | cut -d. -f1))); \
		if [ "$$Z3_MAJOR" -lt 5 ]; then \
			echo "  ✗ Too old (need ≥5.0): make build-z3"; \
			exit 1; \
		fi; \
```

And update the not-found hints: `(≥0.40)` → `(≥0.70)`, `(≥4.8)` → `(≥5.0)`.

- [ ] **Step 3: Update README version claims**

- Line 50: `- \`verilator\` is available and version is between 5.036 and 5.042 (5.044 is buggy!)` → `- \`verilator\` is available and version is exactly 5.052 (5.044 crashed reproducibly here — rebuild with \`make build-verilator\`)`
- Line 54: `#### 1. Verilator (≥5.0)` → `#### 1. Verilator (5.052)`
- Line 75: `#### 2. Yosys (≥0.40)` → `#### 2. Yosys (≥0.70)`
- Line 90: `#### 3. SymbiYosys (SBY) (≥0.40)` → `#### 3. SymbiYosys (SBY) (≥0.70)`
- Line 99: `#### 4. Z3 Theorem Prover (≥4.8)` → `#### 4. Z3 Theorem Prover (≥5.0)`
- After line 24 (end of the env-setup bullet list), add: `- Any tool can be rebuilt from pinned source: \`make build-verilator\`, \`build-yosys\`, \`build-sby\`, \`build-z3\`, or \`make build-toolchain\` for all (see \`tools/mk/toolchain.mk\`)`
- Line 172: `verilator --version    # Should show 5.036-5.042 (5.044 is buggy!)` → `verilator --version    # Should show 5.052`
- Line 173: `yosys --version        # Should show ≥0.40` → `yosys --version        # Should show ≥0.70`
- Line 174: `sby --version          # Should show ≥0.40` → `sby --version          # Should show ≥0.70`
- Line 175: `z3 --version           # Should show ≥4.8` → `z3 --version           # Should show ≥5.0`
- Line 292 (env-check help text): `verilator 5.036-5.042` → `verilator 5.052, yosys/sby ≥0.70, z3 ≥5.0`

- [ ] **Step 4: Verify**

Run: `source ./env-setup && make env-check`
Expected: all four tools found, versions 5.052 / 0.70 / v0.70 / 5.3.1, "All required tools are available!".

Run (negative test): `PATH=/usr/bin:$PATH make env-check`
Expected: fails on old yosys/z3/verilator with the new messages.

- [ ] **Step 5: Commit**

```bash
git add tools/mk/environment.mk README.md
git commit -m "build: Pin Verilator 5.052, Yosys/SBY >=0.70, Z3 >=5.0 with enforced floors

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Clean-worktree verification of the new stack

**Files:**
- None modified in the main tree (verification only; worktree at `/tmp/i2c_master-verify`).

**Interfaces:**
- Consumes: toolchain from Task 2, pins from Task 3.
- Produces: pass/fail record per target; any new-tool findings feed Task 8's review doc.

- [ ] **Step 1: Create the worktree (env-setup is git-ignored, so copy it in)**

```bash
git worktree add /tmp/i2c_master-verify HEAD
cp ./env-setup /tmp/i2c_master-verify/
cd /tmp/i2c_master-verify
source ./env-setup
```

- [ ] **Step 2: env-check**

Run: `make env-check`
Expected: pass (5.052 / 0.70 / v0.70 / 5.3.1).

- [ ] **Step 3: Lint**

Run: `make lint`
Expected: clean pass. If NEW warnings appear vs the old Verilator (they were waived under 5.042), record each one verbatim as an input for Task 8 — do not add waivers in this task.

- [ ] **Step 4: Sims + formal proofs**

Run: `make all`
Expected: `sim-tick-div`, `sim-sync-2ff`, `sim-i2c-od-pads`, `sim-i2c-bit-prim` all pass; `sby-tick-div`, `sby-sync-2ff`, `sby-i2c-bit-prim` all report `DONE (PASS, ...)`.

If an sby proof fails with solver/smtbmc errors (not a design counterexample trace): apply the Z3 contingency from Task 2 (`make build-z3 Z3_VERSION=4.15.4` in the main tree), rerun this step, record the fallback.

- [ ] **Step 5: Clean up**

```bash
cd /home/mikem/kicad/projects/fpga/i2c_master
git worktree remove /tmp/i2c_master-verify
```

Expected: `git status --short` shows only the pre-existing WIP + docs (no new changes from this task).

---

### Task 5: WIP cocotb status under the new stack (no edits)

**Files:**
- None modified.

**Interfaces:**
- Consumes: toolchain from Task 2; the uncommitted cocotb test in the main tree.
- Produces: pass/fail record + failure signature for Task 8's review.

- [ ] **Step 1: Ensure venv exists**

Run: `ls .venv/bin/activate >/dev/null 2>&1 || make venv-setup`
Expected: activation script exists (creation takes ~1 min if missing).

- [ ] **Step 2: Run the WIP cocotb test**

```bash
source ./env-setup
source .venv/bin/activate
make sim-coco-i2c-bit-prim 2>&1 | tee /tmp/coco-wip-run.log
```

Expected outcomes (all acceptable, record which): PASS, FAIL with assertion detail (the known "specification mismatch"), or infra error (e.g. Verilator flag incompatibility with cocotb 2.x/5.052 — record verbatim).

- [ ] **Step 3: Record, don't fix**

Copy the result summary + first failing assertion into the Task 8 notes. Do NOT edit `rtl/i2c_bit_prim.sv` or `test_i2c_bit_prim.py`.

---

### Task 6: Docs restructure — moves, ROADMAP, README links

**Files:**
- Create: `docs/ROADMAP.md`
- Move: `docs/LINTER.md` → `docs/guides/LINTER.md`; `docs/COCOTB.md` → `docs/guides/COCOTB.md`; `docs/BRICK-5-SINGLE-BIT.md` → `docs/notes/BRICK-5-SINGLE-BIT.md`; `docs/FORMAL-VERIFICATION-STRATEGY.md` → `docs/notes/FORMAL-VERIFICATION-STRATEGY.md`
- Delete: `docs/TOOLS-TODO.md`, `docs/COCOTB-TODO.md` (content merged into ROADMAP)
- Modify: `README.md:375-376` (Documentation links)

**Interfaces:**
- Consumes: nothing from earlier tasks (independent of Tasks 1-5 — may be executed in parallel with them).
- Produces: `docs/ROADMAP.md`; the new paths that Task 7's `AGENTS.md`/`docs/README.md` reference.

- [ ] **Step 1: Moves**

```bash
mkdir -p docs/guides docs/notes
git mv docs/LINTER.md docs/guides/LINTER.md
git mv docs/COCOTB.md docs/guides/COCOTB.md
git mv docs/BRICK-5-SINGLE-BIT.md docs/notes/BRICK-5-SINGLE-BIT.md
git mv docs/FORMAL-VERIFICATION-STRATEGY.md docs/notes/FORMAL-VERIFICATION-STRATEGY.md
```

- [ ] **Step 2: Write `docs/ROADMAP.md`**

```markdown
# Roadmap

Prioritized backlog. Nothing here blocks anything; check items off as done.

## Toolchain

- [x] Reusable source-build make targets (`tools/mk/toolchain.mk`) — added 2026-10-19
- [ ] Second-opinion lint/analysis front-end: evaluate **slang** (compiler/elaborator + lint) and/or **Verible** (formatter + style linter + LSP) and/or **svlint** — catch "compiles but not what I meant" classes: implicit nets, width mismatches, incomplete case, blocking/nonblocking misuse, unintended signed math
- [ ] Build glue (**Edalize** / **FuseSoC**) — only if the Makefile grows into its own project

## Cocotb testbenches

- [ ] I²C **monitor + scoreboard**: print START/STOP, addr+R/W, each byte, ACK/NACK, timestamps — "logic-analyzer style" output instead of bit-staring at waves (~30 lines with cocotbext-i2c building blocks)
- [ ] Gate the legacy SV testbench `$finish` on cocotb presence (the `+cocotb` plusarg / `$test$plusargs` idea from the old COCOTB-TODO) so one testbench serves both flows — note: `sim/cocotb.mk` currently passes `+define+COCOTB_SIM` instead; unify on one mechanism
- [ ] Use cocotb's `regression` target semantics for dependency-aware re-runs

## Formal verification

- [ ] `i2c_bit_prim`: bounded liveness — assume "if `want_scl_high` stays 1, `scl_sync` becomes 1 within N ticks", then prove "done within M ticks" (from `notes/FORMAL-VERIFICATION-STRATEGY.md`)
- [ ] SBY `cover` mode for trace generation: "one valid IDLE→START→…→STOP trace", "a trace where ACK=0" — short targeted waves instead of full sims
- [ ] Smaller/focused dumps: trigger-on-fail style FST windowing (FST already default)

## Hardware bring-up (later)

- [ ] sigrok/PulseView + built-in I²C decoder for logic-analyzer day
```

- [ ] **Step 3: Remove the merged TODO files**

```bash
git rm docs/TOOLS-TODO.md docs/COCOTB-TODO.md
```

- [ ] **Step 4: Update README links**

`README.md` lines 375-376:

```markdown
## Documentation

- [Documentation index](docs/README.md)
- [Roadmap](docs/ROADMAP.md)
```

(The linting section at README:349 references `docs/LINTER.md` — change to `docs/guides/LINTER.md`.)

- [ ] **Step 5: Sweep for stale references**

Run: `grep -rn "docs/LINTER\|docs/COCOTB\.md\|TOOLS-TODO\|COCOTB-TODO\|FORMAL-VERIFICATION-STRATEGY" --include="*.md" --include="*.mk" --include="Makefile" --include="*.yml" . | grep -v docs/superpowers | grep -v ROADMAP.md`
Expected: no output (all references updated). Fix any stragglers found.

- [ ] **Step 6: Verify build still works**

Run: `source ./env-setup && make lint`
Expected: unchanged pass (docs moves don't affect builds — sanity only).

- [ ] **Step 7: Commit**

```bash
git add -A docs README.md
git commit -m "docs: Reorganize docs by purpose, merge TODOs into ROADMAP.md

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: AI-assistant files + docs index + commit untracked work

**Files:**
- Create: `AGENTS.md`, `CLAUDE.md`, `docs/README.md`
- Add (currently untracked): `docs/design/i2c_master/*.md`, `.zed/settings.json`

**Interfaces:**
- Consumes: paths created by Task 6 (`docs/guides/`, `docs/notes/`, `docs/ROADMAP.md`), targets from Task 1.
- Produces: `AGENTS.md` — the AI contract referenced by `CLAUDE.md` and used by every future session.

- [ ] **Step 1: Write `AGENTS.md`**

```markdown
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
| All sims + proofs | `make all` |
| Rebuild tools from source | `make build-toolchain` (or single: `build-verilator`, `build-yosys`, `build-sby`, `build-z3`) |

## Naming conventions (build system auto-discovers by these patterns)

- RTL: `rtl/<module>.sv`, module name == filename, snake_case.
- Testbench: `sim/<module>/tb_<module>.sv`.
- cocotb test: `sim/<module>/test_<module>.py`.
- Formal: `formal/<module>/<module>_formal_top.sv` + `<module>.sby`.
- Waivers: `sim/<module>/<module>.vlt`, `formal/<module>/<module>.vlt`.
- Make targets use hyphens (`sim-tick-div`); module names use underscores.

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

- Uncommitted WIP may exist (especially on `coco-bit-prim` branch) — never
  revert or "clean up" the owner's WIP without asking.
- Don't modify `docs/superpowers/` (specs/plans) unless working on them.
- Conventional commits: `feat:`, `fix:`, `docs:`, `test:`, `build:`.
```

- [ ] **Step 2: Write `CLAUDE.md`**

```markdown
Read [AGENTS.md](AGENTS.md) — it applies to all AI assistants in this repo, including Claude Code.
```

- [ ] **Step 3: Write `docs/README.md`**

```markdown
# Documentation Index

| Path | What it is |
|------|------------|
| `guides/LINTER.md` | Linting infrastructure: filelists, waivers, editor integration |
| `guides/COCOTB.md` | How cocotb testbenches integrate with the Makefile |
| `design/i2c_master/` | Per-module design docs (interface, behavior, intent) |
| `notes/BRICK-5-SINGLE-BIT.md` | The single-bit brick: 4-state design and what formal proves |
| `notes/FORMAL-VERIFICATION-STRATEGY.md` | Proof reuse, assume-guarantee, compositional strategy |
| `ROADMAP.md` | Prioritized backlog: toolchain, cocotb, formal, hardware |
| `reviews/` | Dated project reviews |
| `superpowers/specs/` + `superpowers/plans/` | Design specs and implementation plans for planned work |
```

- [ ] **Step 4: Commit untracked design docs and Zed settings**

```bash
git add docs/design/i2c_master .zed/settings.json AGENTS.md CLAUDE.md docs/README.md
git commit -m "docs: Add AGENTS.md/CLAUDE.md AI guide, docs index; commit design docs and Zed settings

Co-Authored-By: Claude <noreply@anthropic.com>"
```

- [ ] **Step 5: Verify references in AGENTS.md are real**

Run: `make help >/dev/null && test -f docs/guides/LINTER.md && test -f docs/ROADMAP.md && echo OK`
Expected: `OK`.

---

### Task 8: Methodology review

**Files:**
- Create: `docs/reviews/2026-10-19-project-review.md`

**Interfaces:**
- Consumes: Task 4's verification record (new-tool warnings/proof status), Task 5's WIP cocotb record.
- Produces: the review document (final deliverable; nothing gets fixed in this session).

**Review focus — "how to correctly structure, write, lint, simulate", NOT "your I²C is buggy".** This is a learning repo; RTL bugs are the learner's material. Only include protocol-correctness observations where they teach a methodology lesson.

**Method:** for each dimension below, read the named files, compare against stated goals, and write findings tagged `structure` / `methodology` / `workflow` / `nice-to-have`, each with `file:line` cites. Verify the seed findings before including them; drop any that don't hold up.

- [ ] **Step 1: Examine the dimensions**

1. **Project structure**: folder layout vs README's own "Project Structure" section; per-module file pairing; root-dir clutter (`*.fst`, `*.surf.ron`, `dump.fst` — should sims write waves into `build/` instead?).
2. **SV writing methodology**: reset conventions across modules (async `negedge rst_n` — consistent?), `always_comb`/`always_ff` split style (note `rtl/i2c_bit_prim.sv` WIP refactor moved to `st_q`/`st_d` — assess the pattern, not the WIP correctness), timescale directive usage vs the `-Wno-TIMESCALEMOD` waiver in `Makefile:23`, `unique case` usage.
3. **Simulation setup**: Verilator flags in `Makefile:19-27` vs `sim/cocotb.mk:34-40` (duplicated/divergent flag sets?); the `+define+COCOTB_SIM` vs `$test$plusargs("cocotb")` gating mismatch (seed from `docs/COCOTB-TODO.md` — was a plan, never landed); testbench structure (self-checking? `$finish` discipline?).
4. **Lint/formal workflow**: waiver files hygiene (commented vs active, explanations present); `lint_config.yml` exclusions; sby scripts (engines, depth, modes — `mode prove` vs `bmc` choices); README "Current Modules" table claims vs reality.
5. **AI-readiness**: post-restructure, does `AGENTS.md` + index give an assistant everything? What's still missing (e.g. per-module test instructions, known-failures list)?
6. **Verification records from Tasks 4-5**: any new-tool warnings, proof status, WIP cocotb failure signature — what do they teach methodologically?

**Seed findings to verify:**
- README:369-371 module table shows Formal = `-` for `i2c_bit_prim` and `i2c_scl_req`, but `formal/i2c_bit_prim/` and `formal/i2c_scl_req/` both exist with tops + `.sby` scripts — docs drift (`workflow`).
- Two cocotb-gating mechanisms designed/used inconsistently (`structure`).
- Waveforms dumped at repo root rather than under `build/` (`structure`).

- [ ] **Step 2: Write the review document**

Use this skeleton, filling each section with verified findings:

```markdown
# Project Review — 2026-10-19

Scope: methodology (structure, directives, lint/sim/formal workflow, AI-readiness).
Explicitly out of scope: I²C protocol correctness — this is a learning repo.
Toolchain at review time: Verilator 5.052, Yosys/SBY 0.70, Z3 5.3.1.

## Verification status under the new toolchain
(env-check / lint / sims / sby results from the clean-worktree run; WIP cocotb status)

## Structure findings
## Methodology findings
## Workflow findings
## Nice-to-haves
## What's already good
(praise what deserves it — the bricks decomposition, waiver discipline, formal strategy docs)
```

- [ ] **Step 3: Commit**

```bash
git add docs/reviews/2026-10-19-project-review.md
git commit -m "docs: Add 2026-10-19 methodology review

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: Final wrap-up

**Files:** none created.

- [ ] **Step 1: WIP untouched check**

Run: `git status --short && git diff --stat`
Expected: exactly the session-start state for WIP — `M rtl/i2c_bit_prim.sv`, `M sim/i2c_bit_prim/test_i2c_bit_prim.py` — plus nothing unexpected. (Spec/superpowers commits and the new files from Tasks 1-8 are separate and committed.)

- [ ] **Step 2: Final env sanity**

Run: `source ./env-setup && make env-check && make lint`
Expected: pass/pass.

- [ ] **Step 3: Report to owner**

Summary must state: tools built + versions, verification results (incl. any Z3 fallback used and why), docs restructure commits, review doc path, and the note that `~/kicad/projects/fpga/tools/verilator.bak` (old 5.042) can be deleted once they're satisfied — plus `~/kicad/projects/fpga/tools/src/*` source trees (~1-2 GB) are safe to keep for fast rebuilds or delete to save disk.

---
