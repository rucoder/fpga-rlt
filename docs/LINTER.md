# Linting Infrastructure

This document describes the linting infrastructure for the i2c_master project, including how lint checks are performed, how filelists are generated, waiver management, and integration with both Make and the Zed editor.

## Overview

The project uses **Verilator** as the primary linter for SystemVerilog code. The linting infrastructure is designed to:

1. **Discover all top modules** automatically from `sim/`, `formal/`, and `rtl/` directories
2. **Generate filelists** (`.f` files) for each top module
3. **Run Verilator** with appropriate include paths, dependencies, and waivers
4. **Support two modes**: command-line (Make) and LSP (Zed editor via Veridian)
5. **Manage waivers** per-module to suppress known/acceptable warnings

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     lint_config.yml                          │
│              (Exclude patterns for tops)                     │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│            tools/gen_lint_filelists.py                       │
│  • Discovers all top modules (tb_*, *_formal_top)           │
│  • Filters based on exclude list                            │
│  • Generates build/lint/tops.txt                            │
│  • Generates build/lint/lint_<top>.f for each top           │
│  • Generates build/rtl_lib.f (RTL as libraries)             │
└──────────────┬──────────────────────────────────────────────┘
               │
               │  Creates:
               │  • build/lint/tops.txt
               │  • build/lint/lint_*.f
               │  • build/rtl_lib.f
               │
               ▼
┌──────────────────────────────┐  ┌─────────────────────────────┐
│  tools/lint_verilator.py     │  │ tools/zed_verilator_wrapper.py│
│  (Make target: make lint)    │  │ (LSP for Zed/Veridian)       │
│  • Reads tops.txt            │  │ • Reads tops.txt             │
│  • Runs verilator per top    │  │ • Finds tops for edited file │
│  • Shows full output         │  │ • Runs verilator per top     │
│  • Returns error if fails    │  │ • Returns diagnostics to LSP │
└──────────────────────────────┘  └─────────────────────────────┘
               │                                 │
               └─────────────┬───────────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │   Verilator     │
                    │   --lint-only   │
                    └─────────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │  Waiver Files   │
                    │  sim/*/*.vlt    │
                    │  formal/*/*.vlt │
                    └─────────────────┘
```

## Directory Structure

```
i2c_master/
├── lint_config.yml              # Linting configuration (exclude patterns)
├── veridian.yml                 # Veridian LSP configuration (for Zed)
├── build/
│   ├── rtl_lib.f                # RTL modules as libraries
│   └── lint/
│       ├── tops.txt             # List of all discovered tops
│       ├── lint_tb_*.f          # Filelist for each testbench top
│       ├── lint_*_formal_top.f  # Filelist for each formal top
│       └── logs/
│           └── verilator_multi.log  # LSP wrapper log
├── sim/
│   └── <module>/
│       ├── tb_<module>.sv       # Testbench (top module)
│       └── <module>.vlt         # Waiver file for this testbench
├── formal/
│   └── <module>/
│       ├── <module>_formal_top.sv   # Formal harness (top module)
│       └── <module>.vlt             # Waiver file for formal checks
└── tools/
    ├── gen_lint_filelists.py        # Generate filelists and tops
    ├── lint_verilator.py            # Run linting from Make
    ├── zed_verilator_wrapper.py     # Wrapper for Zed/Veridian LSP
    └── manage_waivers.py            # Waiver management tool
```

## Components

### 1. Lint Configuration (`lint_config.yml`)

Controls which top modules are excluded from linting:

```yaml
# Exclude list: patterns to match against top names or directory names
exclude:
  - "i2c_bit_prim_formal_top"
  - "i2c_scl_req_formal_top"
```

**Pattern Matching:**
- Patterns match against top module names (e.g., `tb_tick_div`, `sync_2ff_formal_top`)
- Patterns also match against parent directory names
- Substring matching is used (pattern just needs to appear in the name)

**Note:** After modifying `lint_config.yml`, run `make lint-lists` to regenerate the tops list.

### 2. Filelist Generation (`tools/gen_lint_filelists.py`)

This script discovers all top modules and generates filelists for each one.

**Discovery Rules:**
- **Testbenches**: `sim/<module>/tb_<module>.sv` → top name: `tb_<module>`
- **Formal tops**: `formal/<module>/<module>_formal_top.sv` → top name: `<module>_formal_top`

**Generated Files:**
- `build/rtl_lib.f`: All RTL modules as libraries (`-v` flag) with include directories
- `build/lint/tops.txt`: List of all discovered top module names (after exclusion filtering)
- `build/lint/lint_<top>.f`: Filelist for each top, includes:
  - Reference to `rtl_lib.f` (via `-f`)
  - Any helper modules in the same directory as the top (as `-v`)
  - The top module file itself (as direct input)

**Usage:**
```bash
# Generate filelists (triggered automatically by make lint)
make lint-lists

# Or run directly:
./tools/gen_lint_filelists.py

# With waiver generation:
./tools/gen_lint_filelists.py --generate-waivers
./tools/gen_lint_filelists.py --update-waivers
```

**Important:** Waiver files are **NOT** included in the `.f` filelists! They must be specified on the command line separately to avoid conflicts when generating waivers with `--waiver-output`.

### 3. Command-Line Linting (`tools/lint_verilator.py`)

Runs Verilator on all tops from the command line (invoked by `make lint`).

**Features:**
- Reads `build/lint/tops.txt` for list of tops to lint
- Runs Verilator once per top module
- Shows full Verilator output (errors and warnings)
- Exits with error code if any top fails
- Automatically includes waiver files if they exist

**Waiver File Discovery:**
- For `tb_<module>`: uses `sim/<module>/<module>.vlt`
- For `<module>_formal_top`: uses `formal/<module>/<module>.vlt`

**Usage:**
```bash
# Lint all tops
make lint

