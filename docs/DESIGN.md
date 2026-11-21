# elkgame: design of the scroll engine

This document explains how the engine puts a 56-character × 170-line window on an
Acorn Electron (224 × 170 pixels in MODE 1, 112 × 170 in MODE 2) and scrolls it at
50 Hz with interrupts off. Sections 2–4 cover the display: the memory layout, the
frame's top and its raster lock, and the window loop that scrolls the picture across.
Section 5 covers how the picture is kept up to date as it moves, section 6 the bottom
of the frame, and section 7 the timing discipline and how to recalibrate it. Section 8
maps the source, section 9 describes the MODE 2 window, section 10 what a game would
add, and section 11 what is known to be wrong, untested or unknown.

The ULA behaviour the engine depends on is set out, with sources, in
[`ULA-NOTES.md`](ULA-NOTES.md). The evidence that the engine works, and how it was
gathered, is in [`VERIFICATION.md`](VERIFICATION.md). File names are in `src/` unless
they say otherwise. Where this document and a comment in the code disagree, the code
is the reference.

**Conventions.**
- **h** is the horizontal raster position in 1/16 µs, 0–1023 across a 64 µs line,
  with h = 0 at the first displayed pixel. The display fetches run from h 0 to h 639.
- **S** is the moment a main-RAM access that was held up by the display fetches
  completes: in a 20K mode, just after the end of the line's fetches, at about
  h 648 (h 648 in the emulator; see 4.4). It is the only raster position a program
  can observe on the Electron. Times inside a line are given in **µs after S**. Once
  the lock has found S on line 0, every later "S" is the counted position: the
  lock's S plus 128 cycles a line.
- **Cycles** are 2 MHz CPU cycles: 128 to a line. Code and variables are in sideways
  RAM, which runs at 2 MHz. Main RAM and the ULA's registers take a 1 MHz slot, 2 or
  3 cycles depending on the phase the access starts in (`ULA-NOTES.md` section 6).
- A **character** is a MODE 1 character: 8 bytes, 4 pixels wide (2 in MODE 2) and 8
  lines high. "Column" and "character" are used interchangeably across the screen.
- **MW** is the window's mode value: MODE 1 (&08), or MODE 2 (&10) in a MODE 2 build.
  Mode values are written to &FE07 with the comms, LED and motor bits clear: MODE 1
  &08, MODE 2 &10, MODE 3 &18, MODE 4 &20, MODE 5 &28, MODE 6 &30, mode value 7 &38.

---

## 1. The problem

The Electron's ULA shows a 20K MODE 1 screen as 80 characters across by 32 rows of
640 bytes. It offers almost nothing for scrolling:

- **No fine scroll.** The screen start (&FE02, &FE03) holds address bits 14..6, so it
  moves in steps of 64 bytes: 8 characters across, or a tenth of a 640-byte row down.
  It is read once a field.
- **No raster interrupt.** The only video events are display end and the "RTC" event
  on line 99, each once a field.
- **A starved CPU.** Main RAM is shared with the display. In a 20K mode (MODE 0–3) any
  main-RAM access during a line's fetches waits until they end. Sideways RAM
  (&8000–&BFFF) is on the CPU's own side of the bus and runs at a full 2 MHz, so the
  engine runs from a bank of it and keeps its variables there.
- **No room for a second buffer.** The 20K screen is &3000–&7FFF of 32K.

The engine works round all four:

- **Horizontal fine scroll** comes from changing the screen mode twice in every
  window line: a 40-column "lead-in" at the start of the line puts the line's address
  counter a chosen number of characters behind (section 4).
- **Vertical fine scroll** comes from a band of 10-line text rows at the top of the
  frame, which pushes the rows below down by 2 lines a row (2.4).
- **Timing** comes from one main-RAM read a field, which stalls until S of line 0
  and locks the program to the raster (3.1). From there to the window's last line
  every cycle is counted. Outside the window the frame is in 40-column modes, in which
  the ULA never holds up the CPU.
- **New picture** is written as the window moves, at a fixed cost per field. A new
  column is stored by the window loop itself, one byte a line in the horizontal
  blanking (5.1). A new row is drawn a quarter at a time (5.3).

---

## 2. Screen geometry and memory

### 2.1 The window

| | |
|---|---|
| size | 56 characters × 170 lines: 224 × 170 pixels in MODE 1, 112 × 170 in MODE 2 |
| position | screen characters 16–71 (of 80) across, h 128–575; lines 30–199 |
| above it | lines 0–29, black: line 0 MODE 1 or MODE 3 (for the lock), then MODE 4, with 0–3 rows of MODE 6 (10-line text rows) at the top |
| below it | lines 200 to the field's end (311 or 312), black, MODE 4 |
| palette | MODE 1: black, cyan, magenta, yellow (&FE08 = &97, &FE09 = &D3), set on line 29; &FF in both from line 200 to line 29 |

`tools/gen.py` sets the geometry (`Y0` = 30, `Y1` = 200, `H` = 170, `WIN_C` = 16,
`WIN_W` = 56) and writes it, with the mode values and palette, to the generated
`config.inc`. It asserts `WIN_C` ≥ 14, `WIN_C + WIN_W` ≤ 72 and `WIN_W` ≤ 61.

### 2.2 The ring

The ULA wraps a 20K screen at &8000 back to &3000, so the screen is a ring of &5000
bytes. The engine lays it out as rows of **72 characters (576 bytes)**, not the 80
the ULA displays:

- **Coarse scroll is a change of screen start.** 576 bytes is exactly 9 steps of the
  screen start's 64 bytes. A one-character step across is a change of 8 bytes, folded
  into the lead-in (4.2); a one-row step down is a change of 576.
- **The start-of-row latch holds address bits 14..6.** At the end of a character
  row's last line the ULA latches the address counter, truncated to 64 bytes, as the
  next row's start. A line that fetches between 72 and 79 characters therefore
  advances the row by exactly 576 bytes (4.2).
- **320 rows of 576 bytes are exactly 20K**, so the ring is one tape of 2,560
  character cells and the map's rows lie 72 cells apart along it.

Map character column x of character row y is at

    &3000 + (576 y + 8 x) mod &5000

with x mod 2560 and y mod 320 (`R576L`/`R576H`/`R576LT`/`R576HT`, `RINGHI` and
`WRAPHI` in the generated `gen_tables.s` do this arithmetic; `rowaddr` and `addrow` in
display.s use them). Each row's 72 cells hold the window's 56 and 16 **gap cells**,
which are kept zero, so they show black. As the window moves right, every row's window
slides one cell along the tape: the cell entering at the right is the old first gap
cell after it, and the cell leaving at the left becomes a gap cell. Nothing is moved
in memory.

