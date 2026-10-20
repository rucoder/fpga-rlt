# SystemVerilog Learning Repository

This is my collection of RTL modules written while learning SystemVerilog, formal verification, and simulation. They're small, focused designs - not production-scale projects you'd typically see in industry. But that's the point: I learn by building these simple, well-tested primitives from the ground up.

One day they might become something useful. For now, they're a record of my learning journey and a resource for others taking a similar path.

## Prerequisites

### Environment Setup

The project requires specific tools and paths to be configured. Instead of relying on Makefile exports, use the provided `env-setup` script:

**For bash/zsh:**
```bash
# First time setup: copy the example and configure your paths
cp env-setup.example env-setup
# Edit env-setup and fill in your OSSCAD and VERILATOR_PATH values

# Source the environment setup script (do this in each new shell session)
source ./env-setup

# Verify all required tools are installed and configured
make env-check
```

**For fish shell:**
```fish
# First time setup: copy the example and configure your paths
cp env-setup.fish.example env-setup.fish
# Edit env-setup.fish and fill in your OSSCAD and VERILATOR_PATH values

# Source the environment setup script (do this in each new shell session)
source ./env-setup.fish

# Verify all required tools are installed and configured
make env-check
```

The `env-setup` scripts:
- Sets up paths for OSS CAD Suite and Verilator
- Must be sourced (not executed directly) - includes a check for this
- Configures `OSSCAD` and `PATH` environment variables
- Available in both POSIX shell (`env-setup`) and fish shell (`env-setup.fish`) versions
- **Note:** Both `env-setup` and `env-setup.fish` are git-ignored; use the `.example` versions as templates
- Any tool can be rebuilt from pinned source: `make build-verilator`, `build-yosys`, `build-sby`, `build-z3`, or `make build-toolchain` for all (see `tools/mk/toolchain.mk`)

The `env-check` target verifies:
- `sby` is available
- `yosys` is available (≥0.70)
- `z3` is available (≥5.0)
- `verilator` is available and version is exactly 5.052 (5.044 crashed reproducibly here — rebuild with `make build-verilator`)

### Required Tools

#### 1. Verilator (5.052)
SystemVerilog simulator and linter.

**Fedora/RHEL:**
```bash
sudo dnf install verilator
```

**Ubuntu/Debian:**
```bash
sudo apt install verilator
```

**From source:**
```bash
git clone https://github.com/verilator/verilator
cd verilator
autoconf && ./configure && make -j$(nproc)
sudo make install
```

#### 2. Yosys (≥0.70)
Open-source synthesis tool for formal verification.

