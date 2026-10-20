# Cocotb Testbench Integration

This project supports both Verilator C++ testbenches and cocotb Python testbenches.

## Overview

Cocotb allows writing testbenches in Python instead of SystemVerilog or C++. This is useful for:
- Complex test scenarios with high-level abstractions
- Integration with Python libraries (e.g., cocotbext-i2c)
- Rapid prototyping and debugging

## Running Cocotb Tests

```bash
# Run cocotb testbench for a module
make sim-coco-<module>

# Example
make sim-coco-tick-div
```

## Project Structure

```
sim/<module>/
├── tb_<module>.sv          # Verilator testbench (C++)
└── test_<module>.py        # Cocotb testbench (Python) - optional
```

If `test_<module>.py` exists, the cocotb target will be available.

## SystemVerilog Testbench Compatibility

When a module has both Verilator and cocotb testbenches, the SystemVerilog testbench must guard Verilator-specific code:

```systemverilog
module tb_my_module;
    // DUT instantiation
    my_module dut (...);
    
`ifndef COCOTB_SIM
    // Verilator-specific testbench code
    initial begin
        // Clock generation
        // Reset logic
        // Test stimulus
    end
`endif

endmodule
```

The `COCOTB_SIM` macro is defined when cocotb is driving the simulation. All Verilator testbench logic (clock generation, stimulus, etc.) must be wrapped in `ifndef COCOTB_SIM` to avoid conflicts.

## Cocotb Test File Template

```python
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

@cocotb.test()
async def basic_test(dut):
    """Basic test description"""
    # Start clock
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    
    # Test logic here
    await RisingEdge(dut.clk)
```

## Configuration

Cocotb tests are configured in `sim/cocotb.mk`. The makefile:
- Uses `TOPLEVEL` to specify the module under test
- Sources RTL files from `rtl/` directory
- Generates waveforms (FST format)
- Requires Python virtual environment with cocotb installed

## Dependencies

Cocotb tests require the Python virtual environment:

```bash
# One-time setup
make venv-setup

# Activate before running tests
source .venv/bin/activate      # bash/zsh
source .venv/bin/activate.fish # fish
```

## Waveform Viewing

Cocotb generates FST waveforms in the build directory:

```bash
# View waveforms
surfer build/cocotb/<module>/dump.fst
# or
gtkwave build/cocotb/<module>/dump.fst
```

## When to Use Cocotb vs Verilator

**Use Verilator testbenches when:**
- Simple directed tests
- Performance-critical simulations
- Minimal dependencies preferred

**Use cocotb testbenches when:**
- Complex test scenarios
- Need Python libraries (e.g., I2C/SPI bus models)
- Prefer Python over C++/SystemVerilog