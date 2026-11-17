# elkgame: the Electron scroll demo.
#
#   make                 build/elkscroll.ssd and .uef (and everything they need)
#   make emu             the emulator harness: build-emu/elkh and build-emu/elkview
#   make test            a short soak of both ULA models in elkh (needs ROMs: README)
#   make run             the demo in elkview, in a window
#   make clean           (the demo's build only; the emulator's is in build-emu)
#
# Options (each is passed to ca65 as -D NAME=VALUE; the defaults are in src/init.s):
#   START_WX, START_WY   the map position at start (START_WY even)
#   TRAJ=1               a random walk (seeded by SEED) instead of the script
#   SEED                 the random walk's seed
# e.g.  make BUILD=build/rw TRAJ=1 SEED=4321
#
# BUILD may be any directory; tools need python3, ca65 and ld65 (cc65), and for the
# emulator cmake, a C++20 compiler, zlib and (for elkview) SDL2.

BUILD   ?= build
GEN     := $(BUILD)/gen
PYTHON  ?= python3
CA65    ?= ca65
LD65    ?= ld65

DEFINES := $(foreach v,START_WX START_WY TRAJ SEED,$(if $($(v)),-D $(v)=$($(v))))

SRC     := $(wildcard src/*.s src/*.inc)
EMUBUILD ?= build-emu

.PHONY: all emu test run clean
all: $(BUILD)/elkscroll.ssd

# config.inc, gen_tables.s, gen_variants.s, gen_snips.s and model.bin, all at once.
$(GEN)/stamp: tools/gen.py tools/swatch35.py
	$(PYTHON) tools/gen.py $(GEN)
	@touch $@

# The sideways RAM image (elk.bin) and, from the same link, the keyboard routine
# (kbd.bin) and the labels (elk.lbl, which the tests read).  ld65 runs in $(BUILD)
# because the configuration names two output files.
$(BUILD)/elk.bin: $(SRC) $(GEN)/stamp cfg/elk.cfg $(BUILD)/defines
	$(CA65) -g -I src -I $(GEN) $(DEFINES) -l $(BUILD)/elk.lst -o $(BUILD)/elk.o src/elkscroll.s
	cd $(BUILD) && $(LD65) -C $(abspath cfg/elk.cfg) -m elk.map -Ln elk.lbl -o /dev/null elk.o

# The loader carries both into one file, loaded and run at &2000.
$(BUILD)/elkscroll: src/loader.s cfg/loader.cfg $(BUILD)/elk.bin
	$(CA65) --bin-include-dir $(BUILD) -o $(BUILD)/loader.o src/loader.s
	$(LD65) -C cfg/loader.cfg -o $@ $(BUILD)/loader.o

$(BUILD)/elkscroll.ssd: $(BUILD)/elkscroll tools/mkimages.py
	$(PYTHON) tools/mkimages.py $< $(BUILD)

# Rebuild when the options change.
$(BUILD)/defines: FORCE
	@mkdir -p $(BUILD)
	@echo '$(DEFINES)' | cmp -s - $@ || echo '$(DEFINES)' > $@
FORCE:

# ---- the emulator (emu/README.md) ----------------------------------------------------
emu:
	@test -f emu/clk/CMakeLists.txt || git submodule update --init emu/clk
	cmake -S emu -B $(EMUBUILD) -DCMAKE_BUILD_TYPE=Release
	cmake --build $(EMUBUILD) -j

test: all
	test/soak.sh -n 5000

run: all
	$(EMUBUILD)/elkview --rompath $(or $(ELK_ROMS),roms) --realula --ssd $(BUILD)/elkscroll.ssd

clean:
	rm -rf $(BUILD)
