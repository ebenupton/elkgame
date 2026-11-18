# emu: the Electron emulator harness

Two programs on [Clock Signal](https://github.com/TomHarte/CLK)'s Acorn Electron
core:

- **elkh**: headless, driven by a command script. It runs the demo's checks.
- **elkview**: the same machine in a window.

Stock emulators, Clock Signal included, cannot show the scroll demo properly. It
relies on details of the ULA (the start-of-row register's width, 1 MHz RAM slots,
mid-line mode changes, the real chip's address phase) that none of them modelled. The
core is built from a fork with those details, a git submodule at `emu/clk`:
[ebenupton/CLK, branch `elk-headless`](https://github.com/ebenupton/CLK/tree/elk-headless).
It is upstream CLK plus three commits:

1. **ULA fixes to match hoglet's ElectronFpga HDL** (`docs/ULA-NOTES.md` section 13):
   - the start-of-row register holds address bits 14..6 only;
   - RAM accesses are 1 MHz slots, contended only when the release falls in the
     fetch;
   - &FC00–&FDFF and keyboard reads at 1 MHz;
   - &FE05 paging on every write;
   - the RTC event's timing;
   - and, under `CLK_HEADLESS`, a per-field capture of pixels, fetch addresses, modes
     and every &FExx access with its raster position.
2. A count of sideways RAM bus cycles by line (for profiling).
3. **The real (Ferranti) ULA's 40-column address phase and mode 7 wrap** behind a
   switch (`real_m5_phase`); the pad audit in the capture; and bus hooks: OS-call
   trap, opcode fetches, RAM stores.

## Building

```sh
git submodule update --init emu/clk
make emu            # = cmake -S emu -B build-emu && cmake --build build-emu -j
```

This needs cmake 3.19+, a C++20 compiler and zlib. `elkview` also needs SDL2
(`brew install sdl2`); it is skipped without it. The build compiles CLK's core once
(`clkcore`) and links both programs against it.

Both programs need the Electron's ROMs, which are not included: `os.rom` (MOS 1.00)
and `basic.rom` (BASIC II), in the directory given by `--rompath` (or a subdirectory
`Electron/` of it). The tests look in `roms/` or `$ELK_ROMS`.

## elkview

```sh
build-emu/elkview --rompath roms --realula --ssd build/elkscroll.ssd
```

| Option | |
|---|---|
| `--realula` | the real ULA (the demo boots into its schedule; without this, press comma in the demo) |
| `--ssd FILE` | quickload: puts the file `!BOOT` runs at its load address and CALLs it once the OS is up (no DFS ROM needed) |
| `--media FILE --type '*RUN\n'` | load a tape through the OS instead |
| `--record DIR` | write every field as a PPM |

Keys map to the Electron's: cursor keys, letters, digits, RETURN, SPACE, SHIFT, CTRL,
ESC, `'` or `:` for COLON, F12 for BREAK.

## elkh

A command line is a script, run in order, for example:

```sh
build-emu/elkh --rompath roms realula 1 boot 2.5 load build/elkscroll 2000 \
    type 'CALL &2000\n' boot 2 key SPACE down fields 4 key SPACE up \
    fields 500 dump out/f500
```

The file's header comment (`elkh.cpp`) lists every command. These are the ones the
tests use:

- `soak N MODEL OUT WX GCH`: checks every field against the pattern model and the
  frame's timing (`test/soak1.sh`).
- `audit` / `auditdump`: stray stores.
- `race N`: screen stores against the display's fetches of the same bytes.
- `iolog N FILE`: the timing fingerprint (`test/fingerprint.sh`).
- `dump PREFIX`: one field's picture, fetch addresses, modes and I/O.
- `swatch ADDR N`: every store to one sideways RAM address over N fields, with its
  raster position (for following a variable).
