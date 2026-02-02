# python.mk - Python virtual environment setup targets

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
	pip install cocotb cocotb-bus cocotb-test && \
	pip install cocotbext-i2c && \
	pip install click && \
	pip install pyyaml
	@echo ""
	@echo "Virtual environment setup complete!"
	@echo "To activate manually:"
	@echo "  fish:  source .venv/bin/activate.fish"
	@echo "  bash:  source .venv/bin/activate"
	@echo "  zsh:   source .venv/bin/activate"
