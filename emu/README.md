# emu: the Electron emulator harness

Two programs built on the Acorn Electron emulation in
[Clock Signal](https://github.com/TomHarte/CLK) (CLK):

- **elkh**: a headless Electron driven by a command script. It runs the scroll demo's
  checks: the soak, the store audit and the timing fingerprint.
- **elkview**: the same machine in a window (SDL2), in real time.

Both use a fork of CLK with the ULA behaviour the demo depends on. Upstream CLK draws
the demo wrongly: the engine changes mode mid-line at exact microseconds, relies on the
width of the start-of-row register and on the timing of 1 MHz RAM accesses, and on the
real chip's 40-column address phase. `machine.hpp` compiles the fork's Electron into
each program with `CLK_HEADLESS` defined, which gives the harness direct access to the
machine's RAM, ROM slots, CPU and ULA state.

| File | |
|---|---|
| `elkh.cpp` | the headless program; its header comment lists every command |
| `elkview.cpp` | the windowed program; its header comment lists every option |
| `machine.hpp` | the shared machine: ROM loading, construction, key names |
| `CMakeLists.txt` | builds CLK's core once (`clkcore`) and links both programs to it |
| `clk/` | the CLK fork (git submodule) |

## Building

```sh
git submodule update --init emu/clk
make emu
```

`make emu` runs `cmake -S emu -B build-emu -DCMAKE_BUILD_TYPE=Release` and
`cmake --build build-emu -j` (and initialises the submodule if it is empty). The
programs are `build-emu/elkh` and `build-emu/elkview`.

To build against another checkout of the fork, name it with `CLK_ROOT`, either through
make or directly:

```sh
make emu CLK_ROOT=/path/to/clk
cmake -S emu -B build-emu -DCLK_ROOT=/path/to/clk && cmake --build build-emu -j
```

Requirements: cmake 3.19 or later, a C++20 compiler and zlib; on macOS, the
Accelerate framework (BLAS), which CLK's audio filters use. `elkview` also needs SDL2
(found through its CMake package, for example after `brew install sdl2`); without it
only `elkh` is built.

## ROMs

The ROM images are not included. Both programs need:

- `os.rom`: the Electron MOS 1.00;
- `basic.rom`: BASIC II.

They are looked up by these names (CLK's catalogue names) in the directory given by
`--rompath` (default: the current directory), then in its subdirectory `Electron/`.
The Makefile and the test scripts use `roms/`, or the directory named by `ELK_ROMS`.

## elkview

```sh
make run_mode1        # the MODE 1 demo
make run_mode2        # the MODE 2 demo
```

These build the demo and run, for example:

```sh
build-emu/elkview --rompath roms --realula --ssd build/mode1/elkscroll_mode1.ssd
```

| Option | |
|---|---|
| `--rompath DIR` | where the ROMs are |
| `--realula` | the real-ULA switch (see below). The demo boots into the real ULA's lead-in schedule either way; without `--realula`, press comma in the demo to select the FPGA ULA's schedule (full stop selects the real one again) |
| `--ssd FILE` | quickload from a DFS disc image: the file `!BOOT` runs (or else the first file) is copied to its load address 2.5 s after start, and `CALL` its execution address is typed. No DFS ROM is needed. It replaces `--type` |
| `--media FILE` | a tape (`.uef`) or disc image to insert, for example with `--type '*RUN\n'` for a tape |
| `--type TEXT` | text to type 2.5 s after start (`\n` is RETURN) |
| `--record DIR` | write each field shown as `DIR/fNNNNN.ppm` |

The window shows h 0-767 of each 1,024 (a pixel per 1/16 µs) and lines 0-287. The
host's keys map onto the Electron's: cursor keys, letters, digits, RETURN, SPACE,
SHIFT, CTRL, ESC, BACKSPACE for DELETE, TAB for FUNC, `-` `;` `,` `.` `/`, `'` or `:`
for COLON, and F12 for BREAK. Close the window to quit.

## elkh

The command line is a script, run left to right. For example, to boot the MODE 1 demo
on the real-ULA model, start it moving and save field 500's picture, fetch addresses,
modes and I/O:

```sh
build-emu/elkh --rompath roms realula 1 boot 2.5 load build/mode1/elkscroll 2000 \
    type 'CALL &2000\n' boot 2 key SPACE down fields 4 key SPACE up \
    fields 500 dump out/f500
```

`load` copies the loader file (which carries the sideways RAM image) to &2000, and
`CALL &2000` runs it; the loader puts the engine in a sideways RAM bank and enters it.
SPACE starts and stops the motion.

The commands, in brief (the header of `elkh.cpp` gives their arguments in full):

| Command | |
|---|---|
| `boot SECS`, `cycles N`, `fields N` | run for emulated seconds, 2 MHz cycles, or fields |
| `type TEXT`, `key NAME down\|up` | type through the OS; press or release a key |
| `load FILE HEXADDR`, `poke`, `peek`, `peekrom` | main RAM and the ROM slots |
| `regs` | the CPU's registers, the field count and the paged slot |
| `dump PREFIX` | the last complete field: `.ppm`, `.addr`, `.mode`, `.io` |
| `iolog N FILE` | every &FExx access of N fields: the timing fingerprint |
| `realula 0\|1` | the ULA model: FPGA (0, the default) or the real-ULA switch (1) |
| `rowreg old\|new` | the start-of-row register: every bit (old, upstream CLK) or bits 14..6 (new, the default) |
| `soak N MODEL OUT WXADDR GCHADDR` | N fields, each checked (below) |
| `audit`, `auditdump FILE` | the store audit (below) |
| `race N` | screen stores against the same field's display fetches of those bytes |
| `swatch HEXADDR N` | every store to one sideways RAM address over N fields, with its raster position |

### The soak

`soak` runs N fields and checks every one:

- **The picture.** Every pixel of the window must match the pattern model
  (`gen/model.bin`, written by `tools/gen.py`) at the position the program held for
  that field, read from its `wx` variable (WXADDR, from `elk.lbl`). Wherever the window
  fetches the leak byte, &7E07, the pixel must be black (see below). Nothing may be lit
  outside the window, on lines 0-255.
- **The lock.** The window's exit, the first write of MODE 4 to &FE07 on or below the
  window's first line, must land at line Y1 (the line after the window) at h 120
  exactly, and the lock read must be on line 0. The lock read is a main-RAM read, which
  the I/O log does not record, so its position is taken from a status read the program
  makes just before it as a marker.
- **The variable work's end** (a status-read marker in `frame.s`) must come before line
  255, display end in MODE 4; otherwise the field is counted as late.
- **The pad and blip audit.** No non-zero byte may be fetched in a 40-column mode on a
  window line: in the lead-in ("pad") or in the right margin ("blip").

It writes `OUT.rec` (8 bytes a field: position, the characters the vertical step drew,
flags, the variable work's end line), dumps the first three wrong fields as
`OUT_badK.*`, and prints a summary line:

```
soak: 2000 fields, 0 bad, 0 unlocked, 0 late, 0 pad, 0 blip; variable work ended by line 217; lock read h 152..328
```

`audit`, from the point it is given, logs main-RAM stores outside the screen ring
(&3000-&7FFF), the stack, the key bytes (&0A00-&0A02) and the dummy page (&2400-&24FF);
non-zero stores to &7E07 on lines 29-199, while the window's mode writes can show it;
and counts sideways RAM stores by address. `auditdump FILE` writes the counts and
prints its summary line.

`test/soak1.sh` runs one soak under the audit; `test/soak.sh` runs many, both window
modes and both ULA models (`make test`). `test/fingerprint.sh` records an `iolog`, for
checking that a change leaves every ULA access where it was.

## The ULA models

`realula 1` (elkview `--realula`) sets the fork's `Electron::VideoOutput::real_m5_phase`.
It changes two things together:

- **The 40-column address phase.** In MODEs 4-7 the address counter steps in the first
  half of each microsecond, as measured with probe programs on a Ferranti (issue 6)
  Electron, instead of the second half, as in hoglet's ElectronFpga HDL and JamSoft's
  model.
- **Mode value 7 wraps to &3000.** Mode value 7 (&FE07 bits 3-5 = 7, undocumented)
  displays like MODE 4 but wraps the address at &8000 to &3000. This is the Synertek
  ULA's behaviour. A Ferranti ULA treats mode value 7 as plain MODE 4, wrapping to
  &5800. With the switch off, the fork wraps mode value 7 to &5800.

So the switch is not a model of either chip: it combines the Ferranti's phase, which
has been measured, with the Synertek's wrap, and whether Synertek ULAs share the
Ferranti's phase has not been measured. In particular it does not reproduce the
failure on Ferranti ULAs: with the real schedule's 8 µs lead-in, the row whose ring row
starts at &7FC0 takes its eighth 40-column step across &8000, which a Ferranti sends to
&5800, so that row is shown wrongly whenever t = 7 on the real schedule. In the emulator the
switch sends it to &3000 and the row is right. (`docs/DESIGN.md`, "Two ULAs: the
schedules"; `docs/ULA-NOTES.md`, "Later findings: the real (Ferranti) ULA".)

## The fork

The fork is [ebenupton/CLK, branch `elk-headless`](https://github.com/ebenupton/CLK/tree/elk-headless):
upstream CLK (at TomHarte/CLK pull request #1880, "Improve deferred queue") plus three
commits, all in `Machines/Acorn/Electron` apart from a one-line change to
`Numeric/CubicCurve.hpp`.

1. **ULA fixes to match the ElectronFpga HDL, and the capture**
   (`docs/ULA-NOTES.md`, "Recommended CLK patches"):
   - the start-of-row register holds address bits 14..6 only (`row_register_14_6`,
     on by default; elkh `rowreg old` restores upstream's behaviour);
   - the screen wrap's mask, written as a hex literal where binary was meant, corrected;
   - every RAM access is a 1 MHz access, stopped and released like an I/O access; in
     MODEs 0-3 the release waits for the end of the line's fetches only when it falls
     inside them;
   - &FC00-&FEFF, and the keyboard (paged into &8000-&BFFF), are accessed at 1 MHz;
   - &FE05 pages on every write, honouring only values with bit 3 set while slot 8-11
     is selected; a keyboard read's high nibble is 0;
   - the RTC interrupt timed as in the real-chip logic-analyser captures (about 15
     ticks of 1/16 µs earlier than the FPGA's);
   - under `CLK_HEADLESS`: the machine's and the ULA's internals public, and a capture
     of each field (a pixel per 1/16 µs as 3-bit RGB, the address fetched and the mode
     in force in each 0.5 µs slot, and every &FExx access with its raster position);
   - `Numeric/CubicCurve.hpp`: two member initialisers changed from parentheses to
     braces.
2. **A count of &8000-&BFFF bus cycles**, split at a chosen line (`count_from_line`,
   200), for profiling.
3. **The real-ULA switch, the pad audit and bus hooks:**
   - `real_m5_phase` (off by default): the Ferranti's 40-column address phase, and mode
     value 7 wrapping to &3000 (above);
   - the pad audit in the capture: per line, the non-zero bytes fetched in a
     40-column mode in the display, in each half of the line, with the first one's
     position, address and byte;
   - under `CLK_HEADLESS`, hooks: an OS-call trap on opcode fetches at &FFxx, every
     opcode fetch, every main-RAM bus cycle, main-RAM stores and sideways RAM stores.

The fork's own changes are marked "elk-headless" in its comments.

## What the emulator does not model

- **The leak byte.** On a real ULA a CPU write to a ULA register while the ULA is
  fetching for the display takes that video slot, which shows RAM[&7E00 + the
  address's low byte] in place of its own byte: for &FE07, RAM[&7E07]. Neither the fork
  nor the ElectronFpga HDL models this. The demo keeps &7E07 zero, so on hardware the
  slot is black; the soak expects black wherever the window fetches &7E07, and the
  audit reports any non-zero store to it on lines 29-199.
  (`docs/DESIGN.md`, "The leak byte: what a mid-line ULA write shows".)
- **The Ferranti ULA's mode value 7.** As above, the real-ULA switch wraps mode value 7
  to &3000, the Synertek's behaviour, so the Ferranti's failure on the &7FC0 row (lead-in
  t = 7 on the real schedule) does not appear in the emulator.