# Regenerate filelists first, then lint
make lint-lists lint
```

**Output Example:**
```
Linting 7 tops: sync_2ff_formal_top, tb_i2c_bit_prim, ...

=== Linting sync_2ff_formal_top ===
  Waiver file: formal/sync_2ff/sync_2ff.vlt
  Command: verilator --top-module sync_2ff_formal_top --lint-only -sv --timing -Wall ...
  PASSED

...

SUCCESS: All 7 tops passed lint
```

### 4. LSP Wrapper for Zed Editor (`tools/zed_verilator_wrapper.py`)

Provides real-time linting in the Zed editor via the Veridian language server.

**Features:**
- Called by Veridian LSP instead of Verilator directly
- Reads pre-generated filelists (doesn't scan directories - optimized for LSP hot path)
- When a file is edited, finds which top(s) contain that file
- For RTL library files (`rtl/*.sv`), lints them standalone
- For testbench/formal files, lints all relevant tops
- Logs all activity to `build/lint/logs/verilator_multi.log`
- Always returns exit code 0 (LSP expects diagnostics in stdout)

**Configuration:** `veridian.yml` points to `./tools/zed_verilator_wrapper.py`

**Debug log:** `build/lint/logs/verilator_multi.log`

### 5. Waiver Management (`tools/manage_waivers.py`)

**Waivers are committed to git** and version-controlled.

**Location:** `sim/<module>/<module>.vlt` or `formal/<module>/<module>.vlt`

**Workflow:**
1. `make generate-waivers` - tool merges new warnings with existing `.vlt` files
2. New warnings appended **as commented** (must uncomment to activate)
3. Review with `git diff`, then either uncomment waiver OR fix code
4. Commit to git

**Commands:**
```bash
make generate-waivers                          # All modules
./tools/manage_waivers.py generate --module X  # Specific
make list-waivers / clean-waivers
```

**Merge behavior:** Preserves existing waivers, appends only new (duplicates skipped), safe to re-run.

### 6. Veridian LSP Configuration (`veridian.yml`)

Configures the Veridian language server for Zed editor integration.

**Key Settings:**
```yaml
# Source directories to search
source_dirs:
  - rtl
  - sim
  - formal

# Auto-discover files in working directory
auto_search_workdir: true

# Verilator wrapper (calls our script instead of verilator directly)
verilator:
  syntax:
    enabled: true
    path: "./tools/zed_verilator_wrapper.py"
    args:
      - --lint-only
      - -sv
      - --timing
      - -Wall
```

## Workflow

### Workflow

1. `make lint-lists` - generate filelists
2. `make lint` - lint all modules
3. `make generate-waivers` - generate waivers for warnings
4. Uncomment accepted waivers in `.vlt` files

**Adding modules:** Create `sim/<module>/tb_<module>.sv` or `formal/<module>/<module>_formal_top.sv`, then `make lint-lists`

**Excluding modules:** Add to `lint_config.yml` exclude list, then `make lint-lists`

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make lint` | Lint all modules (auto-runs `lint-lists` if needed) |
| `make lint-lists` | Regenerate filelists and tops (force rebuild) |
| `make generate-waivers` | Generate/update waiver files for all modules |
| `make list-waivers` | List all existing waiver files |
| `make clean-waivers` | Remove all waiver files |
| `make clean` | Remove all build artifacts (including filelists) |

## Verilator Options

The following Verilator options are used for linting:

| Option | Description |
|--------|-------------|
| `--lint-only` | Only perform linting (no compilation) |
| `-sv` | Enable SystemVerilog mode |
| `--timing` | Enable timing checks (for SystemVerilog timing constructs) |
| `-Wall` | Enable all warnings |
| `--top-module <name>` | Specify the top module to lint |
| `-f <filelist>` | Read options/files from filelist |
| `-v <file>` | Treat file as a library (only elaborate if referenced) |
| `+incdir+<dir>` | Add include directory |

**Waivers are specified on command line (not in filelist):**
```bash
verilator --lint-only -sv --timing -Wall \
  --top-module tb_tick_div \
  -f build/lint/lint_tb_tick_div.f \
  sim/tick_div/tick_div.vlt  # <-- Waiver file
```

## Troubleshooting

- **No tops found:** `make lint-lists`
- **Module not linted:** Check `lint_config.yml` exclude list, verify naming (`tb_*.sv` or `*_formal_top.sv`), run `make lint-lists`
- **Zed not showing errors:** `make lint-lists`, check `build/lint/logs/verilator_multi.log`
- **Waivers not working:** Uncomment waivers (`// /* lint_off` → `/* lint_off`), verify correct warning type
- **Make won't regenerate:** `rm build/lint/.stamp && make lint-lists`

## Best Practices

1. Run `make lint` before committing
2. Commit `.vlt` files to git (they're source code)
3. Use waivers sparingly - fix issues first
4. Don't commit commented waivers
5. Keep `lint_config.yml` minimal

## CI/CD

Don't run `generate-waivers` in CI - waivers must be committed by developers.

```yaml
lint:
  script:
    - make lint-lists
    - make lint
```

## References

- [Verilator Manual](https://verilator.org/guide/latest/)
- [Veridian LSP](https://github.com/vivekmalneedi/veridian)