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
# Note: build-yosys uses the CMake flow — requires Yosys >= 0.62-ish; older tags
# (Makefile-based) won't configure. For frontend-only needs on old tags:
#   make config-gcc && ENABLE_ABC=0 make -j$(NPROC)   (run from the source dir)
YOSYS_VERSION     ?= 0.70
SBY_VERSION       ?= 0.70
Z3_VERSION        ?= 5.3.1

# Locations (must match env-setup / env-setup.fish)
TOOLS_ROOT       ?= $(HOME)/kicad/projects/fpga/tools
VERILATOR_PREFIX ?= $(TOOLS_ROOT)/verilator
OSSCAD_PREFIX    ?= $(HOME)/.local/oss-cad
TOOLCHAIN_SRC    ?= $(TOOLS_ROOT)/src

# Parallelism: leave 2 cores free so the machine stays usable during builds.
# Override per-invocation with: make build-<tool> NPROC=<n>
NPROC ?= $(shell echo $$(( $$(nproc) - 2 )))

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
	@mkdir -p $(TOOLCHAIN_SRC)/z3-$(Z3_VERSION)
	@if [ ! -f $(TOOLCHAIN_SRC)/z3-$(Z3_VERSION)/CMakeLists.txt ]; then \
		curl -L --fail https://github.com/Z3Prover/z3/archive/refs/tags/z3-$(Z3_VERSION).tar.gz \
			| tar xz --strip-components=1 -C $(TOOLCHAIN_SRC)/z3-$(Z3_VERSION); \
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
