# sim/cocotb.mk
# Usage:
#   make -f sim/cocotb.mk TOP=tb_i2c_bit_prim
#
# Expects: build/lint/lint_<TOP>.f exists (same as your lint lists)
# Runs: verilator + cocotb

TOP ?=
ifeq ($(strip $(TOP)),)
$(error TOP is required, e.g. TOP=tb_i2c_bit_prim)
endif

SIM ?= verilator
TOPLEVEL := $(TOP)

BUILD_DIR ?= build
SIM_BUILD ?= $(BUILD_DIR)/sim/$(TOPLEVEL)

# (optional) keep results per-top too
COCOTB_RESULTS_FILE ?= $(SIM_BUILD)/results.xml

# module directory name: tb_i2c_bit_prim -> i2c_bit_prim
MODDIR := $(patsubst tb_%,%,$(TOP))

# test module filename: sim/<mod>/test_<mod>.py -> python module test_<mod>
COCOTB_TEST_MODULES := test_$(MODDIR)
export COCOTB_TEST_MODULES

# Make that directory importable
export PYTHONPATH := $(abspath sim/$(MODDIR)):$(PYTHONPATH)
# print PYTHONPATH for debugging
$(info PYTHONPATH=$(PYTHONPATH))
# Reuse your generated filelist as Verilator inputs
EXTRA_ARGS += -f $(abspath build/lint/lint_$(TOP).f)

# Optional traces (what you already enabled)
EXTRA_ARGS += --trace --trace-fst --trace-structs --timing

# Define COCOTB_SIM for conditional compilation in testbenches
EXTRA_ARGS += +define+COCOTB_SIM

COCOTB_MAKEFILES := $(shell cocotb-config --makefiles)
include $(COCOTB_MAKEFILES)/Makefile.sim
