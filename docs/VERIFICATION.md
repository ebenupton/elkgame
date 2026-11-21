# Verification

How the scroll engine is checked, what the checks have found, and what is not yet
known.

## 1. The emulator

All checks run on Clock Signal's Electron core, from the fork in `emu/clk`
(`emu/README.md`), corrected in two steps:

1. **To match hoglet's ElectronFpga HDL** in everything the engine relies on
   (`ULA-NOTES.md` section 13). Before the fixes, CLK drew the engine's picture
   wrongly. The fixed core was checked against an nvc simulation of the unmodified
   HDL, running an earlier version of the scroll test. Every &FExx write and status
   read landed at the same raster position in both, apart from a constant 0.5 µs: the
   CPU/video phase (`ULA-NOTES.md`; DESIGN.md 4.4).
2. **To match the real (Ferranti) ULA** where probe programs on an issue 6 Electron
   showed it differs from the HDL (`ULA-NOTES.md` section 15). This is a switch: elkh
   `realula 1`, elkview `--realula`. With it on, the emulator reproduced the probes as
   photographed.

## 2. What a soak checks

`test/soak.sh` runs `test/soak1.sh` over a deterministic set of cases, in both window
modes (`-s` picks one):
- start positions and random-walk seeds spread over the map, including its seams;
- the demo script every seventh run;
- the real-ULA model and schedule on odd runs, the FPGA model and schedule on even
  ones.

For **every field**, elkh's `soak` checks:

| Check | Pass condition |
|---|---|
| picture | every pixel of the window equals the pattern model (`tools/gen.py`, exported as `model.bin`) at the position the program holds for that field, and no pixel outside the window is lit |
| lock | the window's exit write (MODE 4) lands at exactly line 200, h 120, and the lock read stalls in line 0 |
| deadline | the variable-length work ends before line 255 (display end) |
| pad | no non-zero byte is fetched in a 40-column mode on a window line: "pad" in the lead-in, "blip" at the right edge. Either would show on hardware whose phase differs from the emulator's, even if the emulated picture is right |

Over the whole run, the store audit checks:
- no store to main RAM outside the screen ring, the stack, the key bytes and the
  dummy page;
- the set of sideways RAM addresses written stays the same.

`elkh race N` measures, for every screen store, how close the display's fetch of the
same byte comes. On this build nothing comes closer than 9.5 µs: stores behind the
beam land at least 9.5 µs after the fetch, and stores ahead of it at least 16 µs
before.

**Negative controls.** The checks do catch errors:
- The real-ULA schedule on the FPGA model (no comma): every field is wrong (300 of
  300).
- CLK's original start-of-row register (`rowreg old`): every field is wrong and the
  pad audit fires in every one.

## 3. Timing equivalence of two builds

A change to the code can shift timing without making any field wrong at the phase
the emulator models. `test/fingerprint.sh` records every &FExx access of every field,
with its raster position, for a build moving under no external input (`MOTION=1`,
`SCHED` set). `test/fpcompare.py` compares two such records per field:
- **picture**: the picture's mode and palette writes, which must be identical;
- **fixed**: the length of the fixed work below the window;
- **lock**: where the lock read lands.

This is how the cleanup of this repository was checked (section 4).
`test/fpmarkers.py` splits one fingerprint's fixed work into its sections (the edge
rows and the strip build) by the marker reads, for calibrating a change.  For following
one variable through a field, `elkh swatch ADDR N` prints every store to a sideways RAM
address.

## 4. Results

### Before this repository

The engine was developed in a research tree. Its last two versions were soaked
overnight on 14–15 November 2026, under the checks above:

| build | geometry | fields | result |
|---|---|---|---|
| `beam_m7c57` (this engine, as imported) | 57 wide at character 15 | 7.2 million (36 runs × 200,000) | all clean; variable work ended by line 244 at worst |
| `beam_m7c` (its sibling) | 55 wide at character 16 | 31.2 million (156 runs × 200,000) | all clean |

The 55-wide sibling was also simulated on the unmodified ElectronFpga HDL (nvc) at all
16 CPU/video phases, 48 locked fields each, on a random trajectory:
- FPGA schedule: phases 0–5 and 8–15 pass every field; phases 6 and 7 fail 43 of 48.
- Real-ULA schedule at phases 6 and 7: 48 of 48.

So the two schedules between them cover every phase. **The 57-wide build itself has
not been simulated on the HDL.**

### This repository

