# environment.mk - Environment validation targets

.PHONY: env-check
env-check:
	@echo "Checking required tools..."
	@echo ""
	@echo -n "Checking sby... "
	@if command -v sby >/dev/null 2>&1; then \
		echo "✓ found: $$(command -v sby)"; \
	else \
		echo "✗ NOT FOUND"; \
		echo "  Please install sby (part of oss-cad-suite)"; \
		exit 1; \
	fi
	@echo ""
	@echo -n "Checking yosys... "
	@if command -v yosys >/dev/null 2>&1; then \
		echo "✓ found: $$(command -v yosys)"; \
		YOSYS_VERSION=$$(yosys --version | head -n1 | awk '{print $$2}'); \
		YOSYS_MINOR=$$((10#$$(echo $$YOSYS_VERSION | cut -d. -f2 | cut -d+ -f1))); \
		if [ "$$YOSYS_MINOR" -lt 70 ]; then \
			echo "  ✗ Too old (need ≥0.70): make build-yosys"; \
			exit 1; \
		fi; \
		echo "  Version: $$YOSYS_VERSION"; \
	else \
		echo "✗ NOT FOUND"; \
		echo "  Please install yosys (≥0.70)"; \
		exit 1; \
	fi
	@echo ""
	@echo -n "Checking z3... "
	@if command -v z3 >/dev/null 2>&1; then \
		echo "✓ found: $$(command -v z3)"; \
		Z3_VERSION=$$(z3 --version | awk '{print $$3}'); \
		Z3_MAJOR=$$((10#$$(echo $$Z3_VERSION | cut -d. -f1))); \
		if [ "$$Z3_MAJOR" -lt 5 ]; then \
			echo "  ✗ Too old (need ≥5.0): make build-z3"; \
			exit 1; \
		fi; \
		echo "  Version: $$Z3_VERSION"; \
	else \
		echo "✗ NOT FOUND"; \
		echo "  Please install z3 (≥5.0)"; \
		exit 1; \
	fi
	@echo ""
	@echo -n "Checking verilator... "
	@if command -v verilator >/dev/null 2>&1; then \
		echo "✓ found: $$(command -v verilator)"; \
		VERILATOR_VERSION=$$(verilator --version | head -n1 | awk '{print $$2}'); \
		echo "  Version: $$VERILATOR_VERSION"; \
		VERILATOR_MAJOR=$$(echo $$VERILATOR_VERSION | cut -d. -f1); \
		VERILATOR_MINOR=$$((10#$$(echo $$VERILATOR_VERSION | cut -d. -f2))); \
		if [ "$$VERILATOR_MAJOR" -eq 5 ] && [ "$$VERILATOR_MINOR" -eq 52 ]; then \
			echo "  ✓ Version is compatible (5.052)"; \
		elif [ "$$VERILATOR_MAJOR" -eq 5 ] && [ "$$VERILATOR_MINOR" -eq 44 ]; then \
			echo "  ✗ 5.044 crashed reproducibly on this repo - rebuild 5.052: make build-verilator"; \
			exit 1; \
		else \
			echo "  ✗ Unsupported Verilator $$VERILATOR_VERSION - use exactly 5.052 (make build-verilator)"; \
			exit 1; \
		fi; \
	else \
		echo "✗ NOT FOUND"; \
		echo "  Please install verilator 5.052 (make build-verilator)"; \
		exit 1; \
	fi
	@echo ""
	@echo "All required tools are available!"