Because rows are 72 cells apart, a row's cells beyond its 72nd are the next row's
first. A displayed line fetches 72 to 80 characters, so the margins show gap cells:
with a lead-in of t characters, the left margin (screen characters 0–15) shows the
16 − t cells before the window (the previous row's last gap cells), t of them double
width in the lead-in, and the right margin (screen characters 72–79) the 8 cells
after it. Both must be zero. The soak checks that nothing outside the window is lit,
and that no non-zero byte is fetched in a 40-column mode on a window line.

### 2.3 The map and the coordinates

The playfield is a map 2,560 characters across and 2,560 lines (320 character rows)
down, which repeats in both directions. The position is held as:

| variable | meaning |
|---|---|
| `wx` | the map column at the window's left edge, 0–2559: the position shown next field |
| `wy` | the map line at the window's top, 0–2559, always even (vertical steps are 2 lines) |
| `mx` | the window's left column as the ring currently holds it |

`mx` runs ahead of `wx` while a column step is in progress (5.1, 6.3). The test
pattern is a grid of blocks 4 characters by 16 lines (2 character rows), each one of
35 dithered colours (26 in MODE 2), chosen by a hash of the block's coordinates
(`gen.py` explains it). Each block's left pixel column and bottom line are black, so a
character or line out of place breaks the grid at once. The bottom line, not the top,
is the black one, so that line 0 of every character row carries pattern. A game would
have tiles here instead (section 10).

### 2.4 The band and the rows above the window

The vertical position is coarse plus fine:

- **Coarse:** the screen start selects the character row of map line `wy`.
- **Fine:** `f = ((Y0 − wy) & 7) / 2` rows of 10-line text mode at the top of the frame
  push the rows below down by 2f lines.

| `wy & 7` | 0 | 2 | 4 | 6 |
|---|---|---|---|---|
| f (band rows) | 3 | 2 | 1 | 0 |

There are always exactly three character rows above the window's first: f band rows of
10 lines and 3 − f MODE 4 rows of 8, then `wy & 7` lines of the window's first row,
which are MODE 4 too: 10f + 8 (3 − f) + (`wy & 7`) = 30 = `Y0`. All of these rows are
in 40-column modes, so each fetches 320 bytes (40 characters), a multiple of 64. So:

- every row above the window starts aligned, with no per-line writes;
- the screen start is the window's first row less 960 bytes, which is at least &2C40
  (the first row is in &3000–&7FFF): the counter never reaches &8000 above the window,
  and never falls below &0800, where the ULA's wrap rule would act at once.

**Modes of the lines above the window** (`setup_frame` in display.s, from tables in
tables.s, indexed by f):

| line(s) | f = 0 | f = 1 | f = 2 | f = 3 | set by |
|---|---|---|---|---|---|
| line 0 (until S + 3 µs) | MODE 1 | MODE 3 | MODE 3 | MODE 3 | `TOPMODE`, written by `ula_apply` on line 311 of the field before |
| from line 0, S + 3 µs | MODE 4 | MODE 6 | MODE 6 | MODE 6 | `TOP2`, patched into `ftop` |
| line 9, S + 17 µs | MODE 4 | MODE 4 (band ends) | MODE 6 | MODE 6 | `W9TAB`, patched into `fw9` |
| line 19, S + 17 µs | MODE 4 | MODE 4 | MODE 4 (band ends) | MODE 6 | `W19TAB`, patched into `fw19` |
| line 29, S + 17 µs | lead-in mode | lead-in mode | lead-in mode | lead-in mode (band ends) | the palette line (3.4) |

- **Line 0** is MODE 1 or MODE 3, a 20K mode, so that the lock's read stalls (3.1).
  MODE 3 is the text-mode equivalent, used when line 0 is the first line of a band
  row. Only a row's last line decides where the next row starts, so line 0's 80
  characters of fetching do the row no harm.
- **The band ends** on line 10f − 1 with a write at S + 17 µs: after that line's
  character-row counter has rolled over at the end of the line sync, and before the
  next line's first fetch (`ULA-NOTES.md` 11.3). Writes on lines 9 and 19 that do not
  end the band rewrite the mode the line already has.
- **The screen start.** `setup_frame` computes it from `wx` and `wy` and `ula_apply`
  writes it on line 311 (&FE02 = (start >> 1) & &E0, &FE03 = (start >> 9) & &3F). The
  ULA reads it at the start of the next field.

---

## 3. The frame top: the lock and the free time

A field is laid out like this (raster.s, frame.s):

| lines | mode | what runs |
|---|---|---|
| 0 | MODE 1 or 3 | the lock (3.1), then the switch to MODE 4 or 6 at S + 3 µs |
| 0–29 | MODE 4 / MODE 6 | free time and the strip build (3.3); the band's end on line 9 or 19 |
| 29 | MODE 4 / MODE 6 | the palette line (3.4) |
| 30–199 | MW | the window loop (section 4) |
| 200 | – | the exit: black palette, MODE 4 |
| 200–255 | MODE 4 | variable-length work, then a poll for display end (section 6) |
| 255–311/312 | MODE 4 | fixed-length work, then a counted delay to the next lock |

### 3.1 The lock

Interrupts are off from start-up. Each field begins at `frame_top` with one read of a
main-RAM byte (`SYNCB`, &0200):

    frame_top: lda SYNCB      ; issued inside line 0's fetches; stalls until S
    ftop:      lda #M4        ; patched: M4, or M6 in a band
               sta ULA_MODE   ; line 0, S + 3 us

Line 0 is MODE 1 or MODE 3. In a 20K mode a main-RAM read issued anywhere in the
line's fetches waits until they end, so the read returns at S of line 0 wherever in
line 0's fetches it was issued. The counted code starts from there. The read is placed
by the length of the fixed work at the bottom of the previous field (section 6), which
starts at display end and is the same length on every path to within a few µs.

**The margin.** The soak (`emu/elkh soak`) reports where the lock read lands: across
16 runs of 20,000 fields, both window modes and both ULA models, at h 152–488 of
line 0. That is a spread of about 21 µs, from the 1 MHz access phases of the fixed
work's main-RAM stores and the display-end poll's loop. The position
the soak reports is that of the status read (`lda ULA_STAT`) which `frame_tail` makes
as a marker just before `jmp frame_top`, since the emulator logs only &FExx accesses;
the `SYNCB` read's own access follows it by 6 cycles (3 µs), so the read itself is
issued at about h 200–536. Against line 0's fetches, h 0 to about h 648, that leaves
about 12 µs to spare on the early side and 7 µs on the late side.

**The failures.**
- **Too late:** a read issued after line 0's fetches have ended does not stall. It
  returns on the next slot, and the field's writes are that much late.
- **Too early** is the worse failure. A read issued before line 0's fetches begin (in
  the last line of the previous field, where nothing is fetched) returns at once,
  about 40 µs before S, so the whole field is about 40 µs early. And because the
  read's position is set by the fixed work, which is the same every field, every
  later field's read arrives too early as well.

Either way the soak reports the field as unlocked: it checks that the lock read is on
line 0 and that the window's exit write lands at exactly line 200, h 120.

### 3.2 `boot_sync`

The fixed work counts lines to the next field's line 0, and PAL fields alternate 312
and 313 lines, so the program must know which field it is in. `boot_sync` (init.s,
segment TAILS, run once after start-up) finds out:

