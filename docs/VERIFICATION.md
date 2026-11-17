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

`test/soak.sh` runs `test/soak1.sh` over a deterministic set of cases:
- start positions and random-walk seeds spread over the map, including its seams;
- the demo script every seventh run;
- the real-ULA model and schedule on odd runs, the FPGA model and schedule on even
  ones.

For **every field**, elkh's `soak` checks:

| Check | Pass condition |
|---|---|
| picture | every pixel of the window equals the pattern model (`tools/gen.py`, exported as `model.bin`) at the position the program holds for that field, and no pixel outside the window is lit |
| lock | the window's exit write (MODE 6) lands at exactly line 200, h 120, and the lock read stalls in line 0 |
| deadline | the variable-length work ends before line 249 (display end) |
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
| 3, final | the build in this repository | soak: 40 runs × 100,000 fields = 4 million fields (cases 101–140; 20 runs on each ULA model, 6 following the script), all clean: 0 wrong, 0 unlocked, 0 late, 0 pad, 0 blip, 0 stray stores, the same 634 sideways RAM addresses written in every run; variable work ended by line 242 at worst; lock read at h 360–648 of line 0 |

To run the soak yourself: `make emu`, put the ROMs in `roms/`, then
`test/soak.sh -n 100000 -r 40`. With eight runs at once a run of 100,000 fields takes
about seven minutes.

## 5. What is not yet known

- **This build has not run on a real Electron.** The probe discs it was derived from
  have (probes 1–9, on an issue 6 machine with a Ferranti ULA), and so have earlier
  scroll tests. The changes since the last hardware test are the mode 7 lead-in and
  the two-read lock.
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
