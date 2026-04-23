# SystemVerilog Project Makefile

# Simulator (change to your preferred simulator: vcs, modelsim, xcelium, etc.)
SIM ?= iverilog
VIEWER ?= gtkwave

# Directories
SRC_DIR := src
TEST_DIR := test
BUILD_DIR := build
LOG_DIR := logs

# Find all source and testbench files
SRC_FILES := $(wildcard $(SRC_DIR)/*.sv)
TB_FILES := $(wildcard $(TEST_DIR)/*_testbench.sv)

# Extract module names from testbench files
# Assumes testbenches are named [module]_testbench.sv
MODULES := $(patsubst $(TEST_DIR)/%_testbench.sv,%,$(TB_FILES))

# Default target
.PHONY: all
all: help

# Create necessary directories
$(BUILD_DIR) $(LOG_DIR):
	@mkdir -p $@

# Help target
.PHONY: help
help:
	@echo "SystemVerilog Project Makefile"
	@echo "=============================="
	@echo "Available targets:"
	@echo "  make sim MODULE=<name>  - Simulate a specific module"
	@echo "  make wave MODULE=<name> - View waveform for a module"
	@echo "  make all-sims           - Run all testbenches"
	@echo "  make clean              - Remove build and log files"
	@echo "  make list               - List all available modules"
	@echo ""
	@echo "Available modules:"
	@$(foreach mod,$(MODULES),echo "  - $(mod)";)

# List all modules
.PHONY: list
list:
	@echo "Available modules for simulation:"
	@$(foreach mod,$(MODULES),echo "  - $(mod)";)

# Top-level module needs all source files (it instantiates all submodules)
ifeq ($(MODULE),top)
MODULE_SRC := $(SRC_FILES)
else
MODULE_SRC := $(SRC_DIR)/$(MODULE).sv
endif

# Simulation target for individual modules
.PHONY: sim
sim: | $(BUILD_DIR) $(LOG_DIR)
ifndef MODULE
	@echo "Error: Please specify MODULE=<name>"
	@echo "Available modules: $(MODULES)"
	@exit 1
endif
	@echo "Simulating $(MODULE)..."
ifeq ($(SIM),iverilog)
	iverilog -g2012 -o $(BUILD_DIR)/$(MODULE).vvp \
		$(MODULE_SRC) \
		$(TEST_DIR)/$(MODULE)_testbench.sv \
		2>&1 | tee $(LOG_DIR)/$(MODULE)_compile.log
	vvp $(BUILD_DIR)/$(MODULE).vvp 2>&1 | tee $(LOG_DIR)/$(MODULE)_sim.log
	@if [ -f dump.vcd ]; then mv dump.vcd $(BUILD_DIR)/$(MODULE).vcd; fi
else ifeq ($(SIM),vcs)
	vcs -full64 -sverilog +v2k -timescale=1ns/1ps \
		-debug_access+all \
		-o $(BUILD_DIR)/$(MODULE).simv \
		$(MODULE_SRC) \
		$(TEST_DIR)/$(MODULE)_testbench.sv \
		2>&1 | tee $(LOG_DIR)/$(MODULE)_compile.log
	$(BUILD_DIR)/$(MODULE).simv 2>&1 | tee $(LOG_DIR)/$(MODULE)_sim.log
else ifeq ($(SIM),xcelium)
	xrun -64bit -sv -access +rwc \
		-timescale 1ns/1ps \
		$(MODULE_SRC) \
		$(TEST_DIR)/$(MODULE)_testbench.sv \
		-l $(LOG_DIR)/$(MODULE)_sim.log
else
	@echo "Error: Unsupported simulator $(SIM)"
	@echo "Supported: iverilog, vcs, xcelium"
	@exit 1
endif
	@echo "Simulation complete for $(MODULE)"

# View waveform
.PHONY: wave
wave:
ifndef MODULE
	@echo "Error: Please specify MODULE=<name>"
	@exit 1
endif
	@if [ -f $(BUILD_DIR)/$(MODULE).vcd ]; then \
		$(VIEWER) $(BUILD_DIR)/$(MODULE).vcd; \
	elif [ -f $(BUILD_DIR)/$(MODULE).fsdb ]; then \
		verdi -ssf $(BUILD_DIR)/$(MODULE).fsdb; \
	else \
		echo "Error: No waveform file found for $(MODULE)"; \
		exit 1; \
	fi

# Run all simulations
.PHONY: all-sims
all-sims: | $(BUILD_DIR) $(LOG_DIR)
	@echo "Running all testbenches..."
	@$(foreach mod,$(MODULES), \
		echo "=== Simulating $(mod) ==="; \
		$(MAKE) sim MODULE=$(mod) || exit 1; \
	)
	@echo "All simulations complete!"

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR) $(LOG_DIR)
	rm -f *.vcd *.vvp *.log
	rm -rf csrc simv.daidir ucli.key
	rm -f *.fsdb *.vpd
	@echo "Clean complete"

# Deep clean (including simulator caches)
.PHONY: distclean
distclean: clean
	rm -rf DVEfiles
	rm -rf urgReport
	rm -rf AN.DB
	rm -f .vlogansetup.*
	rm -f *.prof

.PHONY: info
info:
	@echo "Project Structure:"
	@echo "  Source files: $(SRC_DIR)/"
	@echo "  Testbenches:  $(TEST_DIR)/"
	@echo "  Build output: $(BUILD_DIR)/"
	@echo "  Log files:    $(LOG_DIR)/"
	@echo ""
	@echo "Simulator: $(SIM)"
	@echo "Waveform viewer: $(VIEWER)"
	@echo ""
	@echo "Found $(words $(MODULES)) module(s):"
	@$(foreach mod,$(MODULES),echo "  - $(mod)";)