# Verification

How the scroll engine is checked, what the checks have found, and what is not yet
known.

## 1. The emulator

All checks run on Clock Signal's Electron core, from the fork in `emu/clk`
(`emu/README.md`), corrected in two steps:

1. **To match hoglet's ElectronFpga HDL** in everything the engine relies on
   (`ULA-NOTES.md` section 13). Before the fixes, CLK drew the engine's picture
   wrongly. The fixed core was checked against an nvc simulation of the unmodified
   HDL, running an earlier version of the scroll engine: every &FExx write and status
   read landed at the same raster position in both, apart from a constant 0.5 µs, the
   CPU/video phase (`ULA-NOTES.md` section 6; DESIGN.md, "The window loop and the
   lead-in").
2. **To match the real ULA's 40-column address phase**, which probe programs on an
   issue 6 Electron with a Ferranti ULA showed to differ from the HDL (`ULA-NOTES.md`
   15.1). This is a switch: elkh `realula 1`, elkview `--realula`. With it on, the
   emulator reproduced the probes as photographed.

The same switch also turns on a wrap of mode value 7 at &8000 to &3000. That is what a
Synertek ULA does; a Ferranti ULA treats mode value 7 as plain MODE 4 and wraps to
&5800 (`ULA-NOTES.md` 15.2). So the "real ULA" model is the Ferranti's phase with the
Synertek's wrap, and it does not reproduce the one fault the wrap causes on a Ferranti
(section 6).

The emulator does not model the leak byte: a CPU write to a ULA register during the
display taking that video slot (`ULA-NOTES.md` 15.4). The soak checks instead that the
byte the slot would show is zero (section 2).

## 2. What a soak checks

`test/soak.sh` runs `test/soak1.sh` over a deterministic set of cases. Run *i* takes
its start position and random-walk seed from *i*, so a given range of runs covers the
same cases every time and disjoint ranges cover new ones:
- start positions spread over the map, including its seams;
- the demo script on every seventh run, random walks on the rest;
- the real-ULA model and schedule on odd runs, the FPGA model and schedule (selected
  by pressing comma) on even ones;
- a MODE 1 window on runs 1, 2, 5, 6, …, MODE 2 on runs 3, 4, 7, 8, … (`-s 1` or
  `-s 2` picks one mode).

Each run builds the demo for its case, boots it in elkh, presses SPACE to start the
motion, and runs elkh's `soak` under the store audit. For **every field**, `soak`
checks:

| Check | Pass condition |
|---|---|
| picture | every pixel of the window equals the pattern model (`tools/gen.py`, exported as `model.bin`) at the position the program holds for that field; wherever the window fetches &7E07, the leak byte, the pixel is black; no pixel outside the window is lit |
| lock | the window's exit write (MODE 4) lands at exactly line 200, h 120, and the lock read is issued in line 0 (measured by the marker read just before it, `frame_tail`'s last status read: the last status read before the palette line's first write) |
| deadline | the variable-length work ends (its end marker, the second status read after the exit) before line 255, display end |
| pad | no non-zero byte is fetched in a 40-column mode on a window line: "pad" in the lead-in, "blip" at the right edge. Either would show on hardware whose phase differs from the emulator's, even if the emulated picture is right |

Its summary line gives the counts of bad, unlocked, late, pad and blip fields, the
latest line at which the variable work ended, and the range of lock-read positions
("lock read h", in 1/16 µs of line 0, from the marker read). The first wrong fields are dumped for
inspection.

Over the whole run, the store audit counts:
- stores to main RAM outside the screen ring (&3000–&7FFF), the stack, the key bytes
  (&0A00–&0A02) and the dummy page (&2400);
- non-zero stores to &7E07 on lines 29–199, where a window line's &FE07 write can show
  it;
- the sideways RAM addresses written (listed in `audit.txt`; the count is printed, for
  comparison between runs).

A run is clean if it has no bad, unlocked, late, pad or blip field, no stray store and
no non-zero store to &7E07.

`elkh race N` measures, for every screen store, how close the display's fetch of the
same byte comes. In the last recorded measurement (the record does not say on which
build) nothing came closer than 9.5 µs: stores behind the beam landed at least 9.5 µs
after the fetch, and stores ahead of it at least 16 µs before.

**Negative controls.** The checks do catch errors. Recorded:
- The real-ULA schedule on the FPGA model (no comma): every field wrong (300 of 300).
- CLK's original start-of-row register (`rowreg old`): every field wrong, and the pad
  audit fires in every one.

Steps 6, 7, 9 and 10 in section 4 each record a negative control of their own.

## 3. Timing equivalence of two builds

A change to the code can shift timing without making any field wrong at the phase the
emulator models. `test/fingerprint.sh` records every &FExx access of every field, with
its raster position, for a build that moves from the start (`MOTION=1`) in its model's
schedule (`SCHED`), so that no key press steers it. `test/fpcompare.py` aligns two such
records and compares them field by field:
- **picture**: the mode and palette writes from line 0 to the window's exit, which
  must be identical;
- **fixed**: the length of the fixed work below the window;
- **lock**: where the lock read lands.

Where a change is meant to be timing-neutral, the whole records can simply be compared
(`diff`). `test/fpmarkers.py` splits one fingerprint's fixed work into its sections
(the edge rows and the strip build) by the marker reads, for calibrating a change. To
follow one variable through a field, `elkh swatch ADDR N` prints every store to a
sideways RAM address.

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

So the two schedules between them cover every phase. **No build in this repository has
been simulated on the HDL.**

### This repository

Steps 1–9 used the two-read lock that the research tree had (the first read late in
line 0, the second mid line 1); step 10 replaced it. The lock-read positions recorded
for steps 3–9 are those of the first read.

| step | change | evidence |
|---|---|---|
| 1, import | the soaked build split into modules | binary byte-identical to `beam_m7c57`'s (elk.bin, kbd.bin, loader, .ssd, .uef) |
| 2, dead code out | dead code removed; page-crossing jitter removed from the fixed work | fingerprints of six trajectories (script and random walks, both models): every picture write identical in 23,880 fields, the lock read's mean within 1.6 cycles. Soak: 8 runs × 100,000 fields, all clean |
| 3, balanced helpers | `rowaddr` and `addrow` balanced | fingerprints: picture writes identical; the fixed work's spread falls from 32 to 24 cycles. Soak: 40 runs × 100,000 fields = 4 million (cases 101–140; 20 runs on each ULA model, 6 following the script), all clean: 0 wrong, 0 unlocked, 0 late, 0 pad, 0 blip, 0 stray stores, the same 634 sideways RAM addresses written in every run; variable work ended by line 242 at worst; lock read at h 360–648 of line 0 |
| 4, smaller | dead tables, `RTCLOG` and `VBUF` removed; timed segments packed; the snippet builder rolled up (about 4K smaller) | fingerprints: picture writes identical, lock read in the same place, at every step. Soak: 24 runs × 50,000 fields, all clean |
| 5, line blocks | the window loop rebuilt: two gadgets with absolute stores and sixteen line blocks that prepare the next row in the visible part; the strip builder 3,554 → ~950 cycles | the lead-in mode write moves from +17 to +15 µs (the phase model's coverage is unchanged, S 648–663); otherwise every write where the old loop put it, the fixed work and the lock read within 2 cycles of the original's (six fingerprinted trajectories). Soak: 16 runs × 50,000 fields = 800,000, both ULA models, all clean; variable work ended by line 242 at worst; lock read at h 344–664 |
| 6, MODE 2 | the window's screen mode a build option (`SCRMODE=2`: 114 × 170 pixels at the time, sixteen colours, the CPC-palette test card); both demos built by default | MODE 1: timing identical to the build before (six fingerprints: every write, the fixed work and the lock read, in every field). Negative control: the MODE 2 program against the MODE 1 model fails 200 of 200 fields. Soak: 16 runs × 50,000 fields = 800,000, four runs each of MODE 1 and MODE 2 on each ULA model, all clean; lock read at h 344–664 |
| 7, split notch | the vertical step as a plan (variable work, ~1,400 cycles) and constant-time stores after display end (`nstore`, ~2,120 cycles, every field) | six fingerprints: picture writes identical, fixed work +0. A field with a step: 2,000–2,900 cycles of variable work (was 3,800–5,200). Negative control (by accident): a wrong span-mask offset failed every field. Soak: 16 runs × 50,000 fields = 800,000, both modes on both ULA models, all clean |
| 8, MODE 4 | lines 2–29 MODE 4 (MODE 6 in the band) instead of MODE 1/3: loop 1 gone, 2,595 cycles of free fixed-length time above the window, the strip build there; MODE 4 below the window, display end at line 255 | six fingerprints: every write from the palette line on identical (the window's exit's value aside), the lock read's spread as before (h 344–680). The strip build made constant (960 cycles: `addrow` off the stack). Soak: 16 runs × 50,000 fields = 800,000, both modes on both ULA models, all clean; variable work ended by line 223 |
| 9, 56 wide; the leak byte (commit 623f8ce) | the window at character 16, 56 wide (it was 57 at character 15); &7E07 kept zero (DESIGN.md, "The leak byte"): `build` zeroes it every field and, with block B5, keeps gadget A from writing it; the soak expects black there, and its audit counts non-zero stores to &7E07 on lines 29–199 | six fingerprints (four MODE 1, two MODE 2, both ULA models, 4,000 fields each): every &FExx access identical to the 56-wide build without the fix, 29.6 million in all (the strip build's extra 38 cycles taken from `CAL_TB`). Negative control: the same soak without the fix, 4 runs × 20,000 fields, fails all four (19–25% of fields wrong, 36–53 non-zero stores to &7E07 a run, all from gadget A's entering store). Soak: 16 runs × 20,000 fields = 320,000, both modes on both ULA models, all clean, no non-zero store to &7E07 in the window; variable work ended by line 223; lock read at h 344–680 |
| 10, the single-read lock (commit 97f6743) | the lock as one read of `SYNCB`, issued inside line 0's fetches, 24 cycles sooner than the first of the two reads was; the counted code from S of line 0, so the switch to MODE 4 (or 6) moves from line 1 to line 0 and `CAL_TA` grows by 128 cycles to 1,170; `boot_sync` unchanged (its read at h 312). Added as the build option `LOCK1`, then made the only lock: the two-read lock is gone, and today's binaries are byte-identical to that `LOCK1` build | six fingerprints (four MODE 1, two MODE 2, both ULA models, 3,000 fields each) against the two-read build: of about 2 million writes a trajectory only the expected ones differ, the switch to MODE 4/6 (line 1 → line 0, both at S + 3 µs) and `ula_apply`'s three writes on line 311 (24 cycles sooner). Negative control: the single read aimed where the first of two used to go: one of two runs issued its read as late as h 664, past S, and failed 111 fields of 5,000 as unlocked. Soak: 16 runs × 20,000 fields = 320,000, both modes on both ULA models, all clean; lock read at h 152–488 |

After step 10, the free time above the window is `CAL_TA` 1,170 + `CAL_TB` 280 +
`CAL_TC` 1,235 = 2,685 cycles of delay, with the strip build's 998 cycles between
`CAL_TA` and `CAL_TB` (DESIGN.md, "The frame top: the lock and the free time"). The
lock read lands at h 152–488 of line 0 (the marker status read just before it; the
read itself is 3 µs later), a spread of about 21 µs, inside line 0's fetches (h 0 to
about 648) with about 12 µs to spare early and 7 µs late.

## 5. Running the checks

The checks need the emulator and the Electron's ROMs (`os.rom`, MOS 1.00, and
`basic.rom`, BASIC II) in `roms/` or the directory named by `ELK_ROMS`:

```sh
make emu                               # build-emu/elkh and build-emu/elkview
make test                              # build both demos, then test/soak.sh -n 5000: 8 runs, both modes
test/soak.sh -n 100000 -r 40           # a longer soak
test/soak.sh -n 20000 -r 16 -o 101     # sixteen new cases (runs 101-116)
test/soak.sh -s 2                      # MODE 2 windows only
```

`soak.sh` takes `-n` fields a run, `-r` runs, `-j` runs at once (default: the number
of CPUs), `-o` the first run's number and `-s` the window mode. It prints a line a run
and a total, and exits with status 0 only if every run is clean. Each run's details
are in `build/soak/rN/soak.txt`, its audit in `build/soak/rN/audit.txt`. With eight
runs at once, a run of 100,000 fields took about seven minutes when last timed.

To check that a change is timing-neutral, fingerprint both builds over the same
trajectories and compare them:

```sh
test/fingerprint.sh old.fp 1283 1280 1 1 real 4000      # OUT WX WY SEED TRAJ MODEL FIELDS
# ... change the code ...
test/fingerprint.sh new.fp 1283 1280 1 1 real 4000
python3 test/fpcompare.py old.fp new.fp
python3 test/fpmarkers.py new.fp                         # the fixed work's sections
```

`MODEL` is `real` or `fpga`; `SCRMODE=2` in the environment fingerprints a MODE 2
build. DESIGN.md, "Timing discipline and calibration", describes how to retune the
calibration constants from these measurements.