1. It writes &FE0A–&FE0F (the palette registers only MODE 2 uses, 9.1) and MODE 1,
   and clears the RTC and display-end flags (&FE05 with bits 4 and 5, keeping the
   bank's paging bits).
2. It waits for the RTC flag. The RTC event is on line 99: at the start of the line in
   the 312-line field, half way along it in the 313-line field.
3. It clears the flags again and counts status polls until display end (line 255 in
   a graphics mode). The count is shorter in the 313-line field, whose RTC came later.
   `CAL_BTHR` (&594 polls) divides the two counts: below it, `fpar` = 1 (this is the
   313-line field).
4. From display end it waits 208 cycles (past line 256), writes line 0's mode, then counts `CAL_BN64` (109)
   passes of 64 cycles, two more in the 313-line field, and `CAL_BREM` (0) cycles, and
   enters `frame_top`.

Its lock read lands at about h 312 of line 0. From then on `fpar` simply alternates,
once a field at the start of the bottom-of-frame work.

### 3.3 The free time above the window

From S + 3 µs of line 0 the lines are MODE 4, or MODE 6 in the band. These are
40-column modes, for which the ULA fetches without holding up the CPU: a main-RAM
access is an ordinary 1 MHz one. Down to the palette line the only writes needed are
the band's possible ends on lines 9 and 19 (2.4), so the time between them is free for
fixed-length work:

| from | to | what | cycles |
|---|---|---|---|
| line 0, S + 3 µs | line 9, S + 17 µs | `CAL_TA` (an `LDELAY`) | 1,170 |
| line 9, S + 17 µs | line 19, S + 17 µs | `build`, the strip for this field's window (5.1), then `CAL_TB` | 998 + 280 |
| line 19, S + 17 µs | the palette line (line 29) | `CAL_TC` | 1,235 |

`CAL_TA` + `CAL_TB` + `CAL_TC` = **2,685 cycles of delay** that a game can replace with
its own fixed-length work, with main RAM at 1 MHz and uncontended. The strip build
takes 998 cycles, 38 of them for the leak byte (4.5). The lines are black (the palette
is &FF until line 29), so stores to the screen here are not seen until the window.

### 3.4 The palette line

Line 29 is the window loop's first iteration (4.1), with the palette in place of the
strip's two stores. It is a 40-column line, so it has no blip:

| µs after S of line 29 | write |
|---|---|
| +4 | &FE08 ← the window's palette (`PAL8`) |
| +9 | &FE07 ← MODE 3 (as in the window's line sync) |
| +13 | &FE09 ← `PAL9` |
| +17 | &FE07 ← the lead-in mode (`vcv`: mode value 7, or MW with no lead-in); in a 3-row band this also ends the band |
| +23 + u | &FE07 ← MW: the palette line's variant `VSPu`, through `VVECP` (none when u = 0) |

The variant returns to `backP`, which loads X with the blip's mode value for the whole
window (`vav`), waits `CAL_ENT` (41) cycles and jumps (through `wtP`, patched by
`build`) to the line-block tail that loads the first window line's byte. That jump
sets the window loop's phase.

---

## 4. The window loop and the lead-in

### 4.1 The gadgets and the line blocks

The window loop (`gen_loop2.s`, generated by `gen_loop2` in `tools/gen.py`, segment
LOOP2) is one iteration a line, exactly 128 cycles. Iteration y runs from the right
margin of line y to the lead-in of line y + 1. Its code exists in pieces:

- two **gadgets** of horizontal-blanking code, `gA` for even map rows and `gB` for
  odd;
- sixteen **line blocks** `b{P}{k}` of visible-part code, one for each line k (0–7)
  of a row of each parity P, each ending in a **tail** `t{P}{k}`;
- the **variants** `VS2u` (u = 0–8, `gen_variants.s`), which make the lead-in's
  second write.

A gadget:

    gP:  sta a:cell_in    ; the entering cell <- A (patched per row, stepped per line)
         lda #0
         sta a:cell_out   ; the leaving cell <- 0
         lda #M3
         sta ULA_MODE     ; +9 us: MODE 3, inside the line sync
         (pad)
    vcP: lda #M7          ; patched per field: the lead-in mode
         sta ULA_MODE     ; +15 us
         lda #MW          ; the window's mode, for the variant
         (pad)
         jmp (VJ)         ; the variant (entered 41 cycles after S), or VX

The variant `VS2u` is u `nop`s and `sta ULA_MODE`, padded so that every variant takes
the same time, then `jmp (VRET)` to the next line block. Each line block is exactly
`BLK_LEN` (45) cycles from its entry to its tail, counted and padded by `gen.py`, and
does, for the line about to be stored:

1. its slice of the next row's preparation (5.1);
2. for k < 7, `inc` of the low bytes of its own gadget's two store addresses, which
   steps them one byte down their cells (cells are 8-byte aligned, so there is never a
   carry);
3. `VRET` ← the next block. Blocks sit in 64-byte slots, four to a page (A0–A3,
   A4–A7, B0–B3, B4–B7), so only the blocks at k = 3 and 7 set `VRET`'s high byte;
4. at k = 7, the row count for the exit (below);
5. its tail: the next line's entering byte into A, `stx ULA_MODE` (the blip, X), and
   `jmp` to the gadget (the other gadget after line 7).

A carries the data byte into the gadget, X holds the blip's mode value through the
whole window, and Y is scratch for the slices. Each block knows its line and its
row's parity, so no register counts lines.

**The writes of one iteration** (µs after S of line y):

| µs after S | write | code |
|---|---|---|
| −3 | &FE07 ← X: MODE 5 when u ≤ 1 (the **blip**, 4.2), else MW, which changes nothing | the tail's `stx ULA_MODE`, every window line |
| just after S | the entering cell ← A | the gadget |
| a few µs later | the leaving cell ← 0 | the gadget |
| +9 | &FE07 ← MODE 3, inside the line sync (4.2) | the gadget |
| +15 | &FE07 ← the lead-in mode: mode value 7, or MW when u = 0 | the gadget (`vcA`, `vcB`) |
| +23 + u | &FE07 ← MW, u µs into line y + 1 (4.2); nothing when u = 0 | the variant `VS2u` |

On the palette line the lead-in mode write is at +17 µs (3.4). The gadgets run on all
170 window lines (30–199); a line block follows each but the last, so there are 169
line blocks a field, the first entered from the palette line.

**Per-field patches** (`setup_frame`, `build`): the lead-in mode into `vcA`, `vcB` and
`vcv`; X's value (`vav`); the variant (`VJ`'s low byte; the window's variants share a
page with `VX`, asserted, so the high byte never changes); the gadgets' store
addresses for the first two rows; the entry tail (`wtP`) and first block (`VRET`); and
the exit.

**The exit.** The last window line's gadget jumps to `VX` instead of a variant:

    VX:  lda #$FF / sta ULA_PAL8 / sta ULA_PAL9   ; black
         lda #M4 / sta ULA_MODE                   ; line 200, h 120 (the soak checks it)
         jmp work                                  ; the bottom of the frame

MODE 4 is a graphics mode, so display end comes at line 255 (in a text mode it would
be line 249), and a 40-column one, so main RAM is uncontended below the window. The
redirect is armed in the visible part of line 198:

- `build` works out which block runs after the second-to-last line (line k0 + 168 of
  the window, counted from the first row's line 0) and how many line-7 blocks come
  before its row (`rows`), and points both line-7 blocks' arming stores at that block's
  hook.
- Each line-7 block counts `rows` down. The one that brings it to zero patches the
  chosen block's `lda #<next / sta VRET` to `lda #<VX / sta VJ`.
- When the chosen block runs, `VJ` becomes `VX`, so the next gadget, the last line's,
  exits.
- The next field's `build` restores the patched hook first (`hkprev`).

### 4.2 The lead-in: t and u

In a 40-column mode (MODE 4, 5, 6 and mode value 7) the ULA fetches a byte every
microsecond, stepping its address one character (8 bytes) per µs; in MODE 0–2 it
fetches one every half microsecond. A mode change takes effect mid-line, and the
address counter carries on from where it had got to.

So every window line starts in a 40-column mode and switches to MW part way in. A
line whose switch comes after t 40-column steps has fetched t characters where MW
would have fetched 2t: its address falls **t characters behind**, and the MW part of
the line shows memory character c − t at screen character c. With t = 0–7 and the
screen start in 8-character steps, the window can start at any map column:

    t  = (WIN_C - wx) & 7          ; the lead-in, in characters (tv, T_BY_X)
    cb = wx - WIN_C + t            ; the screen start's column, a multiple of 8

and screen character `WIN_C` then shows map column `wx`. The lead-in's characters are
the gap cells before the window, which are zero, so the 40-column part is black.

**u** is the variant number: the MW write lands at S + 23 + u µs of the line before,
u µs into the line itself (exactly so in the FPGA's aligned phase, S = 656; 4.4). On the FPGA ULA u = t; on the real ULA u = t + 1, except
that u = 0 when t = 0 (4.3). With u = 0 there is no lead-in: the lead-in mode write is
MW itself and the variant writes nothing.

**Keeping the rows aligned.** The start-of-row latch takes the counter, truncated to
64 bytes, at the end of a row's last line. So a line must end with its counter in the
right 64-byte block: between the row's start + 576 and + 639.

- **The fetch count and the blip.** A line with t characters of lead-in fetches
  80 − t characters, 73 to 79 for t = 1–7: 584 to 632 bytes, which the latch truncates
  to 576. With t = 0 the line would fetch all 80, 640 bytes, one 64-byte block too
  many. So the tail's write at S − 3 µs (h ≈ 600, screen character 75, in the right
  margin) is MODE 5 when u ≤ 1: the last 2–3 µs of the line are fetched at the
  40-column rate, and the line fetches 77–78 characters. This is the **blip**. It is
  needed only at t = 0; the code applies it whenever u ≤ 1 (`VA_BY_X`), which is t = 0
  on either schedule and t = 1 on the FPGA's. When u ≥ 2 the same write stores MW and
  changes nothing.
- **The row ends and MODE 3.** Lines end at different places, so line 0 of each row
  would start from the untruncated counter left by line 7, not from the latch. A write
  of MODE 3 (a text mode) at S + 9 µs, inside every line sync, prevents this: in the
  FPGA model the latch has taken the row's end at the start of the sync, while the
  line was still a graphics line, and in a text mode line 7 is not a row's last line,
  so the counter is reloaded from the latch for line 0 like any other line. The lead-in
  mode write at S + 15 µs, after the sync, makes the line a graphics line again.
  (`ULA-NOTES.md` sections 4, 5 and 11.2.)

**The check in `gen.py`.** `_sim` steps a line's fetches under a schedule's writes, and
`sched_ok(t, S)` requires, for the FPGA schedule at phase S:

- no 40-column step from character 7 to 8 of the row (`forbid={7}`);
- the counter at h 640 in the 10th 64-byte block (576 bytes) and, for t ≥ 1, exactly
  80 − t characters fetched;
- the counter at the window's right edge (h 576) at character `WIN_C + WIN_W − t`:
  every window character fetched in MW;
- for t = 0, the blip after the window's last pixel (h ≥ 580);
- the MODE 3 write inside the line sync (h 768–832) by at least 8 ticks at each end,
  and the lead-in mode write at least 4 ticks after the sync;
- the MW write effective before h 132, 4 ticks into the window's first character.

`check_schedules` asserts every t at every phase in `S_RANGE` (S = 648–659) and is
run by `gen_variants`, so a schedule that fails stops the build. (The schedules in
fact pass at S = 648–663: `cd tools; python3 -c 'import gen; gen.check_schedules(True)'`
prints the map.) The model covers the FPGA schedule only, and models the blip only at
t = 0.

### 4.3 Two ULAs, two schedules, and mode value 7

hoglet's [ElectronFpga](https://github.com/hoglet67/ElectronFpga) HDL steps the
40-column address in the second half of each microsecond. Probe programs on a real
Electron with a Ferranti ULA (issue 6) showed that the real chip steps it half a
microsecond earlier. A mode write lands between the two, so the real chip's switch
out of the 40-column mode costs a character fewer, and a lead-in of t characters needs
the MW write at t + 1 µs. Whether Synertek ULAs step the same way has not been
measured. The engine carries both schedules and switches at run time:

| | key | `sched` | MW write (variant u) | blip (MODE 5) |
|---|---|---|---|---|
| FPGA ULA | comma | 0 | u = t | t = 0, 1 |
| real ULA (the default, `SCHED=8`) | full stop | 8 | u = t + 1; u = 0 when t = 0 | t = 0 |

`setup_frame` indexes the lead-in tables (`VSP_BY_X`, `VSPH_BY_X`, `VS2_BY_X`,
`VA_BY_X`, `VC_BY_X`, from `lead_in_index` in `gen.py`) by `(wx & 7) | sched`. The
keys are read in the bottom of the frame and take effect the field after.

**Why mode value 7.** The lead-in mode, on both schedules, is mode value 7 (&FE07 bits
3–5 = 7, undocumented), not MODE 4 or 5. With the real schedule's longest lead-in
(t = 7, the MW write at 8 µs) a line takes eight 40-column steps from its row's start.
Rows start on 64-byte boundaries, so the one ring row that starts at **&7FC0** takes
its eighth step from &7FF8 across &8000. A 40-column mode wraps the address there to
its own base, not to the 20K ring's &3000: MODE 4 and MODE 5 to &5800, MODE 6 to
&6000. On a **Synertek** ULA (and the "Aberdeen" family) mode value 7 fetches like
MODE 4 but wraps to **&3000**, so that row is right. On a **Ferranti** ULA mode value 7
is plain MODE 4 and wraps to &5800, so that row is wrong (section 11). The FPGA
schedule never takes an eighth step (`gen.py` forbids a step from character 7 to 8),
so the wrap does not arise there; the FPGA treats mode value 7 as MODE 4.

### 4.4 The CPU/video phase

The CPU's 1 MHz slots and the ULA's pixel counter run from the same clock, but nothing
fixes their relative phase. That phase decides where S falls (h 656 when the FPGA's
counters are aligned, h 648 in the emulator, which follows JamSoft's ULA here) and
therefore where each write lands among the fetches. `gen.py`'s model (`_sim`,
`sched_ok`) takes S as a parameter: a write `+u` µs after S is first seen by the video
logic at h 16u + (S − 656) of the next line, MODE 5 steps the address at h ≡ 15
(mod 16) and MODE 1 at h ≡ 7 (mod 8). It was matched to an nvc simulation of the FPGA
HDL. Every FPGA schedule works at S = 648–663 in the model.

In the HDL simulation of the engine's 55-wide sibling at all 16 phases, the FPGA
schedule passed at 14 and the real schedule covered the other two (`VERIFICATION.md`
section 4). On a real ULA the phase has been seen on only one machine.

### 4.5 The leak byte

**The limitation.** On a real ULA, a CPU write to a ULA register while the ULA is
fetching for the display takes that video slot: the slot shows the RAM byte at the
CPU's address with A15 dropped, RAM[&7E00 + the address's low byte], painted in the
mode the write sets, instead of its own byte. For the mode register, &FE07, that is
**RAM[&7E07]**. So **&7E07 must hold zero**, or it shows as a coloured mark at every
such write. Reads apparently do not take a slot: the builds tested on hardware had an
older window loop that read &FE00 once a line in mid-window, and nothing showed there
(the current loop makes no read in the window; `ULA-NOTES.md` 15.4). Neither the
CLK fork nor the FPGA HDL models this.

&7E07 is ordinary screen memory: line 7 of the ring cell at &7E00, which holds map
data as the window moves. The ULA decodes only A0–A3 in page &FE, so the same write
could be made to a mirror, &FE17, &FE27 … &FEF7, which by the same rule would show
&7E17 … &7EF7: line 7 of every other cell from &7E00 to &7EFF. The engine uses &FE07.

**The writes it affects.** Every &FE07 write the engine makes inside a line's fetches
(h 0–639):
- the variant's MW write, at the lead-in's end (+23 + u µs; h ≈ 16u − 8 in the
  emulator's phase), in the left margin, on every window line with u ≥ 1;
- the tail's write at S − 3 µs (h ≈ 600, screen character 75), in the right margin,
  on every window line: the blip's MODE 5 when u ≤ 1, otherwise a rewrite of MW.

All the engine's other register writes are in the horizontal blanking or below the
display: MODE 3 at +9 µs, the lead-in mode at +15 or +17 µs, the palette line's
writes, the band's ends at S + 17 µs, line 0's switch at S + 3 µs, and `ula_apply` on
line 311. (The exit's writes on line 200 are an exception; see section 11.)

**How it was found** (21 November 2026, a real Electron whose ULA type was not
recorded). At 57 wide on character 15, the window's first character went black at one
horizontal position in eight: t = 7, whose MW write (u = 8) lands at h 120, character
15. At 56 wide on character 16, a thin bar the height of the window appeared in the
left margin at the lead-in's end, moving two characters per column step (the lead-in's
end moves 1 µs per step), vanishing at t = 0, its colour depending on the scroll's path
and position. Debug builds that wrote &0F to &7E00–&7E07 turned the bar cyan, and
zeroing them removed it. The window was moved to character 16 so that the longest
lead-in's last slot (h 120) is in the margin.

**How the engine keeps &7E07 zero.**
- **Every field**, `build` (strip.s) stores 0 at `LEAK` (&7E07), above the window
  (3.3), after everything that might have written it in the bottom of the frame:
  `colop`, the notch's `nstore`, and at start-up `init`. These write only below the
  window, in the bottom of the frame.
- **In the window** the only possible writer is the strip (5.1). Its leaving stores are
  zero; an odd map row's line 7 is zero (the grid line: tail `tB6` loads #0); the idle
  strip's bytes are zero. The one case left is gadget A, the even rows', storing line 7
  of its entering cell, from `VO`. When that cell is `LEAKCELL` (&7E00), the tail
  `tA6` is pointed at `ZB`, a byte that is always zero, just below `VO` (vars.s; the
  two share a page, asserted, so only the operand's low byte changes). Block B5 (the
  `('B', 5)` slice in `gen_loop2`) decides this for every A row from the gadget A
  address it has just prepared; `build` decides it for the gadgets it sets up for the
  first two rows.

**The cost.** One byte of the picture is black: line 7 of whichever map cell is at
&7E00, when that is an even row's cell (an odd row's line 7 is black anyway). `build`
spends 38 cycles on it, taken from the free time above the window; the B5 slice fits
in its block's padding. The soak (`emu/elkh soak`) expects black wherever the window
fetches &7E07, and its audit counts non-zero stores to &7E07 on lines 29–199.

**For a game whose map cannot spare that byte.** It could choose, each field, a mirror
of &FE07 whose byte is zero, falling back to zeroing one that is not on show; the
remaining case, all sixteen on show and non-zero, needs the chosen byte zeroed for
every line but its own. The writes' operands are in the generated variants
(`sta ULA_MODE`) and tails (`stx ULA_MODE`).

---

## 5. Keeping the picture up to date

### 5.1 A new column: the beam-raced strip

A coarse step right exposes a new column at the window's right edge, the **entering
column**, and leaves one at its left, the **leaving column**, which must become a
zero gap cell (going left, the other way round). On the window's lines a column is one
byte a line. Instead of drawing it in the vertical blanking, the window loop stores
it: on every window line, in the horizontal blanking, the gadget stores one byte of
the entering column and one zero of the leaving column. Where these stores fall
relative to the beam depends on the field (`smode`):

- **Ahead of the beam** (`smode` 1, the field that first shows a commit): iteration y
  stores line y + 1's bytes, just before that line is displayed (`k0` = (`wy` + 1)
  & 7).