| commit | change | evidence |
|---|---|---|
| 1, import | the soaked build split into modules | binary byte-identical to `beam_m7c57`'s (elk.bin, kbd.bin, loader, .ssd, .uef) |
| 2, dead code out | dead code removed; page-crossing jitter removed from the fixed work | fingerprints of six trajectories (script and random walks, both models): every picture write identical in 23,880 fields, lock read's mean within 1.6 cycles. Soak: 8 runs × 100,000 fields, all clean |
| 3, balanced helpers | `rowaddr` and `addrow` balanced | fingerprints: picture writes identical; the fixed work's spread falls from 32 to 24 cycles |
| 3, balanced helpers (soak) | as above | soak: 40 runs × 100,000 fields = 4 million fields (cases 101–140; 20 runs on each ULA model, 6 following the script), all clean: 0 wrong, 0 unlocked, 0 late, 0 pad, 0 blip, 0 stray stores, the same 634 sideways RAM addresses written in every run; variable work ended by line 242 at worst; lock read at h 360–648 of line 0 |
| 4, smaller | dead tables, `RTCLOG` and `VBUF` removed; timed segments packed; the snippet builder rolled up (about 4K smaller) | fingerprints: picture writes identical, lock read in the same place, at every step; soak: 24 runs × 50,000 fields, all clean |
| 5, line blocks | the window loop rebuilt: two gadgets with absolute stores and sixteen line blocks that prepare the next row in the visible part; the strip builder 3,554 → ~950 cycles | the lead-in mode write moves from +17 to +15 µs (the phase model's coverage is unchanged, S 648–663); otherwise every write where the old loop put it, the fixed work and the lock read within 2 cycles of the original's (six fingerprinted trajectories). Soak: 16 runs × 50,000 fields = 800,000, both ULA models, all clean; variable work ended by line 242 at worst; lock read at h 344–664 |
| 6, MODE 2 | the window's screen mode a build option (`SCRMODE=2`: 114 × 170 pixels, sixteen colours, the CPC-palette test card); both demos built by default | MODE 1: timing identical to the build before (six fingerprints: every write, the fixed work and the lock read, in every field). Negative control: the MODE 2 program against the MODE 1 model fails 200 of 200 fields. Soak: 16 runs × 50,000 fields = 800,000, four runs each of MODE 1 and MODE 2 on each ULA model, all clean; lock read at h 344–664 |
| 7, split notch | the vertical step as a plan (variable work, ~1,400 cycles) and constant-time stores after display end (`nstore`, ~2,120 cycles, every field) | six fingerprints: picture writes identical, fixed work +0. A field with a step: 2,000–2,900 cycles of variable work (was 3,800–5,200). Negative control (by accident): a wrong span-mask offset failed every field. Soak: 16 runs × 50,000 fields = 800,000, both modes on both ULA models, all clean |
| 8, MODE 4 | lines 2–29 MODE 4 (MODE 6 in the band) instead of MODE 1/3: loop 1 gone, 2,595 cycles of free fixed-length time above the window, the strip build there; MODE 4 below the window, display end at line 255 | six fingerprints: every write from the palette line on identical (the window's exit's value aside), the lock read's spread as before (h 344–680). The strip build made constant (960 cycles: `addrow` off the stack). Soak: 16 runs × 50,000 fields = 800,000, both modes on both ULA models, all clean; variable work ended by line 223 |
| 9, 56 wide; the leak byte | the window at character 16, 56 wide; &7E07 kept zero (DESIGN.md 4.5): `build` zeroes it every field and, with block B5, keeps the strip from writing it; the soak expects black there, and its audit counts non-zero stores to &7E07 on lines 29–199 | six fingerprints (four MODE 1, two MODE 2, both ULA models, 4,000 fields each): every &FExx access identical to the 56-wide build without the fix, 29.6 million in all (the strip build's 38 cycles taken from `CAL_TB`). Negative control: the same soak without the fix, 4 runs × 20,000 fields, fails all four (19–25% of fields wrong, 36–53 non-zero stores to &7E07 a run, all from gadget A's entering store). Soak: 16 runs × 20,000 fields = 320,000, both modes on both ULA models, all clean, no store to &7E07 in the window; variable work ended by line 223; lock read at h 344–680 |

To run the soak yourself: `make emu`, put the ROMs in `roms/`, then
`test/soak.sh -n 100000 -r 40`. With eight runs at once a run of 100,000 fields takes
about seven minutes.

## 5. What is not yet known

- **This build has not run on a real Electron.** The 57- and 56-wide builds before it
  have, on 21 November 2026, on the real ULA's schedule: the picture locked and
  scrolled, and no misplaced line or character was reported, but a mid-line write to &FE07
  showed RAM[&7E07] (DESIGN.md 4.5; `ULA-NOTES.md` 15.4), which this build keeps black.
  The probe discs it was derived from also ran (probes 1–9, on an issue 6 machine with
  a Ferranti ULA).
- **The leak's details.** That the slot follows the write's address (a mirror such as
  &FEF7 should show &7EF7), how many of the leaked byte's pixels show, and whether
  writes to &FC and &FD pages take a slot too, are still to be tried.
- **Mode 7's wrap to &3000** is taken from pastraiser.com's hardware notes. The probes
  confirmed the real ULA's address phase, but not this wrap.
- **The CPU/video phase.** On an FPGA ULA it varies from power-up to power-up
  (DESIGN.md 4.4), and between them the two schedules cover every phase in
  simulation. On a real ULA it has been seen only on one machine.
- **Other ULAs.** Synertek-made ULAs, and the replacements (JamSoft, budgie's), have
  not been tried. The JamSoft design's address phase matches the FPGA's.

If it misbehaves on hardware, note what you see. Each symptom points at a different
assumption:
- the picture torn into vertical bars: try the other schedule;
- one line in eight displaced: the row register;
- the whole picture rolling: the lock;
- stray pixels in the lead-in area: the phase or the wrap.