**Build from source (recommended):**
I built Yosys from source and installed to `~/.local/oss-cad` following the [official build instructions](https://yosyshq.readthedocs.io/projects/yosys/en/latest/getting_started/installation.html#building-from-source).

**Package manager (alternative):**
```bash
# Fedora/RHEL
sudo dnf install yosys

# Ubuntu/Debian
sudo apt install yosys
```

#### 3. SymbiYosys (SBY) (≥0.70)
Formal verification flow manager.

```bash
git clone https://github.com/YosysHQ/sby.git
cd sby
sudo make install
```

#### 4. Z3 Theorem Prover (≥5.0)
SMT solver for formal verification.

**Fedora/RHEL:**
```bash
sudo dnf install z3
```

**Ubuntu/Debian:**
```bash
sudo apt install z3
```

**From source:** [Z3Prover/z3](https://github.com/Z3Prover/z3)

#### 5. Python 3 (≥3.8) + Virtual Environment
Required for build scripts and cocotb testing.

**Quick setup (installs cocotb, click, pyyaml):**
```bash
make venv-setup
```

**Manual setup (versions must match the pins in `tools/mk/python.mk`):**
```bash
# Create virtual environment
python -m venv .venv
source .venv/bin/activate.fish  # or: source .venv/bin/activate
pip install -U pip
pip install cocotb==2.1.0 cocotb-bus==0.3.0 cocotb-test==0.2.6
pip install cocotbext-i2c==0.1.2
pip install click==8.3.1
pip install pyyaml==6.0.3
```

#### 6. Surfer (Recommended) or GTKWave
Waveform viewer. I use Surfer for inspecting simulation waveforms.

**Surfer:**
```bash
# Install from https://surfer-project.org/
# Or via cargo:
cargo install surfer
```

**GTKWave (alternative):**
```bash
sudo dnf install gtkwave
```

Note: `.surf.ron` files in the repo store Surfer's waveform viewer state per module.

### Verify Installation

```bash
# First time: create your env-setup from template
# For bash/zsh:
cp env-setup.example env-setup
# For fish:
cp env-setup.fish.example env-setup.fish

# Edit env-setup (or env-setup.fish) and configure your paths

# Source environment setup
# For bash/zsh:
source ./env-setup
# For fish:
source ./env-setup.fish

# Check all required tools (recommended)
make env-check

# Manual verification
verilator --version    # Should show 5.052
yosys --version        # Should show ≥0.70
sby --version          # Should show ≥0.70
z3 --version           # Should show ≥5.0
python3 --version      # Should show ≥3.8
surfer --version       # Optional
```

## Quick Start

```bash
# Setup environment (do this in each new shell session)
# For bash/zsh:
source ./env-setup
# For fish:
source ./env-setup.fish

# Verify tools are installed correctly
make env-check

# Setup Python environment (first time only)
make venv-setup

# Generate lint filelists
make lint-lists

# Lint all modules
make lint

# Run simulation
make sim-tick-div

# Run formal verification
make sby-tick-div

# View waveforms (Surfer or GTKWave)
surfer tb_tick_div.fst
# or: gtkwave tb_tick_div.fst
```

## Project Structure

```
├── rtl/                    # RTL source files
│   └── <module>.sv         # Module implementation
├── sim/                    # Simulation testbenches
│   └── <module>/
│       ├── tb_<module>.sv  # Testbench
│       └── <module>.vlt    # Verilator waivers (optional)
├── formal/                 # Formal verification
│   └── <module>/
│       ├── <module>_formal_top.sv    # Formal harness
│       ├── <module>.sby              # SymbiYosys script
│       └── <module>.vlt              # Verilator waivers (optional)
├── build/                  # Build outputs (generated)
├── tools/                  # Build and lint scripts
├── docs/                   # Documentation
├── lint_config.yml         # Linting configuration
└── Makefile               # Build system
```

## Naming Conventions

**CRITICAL: The build system auto-discovers modules based on these patterns.**

### RTL Modules
```
Location: rtl/<module>.sv
Module name: <module>
Example: rtl/tick_div.sv → module tick_div
```

### Testbenches
```
Location: sim/<module>/tb_<module>.sv
Top module: tb_<module>
Example: sim/tick_div/tb_tick_div.sv → module tb_tick_div
```

### Formal Tops
```
Location: formal/<module>/<module>_formal_top.sv
Top module: <module>_formal_top
Example: formal/tick_div/tick_div_formal_top.sv → module tick_div_formal_top
```

### Waiver Files
```
sim/<module>/<module>.vlt
formal/<module>/<module>.vlt
```

**Module names:** Use `snake_case` (✅ `tick_div` ❌ `TickDiv`)  
**Make targets:** Use hyphens (✅ `make sim-tick-div`)

## Adding a New Module

```bash
# 1. Create RTL module
echo 'module my_module; endmodule' > rtl/my_module.sv

# 2. Create testbench (optional)
mkdir -p sim/my_module
touch sim/my_module/tb_my_module.sv
# Top module MUST be named: tb_my_module

# 3. Create formal harness (optional)
mkdir -p formal/my_module
touch formal/my_module/my_module_formal_top.sv
touch formal/my_module/my_module.sby
# Top module MUST be named: my_module_formal_top

# 4. Regenerate filelists
make lint-lists
```

## Make Targets

**Environment:**
```bash
make env-check            # Verify required tools (sby, yosys, z3, verilator 5.052, yosys/sby ≥0.70, z3 ≥5.0)
```

**Simulation:**
```bash
make sim-<module>         # Run Verilator testbench
make sim-coco-<module>    # Run cocotb testbench (if available)
make all                  # Run all simulations
```

**Formal Verification:**
```bash
make sby-<module>         # Run formal verification
```

**Linting:**
```bash
make lint                 # Lint all modules
make lint-lists           # Regenerate filelists
make generate-waivers     # Generate waiver files
make list-waivers         # List waivers
make clean-waivers        # Remove waivers
```

**Cleanup:**
```bash
make clean                # Remove build artifacts
```

## Linting

The project uses Verilator for linting with automatic filelist generation and git-versioned waivers.

### Lint Configuration

Edit `lint_config.yml` to exclude modules:

```yaml
exclude:
  - "broken_module_formal_top"
  - "tb_experimental"
```

Then regenerate: `make lint-lists`

### Waiver Management

Waivers are committed to git. New waivers are appended as commented - you must uncomment to activate.

```bash
make generate-waivers     # Merge new warnings into existing .vlt files
git diff sim/*/*.vlt      # Review new warnings
# Either: uncomment waiver + add explanation
# Or: fix the real issue in RTL
git commit
```

See `docs/guides/LINTER.md` for details.

## Editor Integration

### Zed Editor (slang-server LSP)

Real-time diagnostics via the `verilog` extension, which auto-downloads
[slang-server](https://github.com/hudson-trading/slang-server) (a SystemVerilog
language server built on the slang compiler).

1. Install the `Verilog` extension in Zed — slang-server is fetched automatically
2. Project context (include dirs, indexed dirs) lives in `.slang/server.json`
   (auto-loaded, auto-reloaded on save)
3. Note: slang is a *second-opinion* linter alongside Verilator — a finding in
   Zed that `make lint` doesn't report means either a waived Verilator warning
   or a rule only slang enforces. Prefer code both accept (e.g. the formal-top
   reset glue uses plain `always`, not `always_ff` — see the formal tops).

The older Veridian LSP integration (`veridian.yml` +
`tools/zed_verilator_wrapper.py`) is **kept but inactive** — the extension no
longer runs Veridian by default. To re-enable it (IDE == `make lint` exactly,
same tool + waivers): set in Zed settings
`"languages": {"SystemVerilog": {"language_servers": ["veridian", "!slang"]}}`
and keep filelists fresh with `make lint-lists`.

## Current Modules

| Module | RTL | Testbench | Formal | Description |
|--------|-----|-----------|--------|-------------|
| `tick_div` | ✅ | ✅ | ✅ | Configurable clock divider |
| `sync_2ff` | ✅ | ✅ | ✅ | 2-FF synchronizer |
| `i2c_od_pads` | ✅ | ✅ | - | Open-drain I/O pads |
| `i2c_bit_prim` | ✅ | ✅ | harness | I2C bit-level primitive |
| `i2c_scl_req` | ✅ | ✅ | harness | SCL request arbiter |

Note: `harness` = formal harness exists; check the Makefile `all:` target for which proofs currently run by default and why.

## Documentation

- [Documentation index](docs/README.md)
- [Roadmap](docs/ROADMAP.md)

## Resources

- [Verilator Manual](https://verilator.org/guide/latest/)
- [Yosys Documentation](https://yosyshq.readthedocs.io/)
- [SymbiYosys Documentation](https://symbiyosys.readthedocs.io/)
- [Z3 Theorem Prover](https://github.com/Z3Prover/z3)