## 6. What is not yet known

- **This build has not run on a real Electron.** Neither the leak byte kept zero
  (step 9) nor the single-read lock (step 10) has been tried on hardware. The 57- and
  56-wide builds before them ran on 21 November 2026, on the real ULA's schedule, on a
  machine whose ULA type was not recorded: the picture locked and scrolled, no
  misplaced line or character was reported, and a mid-line write to &FE07 showed
  RAM[&7E07] (`ULA-NOTES.md` 15.4), which this build keeps black. The probe discs the
  real schedule was derived from also ran, on an issue 6 machine with a Ferranti ULA.
- **Ferranti ULAs and the row at &7FC0.** On a Ferranti ULA, mode value 7 is plain
  MODE 4, which wraps at &8000 to &5800. With the real schedule's 8 µs lead-in (t = 7),
  the ring row that starts at &7FC0 takes its eighth 40-column step across &8000, so
  the window's character row on that ring row shows the wrong bytes whenever t = 7.
  The engine does not avoid this yet. The emulator's real-ULA model has the Synertek's
  wrap to &3000 and does not show it; in an emulator build with a MODE 4 lead-in (what
  a Ferranti does with mode value 7) it affected about 1.5% of fields on random walks,
  always exactly that one character row (8 lines) at t = 7. The soak, as it stands,
  cannot catch it.
