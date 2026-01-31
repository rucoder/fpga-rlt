# source ~/.local/oss-cad/env.sh

export OSSCAD := $(HOME)/.local/oss-cad
export PATH := $(OSSCAD)/bin:$(PATH)

VERILATOR_OUT_DIR:=build/verilator

VERILATOR_OPTS_COMMON:=--Wall --timing --trace -cc \
	-exe --binary --build-jobs $(nproc) --build -O3 \
	-sv --Mdir $(VERILATOR_OUT_DIR)

#helper function to convert - targets to _ e.g. sim-tick-div -> sim_tick_div
dash-to-underscore = $(subst -,_,$1)

.SECONDEXPANSION:

# pattern rules to build individual test benches
.PHONY: sim-%
sim-%: $$(VERILATOR_OUT_DIR)/sim_$$(call dash-to-underscore,$$*)
	$(eval MODULE := $(call dash-to-underscore,$*))
	./$(VERILATOR_OUT_DIR)/sim_$(MODULE)

$(VERILATOR_OUT_DIR)/sim_%: sim/tb_$$(call dash-to-underscore,$$*).sv rtl/$$(call dash-to-underscore,$$*).sv
	$(eval MODULE := $(call dash-to-underscore,$*))
	@mkdir -p $(VERILATOR_OUT_DIR)
	verilator $(VERILATOR_OPTS_COMMON) \
    --top-module tb_$(MODULE) sim/tb_$(MODULE).sv  rtl/$(MODULE).sv \
    -o sim_$(MODULE)

# SBY formal verification targets
sby-%: formal/$$(call dash-to-underscore,$$*).sby rtl/$$(call dash-to-underscore,$$*).sv
	$(eval MODULE := $(call dash-to-underscore,$*))
	@mkdir -p build/formal
	sby -f -d build/formal/$(MODULE) formal/$(MODULE).sby

.PHONY: clean
clean:
	rm -rf $(VERILATOR_OUT_DIR)/*