- **Behind the beam** (`smode` 2, only for a 2-column step, in the field before it is
  shown): iteration y stores line y's bytes of the step's first column, after the line
  has been displayed (`k0` = `wy` & 7). They show from the next field, when the screen
  start moves.
- **Idle** (`smode` 0): both stores of every line go to one gap cell, column
  `mx + WIN_W + 7`, with zero (`pmask` = 0). That cell is always zero, so the stores
  change nothing, in the same time.

**The stores are absolute.** An indexed store makes a dummy read of its target first:
a second main-RAM access. So `sta cell_in` and `sta cell_out` are absolute, and their
operands are changed every line:

- **within a row**, the line blocks `inc` their low bytes;
- **at a row change**, the other gadget takes over, its addresses already prepared
  during the current row: the current row's cells + 576 (the next ring row), wrapped
  into the ring. They are computed from the live gadget, so a partial first row is
  harmless.

The next row's preparation is spread across the row's line blocks (`SLICE` in
`gen_loop2`):

| block | slice |
|---|---|
| A0 | `VO` ← `VON` (the new pair's odd-line byte) |
| A1 | `VE` ← `VEN`; the other gadget's entering address, low byte |
| A2, B1 | the entering address's high byte, ring-wrapped (the carry found again by `cmp`) |
| A3, B2 | the leaving address, low byte |
| A4, B4 | the leaving address's high byte |
| B0 | the entering address, low byte |
| A5 | `VNX`, the next pair's hash value, from `bq` and `permbx` |
| A6 | `VEN`, the next pair's even-line byte |
| B3 | `VON`, the next pair's odd-line byte |
| B5 | the leak byte: `tA6` loads `VO` or `ZB` for the next A row (4.5) |
| B6 | `bq`, the pair's block row, advances (mod 160) |

**The data.** The test pattern needs only two bytes per colour pair (a block row: an
even and an odd character row): `VE` for even lines and `VO` for odd, ANDed with
`pmask` (the block's left pixel black on its first column). An odd row's line 7 is 0.
So each tail loads `VE`, `VO`, `VEN` (line 0 of the next pair's even row), #0 (an odd
row's line 7) or `ZB`. For a game these would become tile fetches in the same slots.

**What `build` does** (strip.s, 998 cycles, fixed length, above the window it sets up):

- the columns: `sxin`/`sxout` from `colop` for a real strip, or the idle gap column,
  with `pmask` (the two paths balanced by `BLD_IDLE`);
- the first row's gadget (A or B by the row's parity) at line `k0` of its cells, and
  the other gadget at line 0 of the next row's;
- the first pair's bytes and the next pair's, with corrections for a first row that
  enters part way through the blocks that copy or advance them (`KEEPE`, `TAKEE`,
  `KEEPO`, `TAKEO`, `BQADD`);
- the entry tail (`wtP`) and first block (`VRET`), the exit (4.1) and the leak byte
  (4.5).

It touches no main RAM other than &7E07, and its paths take the same time with no
1 MHz access on them: `addrow` keeps its intermediate in a variable, not on the stack,
because a 1 MHz access's length depends on its cycle's phase, which would differ
between paths.

**Commit rules.** At most 2 columns a commit, and commits at least 2 fields apart
(enforced by `logic`), so a field is ahead, behind or idle, never two at once. With
the vertical limit (5.3) the top speed is one character a field across (200 MODE 1
pixels a second) and 2 lines a field down (100 lines a second).

### 5.2 The edge rows (colop.s)

The strip covers the window's lines, but not all the cells a step needs:

- **row top:** line 30 has no iteration before it (its blanking is the palette
  line's), so the ahead strip cannot store it;
- **row bot:** its lines below the window are never stored by the strip;
- **the look-ahead rows:** the rows just above and below the window must be right too,
  because the next vertical steps bring them into view (5.3).

`colop` writes these as whole characters, in the fixed-length work below the window.
Going right it writes five rows (top − 1, top, bot, bot + 1, bot + 2: the rows of
lines `wy` − 8, `wy`, `wy` + 169, `wy` + 177, `wy` + 185); going left, top − 2 to
bot + 1. Each row gets the entering cell (pattern) and the leaving cell (zero):

| row | entering cell (pattern) | leaving cell (zero) |
|---|---|---|
| top − 2 (left only) | – | if the class of (xout − 72) is due above |
| top − 1 | if class(xin) is due above | right: if class(xout) is due above; left: always |
| top, bot | always | always |
| bot + 1 | if class(xin) is due below | right: always; left: if class(xout) is due below |
| bot + 2 (right only) | – | if the class of (xout + 72) is due below |

- **Columns:** going right xin = `mx` + 56 and xout = `mx`; going left `mx` − 1 and
  `mx` + 55 (`XINL`, `XOUTL`). `colop` leaves them in `sxin`, `sxout` for the strip.
- **Classes:** "due" is the notch rule (5.3). A cell 72 columns on is the same memory
  as the neighbouring row's gap cell, and its class is the cell's class with bit 1
  flipped (72 columns is 18 blocks).
- **The behind field:** rows top and bot get only their hidden lines (line masks
  `MLINE`, through `PUTCM`): top's lines above the window and bot's below it. Their
  shown lines are the behind strip's, next field.
- **Fixed time:** an unwanted cell or line is stored to the dummy page (`SELP`,
  `PUTCM`), so `colop` takes the same time whatever is due.

### 5.3 A new row: the notch (notch.s)

Vertical steps are 2 lines, and the row about to come into view must be ready when it
does. The engine spreads the work over the four 2-line steps that bring a row from just
out of view to fully in view.

The map's columns are in four **classes**, class = (column >> 2) & 3: 4-character
blocks. With phase k = (`wy` & 7) / 2:

- a cell of the look-ahead row **below** the window must be right iff its class ≤ k;
- a cell of the row **above** iff its class ≤ 3 − k.

The row below is complete when k = 3, just as it comes into view; the row above when
k = 0.

**One step, one class.** A step down makes exactly one (row, class) newly due: the row
below the new last row, class k. A step up makes the row above the new first row due,
class 3 − k. The step draws exactly that: the class's cells across the row's 72-cell
span, pattern in the window's columns and zero in the gap's. The span is laid out
by the side of the window the row is on (`gkind`, `NSPAN`): for a row above, its 16
far-side gap cells then its 56 window cells, from column `mx` − 16; for a row below,
its 56 window cells then 16 gap cells, from `mx`.

**Plan, then store.** The drawing is split across the bottom of the frame (section 6)
so that its stores, the expensive part, are fixed-length work:

- `vstep` (variable-length work) moves `wy` by `dy` and has `nprep` fill a **plan**:
  the class's five blocks' addresses (`NBL`, `NBH`) and each of their twenty cells'
  three bytes (`NTE` for lines 0, 2, 4, 6; `NTO` for 1, 3, 5; `NT7` for line 7). A
  cell's bytes are its block's pattern ANDed with `NSPAN`: &FF in the window's part of
  the span, else 0. About 1,300 cycles. With no step, `nnull` aims all five blocks at
  the dummy page.
- `nstore` (the first fixed-length work after display end) writes the plan's twenty
  cells: five blocks of four cells (32 bytes, never across a page), eight stores a
  cell, the block's page patched into the stores. About 2,120 cycles, the same every
  field, step or not. It starts a page of its own (segment NSTORE) so that its loops
  never cross one.

**Every cell of the five blocks is written**, with no test per cell. The class's first
block starts up to 3 cells before the span and its last ends up to 8 after it; those
cells get zero. Along the tape row r's cell c is row r + 1's cell c − 72, so they are
either the neighbouring window row's gap cells, which are always zero, or cells of a
row two away from the window, which nothing requires and which are drawn class by
class once that row becomes a look-ahead row, before they are due.

At start-up `first_picture` (init.s) draws every class of the 25 rows from top − 1,
twice: first as rows above, then top down as rows below, so that each row's gap cells
on both sides are zero. A drawing as a row above zeroes a few window cells of the row
before, which the second pass redraws; one as a row below zeroes window cells of the
row after, which it draws next.

**Interactions.** A column step needs no bookkeeping: `colop` decides from the column's
class and `wy` alone (5.2). Reversing leaves extra classes drawn, which is harmless: a
class is drawn again whenever it becomes due.

**Cost and limit.** About 1,300 cycles of variable work in a field that steps, and
about 2,120 of fixed work in every field. There is one plan, so **at most 2 lines a
field** (`DYMAX` = 2, asserted in notch.s). A second class a field would need another
plan and another `nstore`'s time in the fixed work.

### 5.4 Why 56 characters at 16, and the one-column rule

**The position.** The longest lead-in, 8 µs on the real schedule, must end before the
window, and its last write takes a video slot that shows &7E07 (4.5). With the window
at character 16, that slot (h 120, character 15) is in the margin.

**The width** is set by the behind column. Going right, a 2-column step's first
entering column is stored a field early, behind the beam, in each row y's cell at
`mx` + 56. Along the tape that cell is row y + 1's cell `mx` + 56 − 72 = `mx` − 16, the
first of the 16 gap cells before row y + 1's window. In the early field the left
margin shows the `WIN_C` − t cells before the window (2.2), so it shows that cell when
`WIN_C` + `WIN_W` − 72 ≥ t.

- So `WIN_C + WIN_W` ≤ 72 (asserted in `gen.py`); at character 16, 56 is the widest.
- **The one-column rule.** With `WIN_C + WIN_W` = 72 the cell shows when t = 0 in the
  early field. So `logic` takes a 2-column step right as a single column whenever the
  field before the commit would have no lead-in. After that the lead-in's parity stays
  odd under 2-column steps, so the rule costs at most one field, once.

The research tree's 55-wide build at character 16 needed no such rule; the 57-wide one
at character 15 had it, and lost its first character to the leak at t = 7.

---

## 6. The bottom of the frame

From the exit at line 200 to the next lock read on line 0 there are 112 lines in a
312-line field (14,336 cycles), 113 in a 313-line one. `work` (frame.s) does, in order:

### 6.1 Variable work and the display-end poll

Variable-length work must end before display end, which the ULA flags at line 255
(MODE 4 is a graphics mode):

- the field parity (`fpar` alternates) and a write to &FE05 that clears the RTC and
  display-end flags, keeping the bank paged;
- the schedule keys: comma selects the FPGA schedule (`sched` = 0), full stop the real
  ULA's (`sched` = 8), on a new press (`SCHKEEP`, `SCHSET`);
- the keyboard (`kbd.s`, at &0900 in main RAM: reading the keyboard pages ROM 8 over
  the sideways bank);
- the trajectory (`logic.s`): this field's `dy` and the commit `hnew`;
- the vertical step and its plan (`vstep`, 5.3).

Then it polls &FE00 for the display-end flag. The poll absorbs all the variation, to
within one pass of its loop (a few µs), so this part needs no counting. The variable work has about 7,000 cycles before
line 255; the soak's worst end is line 223 (`VERIFICATION.md`), which leaves about
4,000. If it overran, the poll would return at once on the flag already set, the fixed
work would start late, and the next lock read would land late.

`bit ULA_STAT` instructions through the bottom of the frame are markers: harmless
status reads whose raster positions the emulator's I/O log records (the soak finds the
variable work's end by them; `test/fpmarkers.py` splits the fixed work by them).

### 6.2 Fixed work

From display end, every path is padded to the same length:

1. **The vertical step's stores** (`nstore`, about 2,120 cycles, a step or not).
2. **The column step**, one of three paths of equal length:
   - **a commit** (`cnext` ≠ 0, shown next field): `colop` for the ahead column with
     rows top and bot whole, `smode` = 1; then `mx` moves one column (`mx_step`), `wx`
     moves by `cnext`, and `k0` = (`wy` + 1) & 7. The two directions' paths are padded (`CAL_CP`, `CAL_CM`);
   - **the behind field of a 2-column step** (`cnext2` = ±2): `colop` for the step's
     first column with only the hidden lines of rows top and bot, `smode` = 2; `mx`
     moves by one, `wx` does not; `k0` = `wy` & 7. Padded by `CAL_BP` and `CAL_BEH`;
   - **idle**: `smode` = 0 and a delay in place of the edge rows (`CAL_NOC1`–`CAL_NOC3`,
     `CAL_NOC`: 3,846 cycles).
3. **The pipeline moves on:** `cnext` ← `cnext2`, `cnext2` ← `hnew`.
4. **Spare time** (`CAL_SPARE`, 676 cycles of `LDELAY`): a delay that a game's
   fixed-length work can replace.
5. **The next field's display parameters:** `setup_frame` (from `wx`, `wy`, `sched`:
   t, the screen start, the band's modes, the lead-in tables' entries) and `ula_apply`
   (&FE02, &FE03 and line 0's mode, written on line 311).
6. **`frame_tail`**, a counted delay to the lock read.

From display end to the lock read is about 7,200 cycles in a 312-line field. The
paths' lengths still differ by a few µs from field to field: `colop`'s and `nstore`'s
main-RAM stores are 1 MHz accesses whose length depends on their phase, and `co_inc`'s
mod-320 row wrap depends on the row. The lock's margin absorbs that (3.1).

### 6.3 The commit pipeline

`logic` chooses a commit (`hnew`) two fields ahead of its display: `hnew` → `cnext2`
→ `cnext`. A commit chosen in the bottom of field N:

| field | what happens |
|---|---|
| N + 1, bottom | for a 2-column commit: the behind field's edge rows (`colop`, hidden lines only); `mx` moves one column |
| N + 2, window | for a 2-column commit: the behind strip stores the first column |
| N + 2, bottom | the commit: the ahead column's edge rows; `mx` moves one column (its second, for a 2-column commit), `wx` by the whole commit |
| N + 3 | shown, the ahead strip storing the entering column just before the beam |

`logic` allows no commit while one is in the pipeline (`cnext2` ≠ 0) and spaces
commits by `hcnt`, so the rules of 5.1 hold.

### 6.4 `frame_tail` and the fields

PAL fields alternate 312 and 313 lines. `frame_tail` (segment TAILS, which shares a page
with `boot_sync`, asserted) counts to the next field's line 0: X = 2 `fpar` + `CAL_N64`
passes of a 64-cycle loop, then `CAL_REM` cycles, then the marker status read and
`jmp frame_top`. `CAL_N64` is at its minimum of 1 and `CAL_REM` is 10; the two extra
passes (128 cycles, a line) in the 313-line field are the only difference between the
fields. `fpar`, found once by `boot_sync` (3.2), simply alternates.

---

## 7. Timing discipline and calibration

Every cycle from the lock to the window's exit is counted, and the fixed work below
the window is balanced. The rules:

- **Delays are macros** with exact cycle counts (macros.inc): `PADN n` (`nop`s and one
  `jmp *+3` for an odd count), `DELAY n` (a counted loop that must not cross a page,
  asserted), and `LDELAY n` (21–1,296 cycles: a loop in its own page, `dlp` in segment
  DLOOP, entered by `jmp` and left by a `jmp` whose operand the macro patches, so it is
  exact wherever it sits and needs no stack).
- **No page crossings where timing matters.** A taken branch that crosses a page costs
  a cycle, and so does an indexed access whose index carries into the next page.
  - The window's line blocks sit in 64-byte slots, the window's variants share a page
    with `VX`, the tails share a page, `nstore`'s loops stay in one page, and `DELAY`
    loops never cross one: all asserted in the source.
  - Every table indexed in the fixed work is asserted not to straddle a page over its
    index range (`NOCROSS`), and every `jmp (vector)` clear of the 6502's &xxFF bug
    (`NOWRAP`).
  - `tools/pagecheck.py BUILD` lists every branch that crosses a page when taken. In
    both default builds the only one is in `logic` (VCODE), in the variable work,
    where it does not matter. DLOOP is page-aligned so that CODE starts 8 bytes into a
    page; when a change moves the fixed work's code, reordering CODE's files has been
    the cheapest fix.
- **Equal paths.** Each branch in the fixed work is balanced: with `nop`s, by storing to
  the dummy page (&2400, main RAM like the screen, so the store takes the same time)
  instead of skipping a store (`SELP`, `PUTCM`, `nnull`), or by padding a whole path
  (the `CAL_` pads below).
- **The window loop** is balanced by construction: `gen.py` counts every line block's
  cycles and pads it to `BLK_LEN`, and the gadget's pads (`PAD_W1`–`PAD_W3`) place its
  writes.
- **What remains** is the 1 MHz phase of main-RAM accesses (2 or 3 cycles each) and
  `co_inc`'s row wrap, which leave the fixed work's length varying by a few µs from
  field to field, well inside the lock's margin.

### 7.1 The constants (cal.inc)

| constant | value | what it sets |
|---|---|---|
| `CAL_TA` | 1,170 | free time from line 0, S + 3 µs, to the write on line 9 |
| `CAL_TB` | 280 | free time from the end of `build` to the write on line 19 |
| `CAL_TC` | 1,235 | free time from line 19 to the palette line |
| `CAL_CP`, `CAL_CM` | 31, 19 | pads for a commit going right, left |
| `CAL_BP` | 11 | pad for the behind field going right |
| `CAL_BEH` | 60 | the behind path after its edge rows |
| `CAL_NOC1`–`3`, `CAL_NOC` | 1,200 × 3, 246 | the idle path in place of the edge rows |
| `CAL_SPARE` | 676 | the fixed work's spare time (at most 1,296, one `LDELAY`) |
| `CAL_N64`, `CAL_REM` | 1, 10 | `frame_tail`: 64-cycle passes (+2 in the 313-line field) and the rest |
| `CAL_BTHR` | &594 | `boot_sync`: the poll count dividing the two fields |
| `CAL_BN64`, `CAL_BREM` | 109, 0 | `boot_sync`: display end to its lock read |
| `PAD_W1`, `PAD_W2`, `PAD_W3` | 0, 4, 3 | the gadget's pads: to MODE 3, to the lead-in mode, to the variant |
| `BLK_LEN` | 45 | a line block's length, so that an iteration is 128 cycles |
| `CAL_ENT` | 41 | the palette line's handover to the first window line: the loop's phase |
| `CAL_V20` | 23 | the window's variant 0, as long as the others given the loop's 1 MHz alignment |
| `BLD_IDLE` | 28 | `build`: pads the real path's column setup to the idle one's |

The loop constants (`PAD_W*`, `BLK_LEN`, `CAL_ENT`, `CAL_V20`) fix the picture's writes
and are not tuned against the fixed work. `CAL_TA`, `CAL_TB` and `CAL_TC` fix the
band's writes on lines 9 and 19 and the palette line: if `build` changes length,
`CAL_TB` changes by the opposite amount (the leak byte's 38 cycles came out of it).

### 7.2 Retuning after a change to the fixed work

1. **Fingerprint** the old and the new build over the same trajectories:
   `test/fingerprint.sh OUT WX WY SEED TRAJ MODEL FIELDS` (MODEL `real` or `fpga`;
   `SCRMODE=2` in the environment for the MODE 2 window). It builds with `MOTION=1`
   and the model's schedule, so no key press steers it, and records every &FExx access
   of every field with its raster position.
2. **Compare** with `python3 test/fpcompare.py OLD NEW`. For each field it reports the
   picture writes (&FE07–&FE09 from line 0 to the exit), which must be identical; the
   fixed work's length (from the display-end poll's last read to `ula_apply`'s &FE02
   write); and the lock read's position; with histograms of the differences in cycles.
   `python3 test/fpmarkers.py FP` splits one fingerprint's fixed work into its sections
   by the marker reads.
3. **Adjust.** Move `CAL_REM` (or `CAL_SPARE`) by the change in the fixed work's
   length, so that the lock read stays where it was: one cycle is 0.5 µs, 8 units of
   h. If the change affects only some paths, adjust those paths' pads. `CAL_N64` is at
   its minimum, so lengthening the fixed work beyond `CAL_SPARE` + `CAL_REM` would
   push the lock read late.
4. **Confirm with the soak**: `test/soak.sh` (`-n` fields, `-r` runs). Each run's
   summary line ends `lock read h A..B`: the range, over every field, of the marker
   read before the lock read, in 1/16 µs of line 0. The current builds give h 152–488;
   keep the range well inside line 0's fetches, remembering that the `SYNCB` read
   itself follows the marker by 3 µs (3.1). The same line gives the variable work's
   latest end ("ended by line").
5. Run `tools/pagecheck.py` on the build: a new crossing branch in the fixed work adds
   a cycle to one path.

---

## 8. Source map and build options

| file | segment(s) | what |
|---|---|---|
| `elkscroll.s` | – | the root: includes everything in the order that fixes the layout |
| `cal.inc` | – | the cycle calibration (section 7) |
| `hw.inc` | – | ULA registers and fixed main-RAM addresses (`SYNCB`, `KBD`, `KEYS`, `DUMMY`, `LEAK`) |
| `macros.inc` | – | `PADN`, `DELAY`, `LDELAY`, `SELP`, `PUTCC`, `PUTCM`, `NOCROSS`, `NOWRAP` |
| `raster.s` | DLOOP, ENTRY, LOOP | the `LDELAY` loop; the entry at &8000; `frame_top`, the free time, the palette line; includes the generated window code |
| `gen_loop2.s` (generated) | LOOP2, TABLES3 | the gadgets, the sixteen line blocks, and their tables |
| `gen_variants.s` (generated) | VARIANTS | `VX` and the variants `VS2u`, `VSPu` |
| `init.s` | VCODE, TAILS | start-up, `first_picture`; `boot_sync` |
| `logic.s` | VCODE | the trajectory: script, random walk, keys |
| `notch.s` | VCODE, NSTORE | `vstep`, `nprep`, `nnull`, `ndraw`; `nstore` |
| `colop.s` | CODE | the edge rows |
| `strip.s` | CODE, TABLES4 | `build` |
| `frame.s` | CODE, TAILS | the bottom of the frame; `frame_tail` |
| `display.s` | CODE | `setup_frame`, `rowaddr`, `ula_apply`, `addrow` |
| `tables.s` | TABLES, TABLES2 | `gen_tables.s` (generated), then the hand-written tables |
| `vars.s` | VARS | the variables (no zero page is used) |
| `kbd.s` | KBDCODE | the keyboard scan, at &0900 in main RAM |
| `loader.s` | LOADER | the program file at &2000: finds a sideways RAM bank, copies the image and the keyboard routine, enters at &8000 with the bank in A |

`cfg/elk.cfg` places the segments in the 16K bank; `cfg/loader.cfg` the loader at
&2000. In the default builds (both modes alike):

| segment | addresses | segment | addresses |
|---|---|---|---|
| ENTRY | &8000–&8002 | TABLES | &9300–&9FCF |
| LOOP | &8003–&807B | TABLES2 | &A000–&A245 |
| LOOP2 | &8100–&852B | TABLES4 | &A246–&A29F |
| TAILS | &852C–&85D1 | TABLES3 | &A300–&A3F8 |
| VARIANTS | &8600–&870C | NSTORE | &A400–&A45C |
| DLOOP | &8800–&8807 | VCODE | &A45D–&ABB7 |
| CODE | &8808–&9251 | VARS | &AC00–&ACC4 |
| KBDCODE | &0900–&0974 (main RAM) | | |

CODE holds only fixed-length work, in an order (colop, strip, frame, display) in which
no branch on a fixed path crosses a page. VCODE holds variable-length work, out of
CODE's way. The image uses &8000–&ACC4, about 11.2K of the 16K bank. Main RAM holds the
screen ring (&3000–&7FFF), the dummy page (&2400), the keyboard routine (&0900), its
results (&0A00–&0A02), `SYNCB` (&0200) and the stack.

**Generated files** (`tools/gen.py OUTDIR`, run by the Makefile into `BUILD/gen`):
`config.inc`, `gen_tables.s`, `gen_variants.s`, `gen_loop2.s`, and `model.bin`, the
pattern for the soak's checker. Everything generated is a pure function of `gen.py`'s
constants and `SCRMODE`.

**Make targets:**

| target | what |
|---|---|
| `make` (`all`) | both demos: `build/mode1/elkscroll_mode1.ssd`/`.uef` and `build/mode2/elkscroll_mode2.ssd`/`.uef` (DFS files `ELKSCR1`, `ELKSCR2`; titles "ELK SCROLL 1", "ELK SCROLL 2") |
| `elkscroll_mode1`, `elkscroll_mode2` | one of them |
| `make one SCRMODE=1\|2 BUILD=dir` | one demo, in `dir` |
| `make bin` | both, copied into `bin/` (the prebuilt images in the repository) |
| `make run_mode1`, `make run_mode2` | build and open in `elkview` with the real-ULA model (`--realula`) |
| `make emu` | the emulator harness, `build-emu/elkh` and `build-emu/elkview` |
| `make test` | `test/soak.sh -n 5000` |
| `make clean` | removes `BUILD` |

The disc images have boot option 3 (SHIFT+BREAK); the tape images load with `*RUN`.
The program loads and runs at &2000.

**Build options** (`make NAME=VALUE`; each is passed to ca65 as `-D NAME=VALUE`, except
`SCRMODE`, which goes to `gen.py`; defaults in init.s):

| option | default | |
|---|---|---|
| `START_WX`, `START_WY` | 1283, 1280 | the map position at start (`START_WY` even, asserted) |
| `TRAJ` | 0 | 0: the demo script (`gen.py` `SCRIPT`); 1: a random walk |
| `SEED` | &ACE1 | the random walk's seed |
| `MOTION` | 0 | 1: moving from the start (otherwise SPACE starts and stops it) |
| `SCHED` | 8 | the lead-in schedule at start: 8 the real ULA's, 0 the FPGA's |
| `SCRMODE` | 1 | the window's mode, 1 or 2 (section 9) |

`DYMAX` (2) and `SCR0` (the script segment to start at) are also read by init.s but
are not passed through by the Makefile.

---

## 9. The MODE 2 window

`SCRMODE=2` builds a **112 × 170-pixel MODE 2 window** with sixteen logical colours,
eight of them distinct, from the same engine. MODE 0, 1 and 2 fetch identically: 80
bytes a line, one every half microsecond. So the ring, the lead-in, the blip, the
strip and the notch all work on bytes unchanged. A character is still 8 bytes, now 2
pixels wide; a column step is 2 MODE 2 pixels; a pattern block is 8 × 16 pixels. The
assembly has no conditional code for it: the two builds differ only in generated
values, and their segments lie at the same addresses.

### 9.1 The palette

The register pairs are independent: pair (&FE08 + 2i, &FE09 + 2i) holds logical colours
base_i | {0, 2, 8, 10}, base = 0, 4, 5, 1 (`ULA-NOTES.md` section 9; `palette_bytes2`
in `gen.py`). Every mode except MODE 2 uses only colours 0, 2, 8 and 10, which &FE08 and
&FE09 hold. Hence:

- &FE0A–&FE0F are written once, in `boot_sync`, and never change. They are &FF in a
  MODE 1 build. They are written there (segment TAILS) rather than in `init` so as not
  to move CODE.
- The palette line and the exit black out the window with &FE08/&FE09 exactly as in
  MODE 1.
- Only the window's lines are MODE 2. Above and below the window the lines are as in a
  MODE 1 build, and show only colours that &FE08/&FE09 hold.

### 9.2 What changes

| | MODE 1 build | MODE 2 build |
|---|---|---|
| `MW`: the variants' write, the gadgets' `lda #MW` | &08 | &10 |
| the lead-in mode (`VC_BY_X`: the gadgets, the palette line) | mode 7 / MW | mode 7 / MW |
| the tail's write (`VA_BY_X`, X in the window) | MODE 5 / MW | MODE 5 / MW |
| `LMASK`, the block's black left pixel (`PMASK`, `PEM`, `POM`) | &77 | &55 |
| &FE08, &FE09 | &97, &D3 | the MODE 2 palette |
| &FE0A–&FE0F | &FF | the MODE 2 palette |

### 9.3 The test card

The MODE 2 test card uses the Amstrad CPC's palette. Each of the CPC's 27 colours has
red, green and blue each off, half or full, and is the average of two of the Electron's
eight: A, with every component that is at least half on, and B, with every component
that is full. A block is A and B in a 1 × 2 dither: the pair alternates along each line
and swaps on the next. Those are exactly the even-line and odd-line bytes the engine
already carries per colour pair (`VE`, `VO`), so the strip's data path is unchanged.
The 26 colours other than black are used, so the grid stays visible. Logical colour L
shows colour L, or 15 − L above 7, so each colour has two logical names; each colour
of a pair appears under one of them, so the picture uses every palette register.
`model.bin` carries the mode and the palette for the soak's checker.

---

## 10. Toward a game engine

The display engine is complete; the test pattern stands in for a game's map. A game
would replace or add:

- **Map data.** The pattern's tables (`PERM`, `PE`, `PO`, `PEM`, `POM`) and their use in
  `build`, `colop`, `nprep` and the line blocks' data slices become tile lookups: each
  fills a cell's eight bytes, or the next line's entering byte, from the map, in the
  same fixed time.
- **The leak byte.** &7E07 must be zero at every write of 4.5, which in practice means
  from the end of `build` to line 199. A game that draws into the ring must not store a
  non-zero byte there in that time (that is, in `CAL_TB`, `CAL_TC` or the window), or
  must use the mirror scheme of 4.5.
- **Sprites.** The engine is single-buffered, so a sprite is drawn into the ring and
  erased again. A sprite over the entering or leaving column on a raced line needs
  care: the strip overwrites those cells as the beam passes. Draw sprites after the
  commit field's window, or keep them a column inside the edges.
- **Time.** As it stands the engine holds the CPU from line 0 to line 200, so game
  logic and sprite work fit in:
  - the variable work before display end: about 7,000 cycles less the keyboard, the
    trajectory and the vertical step's plan, about 4,000 in the worst field (6.1);
  - the free time above the window: 2,685 cycles of fixed-length work, with main RAM
    at 1 MHz (3.3), in three pieces separated by the band's writes on lines 9 and 19;
  - the spare time below it: 676 cycles of fixed-length work (`CAL_SPARE`);
  - the line blocks' padding: each is 45 cycles and uses at most 40.

  Anything placed in the fixed-length slots must take the same time on every path. A
  game may also run its logic at a lower frame rate than the display.
- **Constraints.** X must hold the blip's value through the window. Everything from the
  tail's write to the variant's write must stay as listed in 4.1. Commits must stay
  within 2 columns and 2 fields apart, and vertical steps within 2 lines a field.

---

## 11. Known limitations and open questions

**On a Ferranti ULA, the row at &7FC0 is displayed wrongly at t = 7 on the real
schedule.** Mode value 7, the lead-in mode, wraps at &8000 to &3000 on a Synertek ULA
but to &5800 on a Ferranti, where it is plain MODE 4 (4.3). So on the Ferranti a
line's 40-column lead-in must not cross &8000. With the real schedule's 8 µs lead-in
(t = 7, the MW write at 8 µs) a line takes eight 40-column steps from its row's start;
rows start on 64-byte boundaries, so the ring row that starts at &7FC0 takes its eighth
step across &8000. On a Synertek ULA that is wrapped to &3000 and the line is right; on
a Ferranti it is wrapped to &5800 and every line of that character row shows the wrong
bytes. For any screen start exactly one of the ring's 320 rows starts at &7FC0. The
engine does not avoid this yet. In the emulator, in a build with a MODE 4 lead-in (what
a Ferranti does with mode value 7), it affected about 1.5% of fields on random walks,
always exactly that one character row (8 lines), at t = 7. Possible fixes: keep the
lead-in out of a 40-column mode when it crosses &8000, for example with a MODE 1 hole
across the step from character 7 to 8 on that row's lines; or row starts that avoid
&7FC0. The probes that established the real schedule ran on a Ferranti ULA, so this is
the platform the real schedule was measured on.

**The leak byte** (4.5). &7E07 must hold zero; the engine keeps it so at the cost of one
black byte in the picture and 38 cycles a field. Not yet tested on hardware: that the
leaked byte follows the alias (a write to &FEF7 showing &7EF7); whether &FE01 or page
&FF reach the mode register; whether writes to pages &FC and &FD, which the ULA also
stretches to 1 MHz, take a slot; whether the tail's write at S − 3 µs in the right
margin shows the byte as the lead-in's write does (the hardware reports describe only
the left-margin bar).

**The exit's writes.** `VX` writes &FE08 and &FE09 and then &FE07 (MODE 4) in the first
8 µs of line 200: the &FE08 write at the cycle position of a variant's +24 µs write
(about h 8 in the emulator's phase), the &FE07 write at h 120. Line 200 is fetched (in
the lead-in mode, or MW when u = 0), so by the leak rule these slots would show &7E08,
&7E09 and &7E07. &7E07 is zero, and once &FE09 is written the palette is black, but
when the &FE08 write lands, &FE09 still holds the window's red and green bits, so a
non-zero &7E08 might show on line 200, left of the window. This has not been analysed
or looked for on hardware.

**The emulator** (the CLK fork, `emu/clk`) models neither the leak nor the Ferranti's
mode value 7. Its real-ULA switch (`Electron::VideoOutput::real_m5_phase`; elkh
`realula 1`, elkview `--realula`) models the Ferranti's 40-column address phase and the
Synertek's mode-7 wrap to &3000 together, a combination no real ULA is known to have, so
it does not reproduce the &7FC0 failure. The soak's model treats the leak byte as black
wherever the window fetches it, which matches what the engine stores, not what a ULA
does.

**Untested ULAs and phases.**
- Synertek ULAs: their 40-column address phase has not been measured, so which schedule
  they need is unknown. Earlier logic-analyser captures (sync, display end, RTC, field
  alternation) found Ferranti and Synertek within 1–2 ticks of each other
  (`ULA-NOTES.md`).
- The replacement ULAs (the FPGA, JamSoft, budgie's) have been checked only in models.
  On an FPGA ULA the CPU/video phase varies from power-up to power-up; between them the
  two schedules covered every phase in simulation of the 55-wide sibling (4.4).
- `check_schedules` models only the FPGA schedule, and the blip only at t = 0; the code
  also blips at t = 1 on the FPGA schedule (4.2). The soak on the FPGA model passes
  with it.
- On a real ULA the CPU/video phase has been seen on one machine only.

**What has and has not run on hardware.**
- Probe programs 1–9 ran on an issue 6 Electron with a Ferranti ULA. They established
  the real ULA's 40-column address phase (the real schedule).
- On 21 November 2026 the 57-wide build at character 15 and the 56-wide build at
  character 16, before the leak byte was kept zero, ran on a real Electron whose ULA
  type was not recorded. The picture locked and scrolled; they showed the leak (4.5).
- **This build** — 56 wide with the leak byte kept zero, and the single-read lock — has
  not yet run on hardware. Its evidence is the emulator's (`VERIFICATION.md`).

**Other limits of the engine as it stands.**
- At most 2 lines a field vertically (one notch plan) and 2 columns every 2 fields
  horizontally.
- Single-buffered: everything drawn into the ring is drawn where the beam will show it.
- The lock's margin, about 12 µs early and 7 µs late, has been measured only in the emulator, on one
  CPU/video phase.
- If the variable work overran display end, the field's lock would be lost (6.1).
- Not quite fixed-length: `colop`'s step to the next row of a run (`co_inc`) wraps the
  row number at 256 and 320, and takes about 16, 24, 29 or 33 cycles depending on the
  row, so a run that crosses one of those rows varies the fixed work by up to about 17
  cycles (8.5 µs). The soak's lock-read spread (h 152–488) includes it, but with the
  single-read lock's margin it is worth balancing.
- The demo's commit gap: `logic` sets `hcnt` to the gap less one, so gaps of 2 and 3
  fields both give a commit every 2 fields (the `cnext2` check enforces the minimum of
  2). This changes only the demo's speeds.
