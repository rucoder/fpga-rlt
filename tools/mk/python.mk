# python.mk - Python virtual environment setup targets
# Python deps are pinned like the rest of the toolchain (see tools/mk/
# toolchain.mk): a fresh `make venv-setup` must reproduce this exact stack.
# To upgrade: bump the pins, rerun venv-setup (or pip install -U '<pkg>==<ver>').

.PHONY: venv-setup
venv-setup:
	@echo "Setting up Python virtual environment..."
	python3 -m venv .venv
	@echo "Installing Python dependencies..."
	@if [ -n "$$FISH_VERSION" ]; then \
		. .venv/bin/activate.fish; \
	else \
		. .venv/bin/activate; \
	fi && \
	pip install -U pip && \
	pip install cocotb==2.1.0 cocotb-bus==0.3.0 cocotb-test==0.2.6 && \
	pip install cocotbext-i2c==0.1.2 && \
	pip install click==8.3.1 && \
	pip install pyyaml==6.0.3
	@echo ""
	@echo "Virtual environment setup complete!"
	@echo "To activate manually:"
	@echo "  fish:  source .venv/bin/activate.fish"
	@echo "  bash:  source .venv/bin/activate"
	@echo "  zsh:   source .venv/bin/activate"
