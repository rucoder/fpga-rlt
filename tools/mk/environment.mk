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
		echo "  Version: $$YOSYS_VERSION"; \
	else \
		echo "✗ NOT FOUND"; \
		echo "  Please install yosys (≥0.40)"; \
		exit 1; \
	fi
	@echo ""
	@echo -n "Checking z3... "
	@if command -v z3 >/dev/null 2>&1; then \
		echo "✓ found: $$(command -v z3)"; \
		Z3_VERSION=$$(z3 --version | awk '{print $$3}'); \
		echo "  Version: $$Z3_VERSION"; \
	else \
		echo "✗ NOT FOUND"; \
		echo "  Please install z3 (≥4.8)"; \
		exit 1; \
	fi
	@echo ""
	@echo -n "Checking verilator... "
	@if command -v verilator >/dev/null 2>&1; then \
		echo "✓ found: $$(command -v verilator)"; \
		VERILATOR_VERSION=$$(verilator --version | head -n1 | awk '{print $$2}'); \
		echo "  Version: $$VERILATOR_VERSION"; \
		VERILATOR_MAJOR=$$(echo $$VERILATOR_VERSION | cut -d. -f1); \
		VERILATOR_MINOR=$$(echo $$VERILATOR_VERSION | cut -d. -f2); \
		if [ "$$VERILATOR_MAJOR" -eq 5 ]; then \
			if [ "$$VERILATOR_MINOR" -ge 36 ] && [ "$$VERILATOR_MINOR" -le 42 ]; then \
				echo "  ✓ Version is compatible (5.036-5.042)"; \
			elif [ "$$VERILATOR_MINOR" -eq 44 ]; then \
				echo "  ✗ WARNING: Version 5.044 is known to be buggy!"; \
				echo "  Please use version between 5.036 and 5.042"; \
				exit 1; \
			elif [ "$$VERILATOR_MINOR" -lt 36 ]; then \
				echo "  ✗ WARNING: Version too old (need 5.036+)"; \
				exit 1; \
			else \
				echo "  ⚠ WARNING: Version not tested (recommended: 5.036-5.042)"; \
			fi; \
		else \
			echo "  ⚠ WARNING: Major version $$VERILATOR_MAJOR not tested (recommended: 5.036-5.042)"; \
		fi; \
	else \
		echo "✗ NOT FOUND"; \
		echo "  Please install verilator (version 5.036-5.042)"; \
		exit 1; \
	fi
	@echo ""
	@echo "All required tools are available!"
