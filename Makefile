# elkgame: the Electron scroll demo.
#
#   make                 both demos: build/elkscroll.ssd/.uef (MODE 1) and
#                        build/mode2/elkscroll2.ssd/.uef (MODE 2)
#   make one             one demo, in BUILD, as SCRMODE says (1 or 2)
#   make emu             the emulator harness: build-emu/elkh and build-emu/elkview
#   make test            a short soak of both ULA models in elkh (needs ROMs: README)
#   make run, make run2  the MODE 1 or MODE 2 demo in elkview, in a window
#   make clean           (the demo's build only; the emulator's is in build-emu)
#
# Options (each is passed to ca65 as -D NAME=VALUE; the defaults are in src/init.s):
#   START_WX, START_WY   the map position at start (START_WY even)
#   TRAJ=1               a random walk (seeded by SEED) instead of the script
#   SEED                 the random walk's seed
#   MOTION=1             moving from the start (else SPACE starts and stops it)
#   SCHED=0              boot into the FPGA ULA's lead-in schedule (default 8: the real ULA's)
#   LOCK1=1              lock with one read, in line 0: a line (128 cycles) more free time
#                        above the window, about half the lock's margin (DESIGN.md 3.1)
#   SCRMODE=2            the MODE 2 window (16 colours, 112 x 170 pixels; gen.py)
# e.g.  make BUILD=build/rw TRAJ=1 SEED=4321
#
# BUILD may be any directory; tools need python3, ca65 and ld65 (cc65), and for the
# emulator cmake, a C++20 compiler, zlib and (for elkview) SDL2.

BUILD   ?= build
GEN     := $(BUILD)/gen
PYTHON  ?= python3
SCRMODE ?= 1
CA65    ?= ca65
LD65    ?= ld65

DEFINES := $(foreach v,START_WX START_WY TRAJ SEED MOTION SCHED,$(if $($(v)),-D $(v)=$($(v))))

SRC     := $(wildcard src/*.s src/*.inc)
EMUBUILD ?= build-emu

IMG     := elkscroll_mode$(SCRMODE)

.PHONY: all elkscroll_mode1 elkscroll_mode2 one bin emu test run_mode1 run_mode2 clean
all: elkscroll_mode1 elkscroll_mode2
elkscroll_mode1:
	@$(MAKE) --no-print-directory one SCRMODE=1 BUILD=$(BUILD)/mode1
elkscroll_mode2:
	@$(MAKE) --no-print-directory one SCRMODE=2 BUILD=$(BUILD)/mode2
one: $(BUILD)/$(IMG).ssd

# The prebuilt images in bin/, from a default build of both.
bin: all
	@mkdir -p bin
	cp $(BUILD)/mode1/elkscroll_mode1.ssd $(BUILD)/mode1/elkscroll_mode1.uef bin/
	cp $(BUILD)/mode2/elkscroll_mode2.ssd $(BUILD)/mode2/elkscroll_mode2.uef bin/

# config.inc, gen_tables.s, gen_variants.s and model.bin, all at once.
$(GEN)/stamp: tools/gen.py tools/swatch35.py $(BUILD)/defines
	SCRMODE=$(SCRMODE) $(PYTHON) tools/gen.py $(GEN)
	@touch $@

# The sideways RAM image (elk.bin) and, from the same link, the keyboard routine
# (kbd.bin) and the labels (elk.lbl, which the tests read).  ld65 runs in $(BUILD)
# because the configuration names two output files.
$(BUILD)/elk.bin: $(SRC) $(GEN)/stamp cfg/elk.cfg $(BUILD)/defines Makefile
	$(CA65) -g -I src -I $(GEN) $(DEFINES) -l $(BUILD)/elk.lst -o $(BUILD)/elk.o src/elkscroll.s
	cd $(BUILD) && $(LD65) -C $(abspath cfg/elk.cfg) -m elk.map -Ln elk.lbl --dbgfile elk.dbg -o /dev/null elk.o

# The loader carries both into one file, loaded and run at &2000.
$(BUILD)/elkscroll: src/loader.s cfg/loader.cfg $(BUILD)/elk.bin
	$(CA65) --bin-include-dir $(BUILD) -o $(BUILD)/loader.o src/loader.s
	$(LD65) -C cfg/loader.cfg -o $@ $(BUILD)/loader.o

$(BUILD)/$(IMG).ssd: $(BUILD)/elkscroll tools/mkimages.py
	$(PYTHON) tools/mkimages.py $< $(BUILD) $(IMG)

# Rebuild when the options change.
$(BUILD)/defines: FORCE
	@mkdir -p $(BUILD)
	@echo '$(DEFINES) SCRMODE=$(SCRMODE)' | cmp -s - $@ || echo '$(DEFINES) SCRMODE=$(SCRMODE)' > $@
FORCE:

# ---- the emulator (emu/README.md) ----------------------------------------------------
emu:
	@test -f emu/clk/CMakeLists.txt || git submodule update --init emu/clk
	cmake -S emu -B $(EMUBUILD) -DCMAKE_BUILD_TYPE=Release
	cmake --build $(EMUBUILD) -j

test: all
	test/soak.sh -n 5000

run_mode1: elkscroll_mode1
	$(EMUBUILD)/elkview --rompath $(or $(ELK_ROMS),roms) --realula --ssd $(BUILD)/mode1/elkscroll_mode1.ssd

run_mode2: elkscroll_mode2
	$(EMUBUILD)/elkview --rompath $(or $(ELK_ROMS),roms) --realula --ssd $(BUILD)/mode2/elkscroll_mode2.ssd

clean:
	rm -rf $(BUILD)
