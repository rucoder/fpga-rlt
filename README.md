# SystemVerilog Learning Repository

This is my collection of RTL modules written while learning SystemVerilog, formal verification, and simulation. They're small, focused designs - not production-scale projects you'd typically see in industry. But that's the point: I learn by building these simple, well-tested primitives from the ground up.

One day they might become something useful. For now, they're a record of my learning journey and a resource for others taking a similar path.

## Prerequisites

### Required Tools

#### 1. Verilator (≥5.0)
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

#### 2. Yosys (≥0.40)
Open-source synthesis tool for formal verification.

**Fedora/RHEL:**
```bash
sudo dnf install yosys
```

**Ubuntu/Debian:**
```bash
sudo apt install yosys
```

**From source:** [YosysHQ/yosys](https://github.com/YosysHQ/yosys)

#### 3. SymbiYosys (SBY) (≥0.40)
Formal verification flow manager.

```bash
pip install symbiyosys
```

Or from source:
```bash
git clone https://github.com/YosysHQ/sby.git
cd sby
sudo make install
```

#### 4. Z3 Theorem Prover (≥4.8)
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

#### 5. Python 3 (≥3.8)
Required for build scripts.

```bash
sudo dnf install python3 python3-pip
pip install pyyaml
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
verilator --version    # Should show ≥5.0
yosys --version        # Should show ≥0.40
sby --version          # Should show ≥0.40
z3 --version           # Should show ≥4.8
python3 --version      # Should show ≥3.8
surfer --version       # Optional
```

## Quick Start

```bash
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

**Simulation:**
```bash
make sim-<module>         # Run testbench
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

See `docs/LINTER.md` for details.

## Editor Integration

### Zed Editor (Veridian LSP)

Real-time linting configured in `veridian.yml`.

1. Install Veridian extension in Zed
2. Generate filelists: `make lint-lists`
3. Open project - linting works automatically

Debug log: `build/lint/logs/verilator_multi.log`

## Current Modules

| Module | RTL | Testbench | Formal | Description |
|--------|-----|-----------|--------|-------------|
| `tick_div` | ✅ | ✅ | ✅ | Configurable clock divider |
| `sync_2ff` | ✅ | ✅ | ✅ | 2-FF synchronizer |
| `i2c_od_pads` | ✅ | ✅ | - | Open-drain I/O pads |
| `i2c_bit_prim` | ✅ | ✅ | - | I2C bit-level primitive |
| `i2c_scl_req` | ✅ | ✅ | - | SCL request arbiter |

## Documentation

- `docs/LINTER.md` - Linting infrastructure
- `docs/FORMAL-VERIFICATION-STRATEGY.md` - Formal verification approach
- `docs/BRICK-5-SINGLE-BIT.md` - I2C bit-level primitives

## Resources

- [Verilator Manual](https://verilator.org/guide/latest/)
- [Yosys Documentation](https://yosyshq.readthedocs.io/)
- [SymbiYosys Documentation](https://symbiyosys.readthedocs.io/)
- [Z3 Theorem Prover](https://github.com/Z3Prover/z3)