- **Synertek ULAs and the phase.** The real schedule's half-microsecond phase was
  measured on a Ferranti ULA only. Whether Synertek ULAs step the 40-column address
  the same way has not been measured. Earlier logic-analyser captures found Ferranti
  and Synertek ULAs within 1–2 ticks of each other in sync, display end, RTC and field
  alternation (`ULA-NOTES.md` sections 1–3).
- **The leak's details.** Not yet tried on hardware:
  - that the leaked byte follows the write's address: a mirror such as &FEF7 should
    show &7EF7;
  - whether writes to &FE01 or to page &FF reach the mode register;
  - whether writes to pages &FC and &FD, which the ULA also stretches to 1 MHz, take a
    slot too (they would show &7Cxx and &7Dxx);
  - how many of the leaked byte's pixels show.
- **The CPU/video phase.** On an FPGA ULA it varies from power-up to power-up
  (DESIGN.md, "The window loop and the lead-in"), and between them the two schedules
  cover every phase in simulation of the 55-wide sibling. On a real ULA it has been
  seen on one machine only. The single-read lock's margin (about 12 µs early, 7 µs late) was measured
  at the one phase the emulator models.
- **Other ULAs.** The replacements (JamSoft, budgie's) have not been tried. The JamSoft
  design's address phase matches the FPGA's.

If it misbehaves on hardware, note what you see. Each symptom points at a different
assumption:
- the picture torn into vertical bars: try the other schedule;
- one character row (8 lines) wrong, at one horizontal position in eight: the
  Ferranti's mode value 7 and the row at &7FC0;
- a thin bar the height of the window in the left margin, moving with the scroll: the
  leak byte, &7E07, not zero;
- one line in eight displaced: the row register;
- the whole picture rolling: the lock;
- stray pixels in the lead-in area: the phase or the wrap.
