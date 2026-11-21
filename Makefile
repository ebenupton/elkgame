# elkgame: the Electron scroll demo.
#
#   make, make all       both demos: build/mode1/elkscroll_mode1.ssd/.uef (MODE 1 window)
#                        and build/mode2/elkscroll_mode2.ssd/.uef (MODE 2 window)
#   make elkscroll_mode1, make elkscroll_mode2
#                        one of the two, in BUILD/mode1 or BUILD/mode2
#   make one             one demo, directly in BUILD, in the mode SCRMODE says (1 or 2):
#                        BUILD/elkscroll_mode1 or _mode2 .ssd/.uef
#   make bin             both, then copies the four images into bin/ (the prebuilt
#                        binaries committed to the repository)
#   make emu             the emulator harness: build-emu/elkh and build-emu/elkview
#                        (CLK_ROOT=dir: build against that checkout of the CLK fork)
#   make test            both demos, then test/soak.sh -n 5000 (8 runs: both window
#                        modes, both ULA models; needs make emu and the ROMs, README)
#   make run_mode1, make run_mode2
#                        the MODE 1 or MODE 2 demo in elkview on the real ULA model
#                        (ROMs from ELK_ROMS, default ./roms)
#   make clean           removes BUILD (the emulator's build, in build-emu, stays)
#
# Options for the assembler (each passed to ca65 as -D NAME=VALUE; defaults in
# src/init.s):
#   START_WX, START_WY   the map position at start (default 1283, 1280; START_WY even)
#   TRAJ=1               a random walk (seeded by SEED) instead of the demo script
#   SEED                 the random walk's seed (default &ACE1)
#   MOTION=1             moving from the start (else SPACE starts and stops it)
#   SCHED=0              boot into the FPGA ULA's lead-in schedule (default 8: the real
#                        ULA's; comma and full stop switch between them while running)
# and one for tools/gen.py, not the assembler:
#   SCRMODE=2            the MODE 2 window (16 colours, 112 x 170 pixels).  Only make one
#                        reads it: all and the two image targets set it themselves.
# e.g.  make one BUILD=build/rw TRAJ=1 SEED=4321
#
# BUILD may be any directory.  The demo needs python3, ca65 and ld65 (cc65); the
# emulator needs cmake, a C++20 compiler, zlib and (for elkview) SDL2.

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

# The generated source (config.inc, gen_tables.s, gen_variants.s, gen_loop2.s) and
# the soak's pattern model (model.bin), all from one run of gen.py.
$(GEN)/stamp: tools/gen.py tools/swatch35.py $(BUILD)/defines
	SCRMODE=$(SCRMODE) $(PYTHON) tools/gen.py $(GEN)
	@touch $@

# The sideways RAM image (elk.bin) and, from the same link, the keyboard routine
# (kbd.bin), the labels (elk.lbl, which test/soak1.sh reads) and the debug file
# (elk.dbg, which tools/pagecheck.py reads).  ld65 runs in $(BUILD) because
# cfg/elk.cfg names its two output files without a directory.
$(BUILD)/elk.bin: $(SRC) $(GEN)/stamp cfg/elk.cfg $(BUILD)/defines Makefile
	$(CA65) -g -I src -I $(GEN) $(DEFINES) -l $(BUILD)/elk.lst -o $(BUILD)/elk.o src/elkscroll.s
	cd $(BUILD) && $(LD65) -C $(abspath cfg/elk.cfg) -m elk.map -Ln elk.lbl --dbgfile elk.dbg -o /dev/null elk.o

# The program: the loader (src/loader.s) with elk.bin and kbd.bin included, one file
# loaded and run at &2000.
$(BUILD)/elkscroll: src/loader.s cfg/loader.cfg $(BUILD)/elk.bin
	$(CA65) --bin-include-dir $(BUILD) -o $(BUILD)/loader.o src/loader.s
	$(LD65) -C cfg/loader.cfg -o $@ $(BUILD)/loader.o

$(BUILD)/$(IMG).ssd: $(BUILD)/elkscroll tools/mkimages.py
	$(PYTHON) tools/mkimages.py $< $(BUILD) $(IMG)

# Rebuild when the options change: BUILD/defines is rewritten only when they differ.
$(BUILD)/defines: FORCE
	@mkdir -p $(BUILD)
	@echo '$(DEFINES) SCRMODE=$(SCRMODE)' | cmp -s - $@ || echo '$(DEFINES) SCRMODE=$(SCRMODE)' > $@
FORCE:

# ---- the emulator (emu/README.md) ----------------------------------------------------
emu:
	@test -n "$(CLK_ROOT)" || test -f emu/clk/cmake/CLK_SOURCES.cmake || git submodule update --init emu/clk
	cmake -S emu -B $(EMUBUILD) -DCMAKE_BUILD_TYPE=Release $(if $(CLK_ROOT),-DCLK_ROOT=$(abspath $(CLK_ROOT)))
	cmake --build $(EMUBUILD) -j

test: all
	test/soak.sh -n 5000

run_mode1: elkscroll_mode1
	$(EMUBUILD)/elkview --rompath $(or $(ELK_ROMS),roms) --realula --ssd $(BUILD)/mode1/elkscroll_mode1.ssd

run_mode2: elkscroll_mode2
	$(EMUBUILD)/elkview --rompath $(or $(ELK_ROMS),roms) --realula --ssd $(BUILD)/mode2/elkscroll_mode2.ssd

clean:
	rm -rf $(BUILD)
