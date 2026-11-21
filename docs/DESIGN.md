# elkgame: design of the scroll engine

This document explains how the demo puts a 224 × 170-pixel MODE 1 window on an Acorn
Electron and scrolls it at 50 Hz. It covers the display tricks first (sections 2–4),
then how the picture is kept up to date as it moves (5), then the frame's timetable
(6) and the timing discipline that holds it together (7). Section 9 says what a game
built on the engine would add, and section 10 how the same engine shows a 112 × 170
MODE 2 window.

The ULA behaviour everything depends on is set out, with sources, in
[`ULA-NOTES.md`](ULA-NOTES.md), and the evidence that it works is in
[`VERIFICATION.md`](VERIFICATION.md). File references are to `src/` unless they say
otherwise.

**Conventions.**
- Times inside a line are in **µs after S**. S is the moment a stalled main-RAM read
  completes: in a 20K mode, at the end of the line's display fetches, about h 648 of
  1024. It is the only raster position a program can observe on the Electron, and
  every write in the scanline loop is placed relative to it.
- Raster positions `h` are in 1/16 µs, 0–1023 across a 64 µs line, with h = 0 at the
  first displayed pixel.
- **Cycles** are 2 MHz CPU cycles: 128 to a line.
- A **character** is a MODE 1 character: 8 bytes, 4 pixels wide and 8 scanlines high.

---

## 1. The problem

The Electron's ULA displays a 20K MODE 1 screen as 320 × 256 pixels: 80 characters
(8-byte, 4-pixel cells) across, by 32 rows of 640 bytes. The hardware offers very
little to scroll with:

- **No fine scroll.** The screen start register (&FE02/&FE03) holds address bits
  14..6, so it moves in steps of 64 bytes: 8 characters across, or roughly a tenth of
  a row down.
- **No raster interrupt.** There are only two video events, display end and the
  "RTC" event at line 99, each once a field.
- **The CPU is starved.** Main RAM is shared with the display. While the ULA fetches
  in a 20K mode, any main-RAM access stalls until the end of the line's fetches. So
  code running from main RAM gets almost nothing done during the visible part of the
  screen. Sideways RAM (&8000–&BFFF) is on the CPU's own bus and runs at a full
  2 MHz, so the engine lives there.
- **No double buffer** worth having: 20K is all the screen RAM there is.

The engine works round all four:

- **Horizontal fine scroll** comes from changing the screen mode partway through every
  scanline (section 4).
- **Vertical fine scroll** comes from a band of text-mode rows at the top of the frame
  (section 2).
- **Timing** comes from a stalled read that locks the program to the raster once a
  field. Interrupts are off and every cycle from there to the window's last line is
  counted (sections 3 and 7). Outside the window, the frame stays in 40-column modes
  (MODE 4 and 6), where the CPU's main-RAM accesses are never held up.
- **New picture** is written as the window moves, at a fixed and small cost per field.
  A new column is written by the scanline loop itself, one byte a line, just ahead
  of the beam. A new row is drawn a quarter at a time (section 5).

---

## 2. Screen geometry and memory

### 2.1 The window

| | |
|---|---|
| size | 56 characters × 170 scanlines = 224 × 170 pixels |
| position | screen character 16 (of 80) across; lines 30–199 |
| above it | lines 0–29: black. Lines 0 and 1 are MODE 1 or MODE 3 (for the lock); the rest MODE 4, with 0–3 rows of 10-line text mode (MODE 6) at the top |
| below it | lines 200–312: black, MODE 4 (display end at line 255) |
| palette | black, cyan, magenta, yellow; set on line 29, blacked out at line 200 |

`gen.py` sets the geometry (`WIN_C`, `WIN_W`, `Y0`, `Y1`) and writes it to
`config.inc` for the assembler.

### 2.2 The ring

The ULA displays 80 characters a line, but the engine lays the 20K screen ring out
(&3000–&7FFF, which the ULA wraps) as rows of **72 characters (576 bytes)**. Each
displayed line therefore fetches only 72 to 79 characters before the next row begins,
and a row's 72 cells hold the window's 56 and 16 gap cells, which are kept zero (black).

Why 72 and not 80:

- **Coarse scroll is cheap.** The screen start register moves in 64-byte steps, and a
  576-byte row is exactly 9 of them. So a one-character coarse step across is a change
  of screen start by 8 bytes, folded into the lead-in (section 4), and a one-row step
  down is a change of 576 bytes.
- **The display start-of-row register holds address bits 14..6.** Each line's fetch
  must end with the counter on the next row's 64-byte boundary: rows 576 bytes apart,
  9 × 64 (section 4.2).
- **The window is narrower than 80 characters anyway**, because the lead-in eats the
  left of the line.

Map character (x, row y) is at `&3000 + (576 y + 8 x) mod &5000`. So the ring is one
"tape" of cells, and the window's rows are 72 cells apart along it. As the window moves
right, every row's window slides one cell along the tape:

- the cell entering at the right edge is the old gap cell next to it;
- the cell leaving at the left becomes the new gap cell.

Nothing is ever moved in memory. 320 rows of 576 bytes is exactly 20K, so map rows
wrap round the ring every 320 rows (`R576L`/`R576H`, `RINGHI`, `WRAPHI` in
`gen_tables.s`).

### 2.3 The map and the coordinates

The playfield is a map of 2560 × 2560 characters that repeats in both directions. The
position is held as:

- `wx`: the map column at the window's left edge;
- `wy`: the map scanline at its top;
- `mx`: the window's left column as the ring currently holds it.

`mx` runs ahead of `wx` during a column step (section 5.1). The test pattern is a
hash of 16 × 16-pixel blocks (`gen.py` explains it). A game would have tiles here
instead (section 9).

### 2.4 Vertical fine scroll: the band

Vertical position is coarse plus fine:

- **Coarse.** The screen start picks the character row of map scanline `wy`.
- **Fine.** `f = ((Y0 − wy) & 7) / 2` rows of 10-line text mode at the top of the
  frame push the rows below down by 2f lines. They are MODE 6, except that lines 0 and
  1 are MODE 3, so that the lock's reads stall (3.1).

Vertical steps are therefore 2 scanlines, and `wy` is always even. The lines above the
window are black: the palette is black until line 29.

**The rows above the window.** Below the band, the rows are MODE 4, 8 lines each. There
are always exactly three rows above the window's first: 10f + 8 (3 − f) + (wy & 7) =
30 = Y0. Each is 320 bytes, the 40 characters a MODE 4 or MODE 6 line fetches, so:
- every row starts aligned (320 is a multiple of 64; 4.2), with no per-line writes;
- the screen start is the window's first row less 960, always at least &2C40: the
  counter never wraps above the window.

The band ends on line 10f − 1 with a switch to MODE 4 at S + 17 µs, after that line's
row counter has rolled over and before the next line's first fetch (`ULA-NOTES.md`
11.3). The switch for f = 1 and 2 is written on lines 9 and 19 by table (`W9TAB`,
`W19TAB`: MODE 4 there, MODE 6 to carry on). For f = 3 it's the palette line's lead-in
write on line 29. `setup_frame` (display.s) works out the screen start, `f`, and the
modes: lines 0 and 1 (`TOPMODE`), the band (`TOP2`) and the two switches.

---

## 3. The frame and the scanline loop (raster.s)

### 3.1 The lock

Interrupts are off for good. Each field starts with `frame_top`, two reads of a
main-RAM byte (`SYNCB`):

- The first is aimed late in line 0.
- The second is aimed mid line 1.

Lines 0 and 1 are MODE 1, or MODE 3 when there is a band. In those modes a read stalls
until that line's fetches end (S), so the second read always returns at S of line 1. The first read exists so that the lock tolerates
errors: if the work below the window took a little too long, the first read lands
after line 0's fetches and returns at once, and the second still stalls. The
work below the window may be off by about **±20 µs** with every field still
pixel-exact, so the fixed work need not be counted to the cycle. Its measured spread
is about 12 µs (section 7).

**One read (`LOCK1=1`).** A read issued anywhere in line 0's fetches, h 0 to S (about
h 648), already stalls to S; the second read only extends the late side. Across the
soak the lock read is issued at h 344–680 of line 0, a spread of about 21 µs, so a
single read aimed 24 cycles (12 µs) sooner (`CAL_L1S`, taken from `CAL_SPARE`) lands
at h 152–488, inside line 0's fetches with about 10 µs to spare on either side. The
counted code then starts at S of line 0, a line sooner: the switch to MODE 4 (or 6) is
on line 0 instead of line 1, and `CAL_TA` is 128 cycles longer, so every write from
line 9 down is where the two-read lock puts it and the free time above the window is
2,685 cycles. `boot_sync`'s read already lands mid line 0 (h 312) and is unchanged.
The cost is the margin: about ±10 µs, against −21/+26 µs with two reads, on one CPU/
video phase in the emulator. Too early is the worse failure: a read issued before line
0's fetches returns at once, and every later field's read arrives too early as well.
The two-read lock stays the default.

**Above the window: free time.** Just after the lock the mode goes to MODE 4 (or MODE 6
in a band). In a 40-column mode the ULA fetches without holding up the CPU: a main-RAM
access is an ordinary 1 MHz one. The lines down to the palette line need no per-line
writes (2.4), only the band's two possible switches on lines 9 and 19. So the time
between is free for fixed-length work:

| from | to | what | cycles |
|---|---|---|---|
| line 1, S + 3 µs | line 9, S + 17 µs | `CAL_TA` (delay) | 1,042 (`LOCK1`: from line 0, 1,170) |
| line 9 | line 19, S + 17 µs | the strip build for this field's window (`build`, 5.1), then `CAL_TB` | 998 + 280 |
| line 19 | the palette line | `CAL_TC` | 1,235 |

That is 2,557 cycles of delay a game can replace with its own fixed-length work, such
as sprite drawing, with main RAM at 1 MHz.

### 3.2 The loop

From the free time, the program counts to the first iteration. Each **iteration** is
exactly 128 cycles, one line. Iteration y runs from the right margin of line y to the
lead-in of line y+1, and makes these writes (µs after S of line y):

| µs after S | write | |
|---|---|---|
| −3 | &FE07: the **blip** | MODE 5 when the lead-in is 0 or 1 µs, else MODE 1 (no change). Section 4.2 |
| ~0 | first store | window: the entering column's byte (section 5.1) |
| ~+3 | second store | window: the leaving column's zero |
| +9 | &FE07: MODE 3 | inside the line sync. Section 4.2 |
| +15 | &FE07: the lead-in mode | mode 7 (a 40-column mode), or MODE 1 if there is no lead-in |
| +23+u | &FE07: MODE 1 | the **variant**: u nops then the store (none when u = 0). Section 4 |

The loop has two parts:

- **the palette line** (iteration Y0−1): its two stores are the palette's, &FE08 and
  &FE09. It has no blip, because its line is a 40-column one.
- **loop 2**: the window, iterations Y0..Y1−2, below.

**Loop 2: two gadgets and sixteen line blocks** (`gen_loop2.s`, generated by `gen.py`).
The horizontal-blanking code exists twice, as **gadgets**: gA for even map rows and gB
for odd. Each begins with an 8-byte block holding both store addresses:

    gP:   sta cell_in       ; the entering cell <- A (this line's byte)
          lda #0
          sta cell_out      ; the leaving cell <- 0
          lda #M3
          sta &FE07         ; +9: MODE 3 in the sync
          (pad)
          lda #vc           ; patched each field: the lead-in mode
          sta &FE07         ; +15
          lda #M1
          (pad)
          jmp (VJ)          ; the variant (c41), or VX on the last line

The variant writes MODE 1 and returns through `jmp (VRET)` to the **line block** for
the next line. There are sixteen, b{P}{k}, one for each line k of a row of each parity
P. Each is exactly `BLK_LEN` cycles and does, for the line about to be stored:

1. its slice of the next row's preparation (section 5.1);
2. `inc` of the two store addresses' low bytes in its own gadget, stepping them one
   byte down their cells (a cell is 8-aligned, so there is never a carry). The line-7
   blocks skip this;
3. `VRET` ← the next block. The blocks sit in 64-byte slots, four to a page, so only
   the blocks at k = 3 and 7 set the high byte;
4. its tail: the next line's entering byte into A, the blip (`stx &FE07`; X holds the
   blip's mode value throughout the loop), and `jmp` to the gadget (the other one after
   line 7).

Registers: A carries the data byte into the gadget, X is the blip value, and Y is
scratch for the blocks. Because each block knows its own line and row parity, no
register is needed to count lines.

### 3.3 The exit

The last window line (line 199) goes to **VX** instead of a variant:

- black palette (&FE08 = &FE09 = &FF);
- MODE 4 for the rest of the field;
- then `jmp work`, the bottom of the frame (section 6).

MODE 4 is a graphics mode, so display end is flagged at line 255, six lines later than
in a text mode such as MODE 6. It is a 40-column mode, so main RAM is not contended. The redirect happens in the visible part of the second-to-last line:

- **Arming.** The line-7 blocks count rows down (`rows`, set by the builder). The one
  that brings the count to zero patches one chosen block's `lda #<next` / `sta VRET` to
  `lda #<VX` / `sta VJ`.
- **The redirect.** When that block next runs, VJ points at VX, so the last line's
  gadget exits.
- **Restoring.** The builder restores the patched block each field.

The window's variant set and VX share a page, so `VJ` only ever changes by its low
byte.

---

## 4. Horizontal fine scroll: the lead-in

### 4.1 The mechanism

In a 40-column mode (MODE 4, 5, 6 and mode value 7) the ULA fetches a byte every
microsecond. In MODE 1 it fetches one every half microsecond. The mode register
takes effect mid-line, and the address counter keeps running from wherever it had
got to.

So each window line starts in a 40-column mode, which is black here because the
palette's 40-column colours are all black, and switches to MODE 1 t µs into the line.
The line has then fetched t characters where MODE 1 would have fetched 2t: its address
falls t characters behind. Its first visible MODE 1 character is the one t
characters before where it would have been. With t = 0..7 and the screen start in
8-character steps, the window can start at any character of the map:

- t = (`WIN_C` − wx) & 7;
- the screen start is at column wx − `WIN_C` + t, which is a multiple of 8.

The window starts at character 16 because the longest lead-in (8 µs on the real ULA,
section 4.3) must be over before the window's first pixel, and its last write takes a
video slot of its own (4.5).

### 4.2 Keeping the rows aligned: the blip and MODE 3

The start-of-row register latches the address at the end of each character row's
last line and reloads it for each line of the next row. It holds bits 14..6 only, so
a line must end with the counter in the right 64-byte block: the row's start + 576.

**The fetch count.** A line with a t-µs lead-in fetches 80 − t characters, and
(80 − t) / 8 rounds down to 9 for t = 1..7: 576 bytes. With t = 0 the line would fetch
all 80 characters, and (80 / 8) = 10 blocks is one too many. So when there is no
lead-in, a write 3 µs before S (the **blip**) puts the right margin into MODE 5 for its
last 2–3 µs. The line then fetches 77–78 characters, which rounds down to 9.

**The row ends.** Lines end at different positions, so line 0 of each row would
otherwise start from the untruncated counter, not the latch. A write of MODE 3, a text
mode, inside every line sync fixes this. In a text mode, line 7 of a row is not a
"last line", so the counter is reloaded from the latch, and line 0 of the next row
starts at the row's first character like every other line. Graphics mode is back
before the sync ends.

`gen.py` checks all of this against a model of the FPGA ULA's fetch timing at every
phase in `S_RANGE` (`check_schedules`); the build fails if any schedule fails.

### 4.3 Two ULAs: the schedules

hoglet's [ElectronFpga](https://github.com/hoglet67/ElectronFpga) HDL steps the
40-column address in the second half of each microsecond. Probe programs on a real
(Ferranti, issue 6) Electron showed that **the real chip steps it in the first half**.
A mode write lands between the two, so the real chip loses one character fewer in the
switch. Hence two schedules:

| | the MODE 1 write (variant u) | the blip |
|---|---|---|
| FPGA ULA (`sched` = 0, comma) | u = t µs into the line | when u ≤ 1 |
| real ULA (`sched` = 8, full stop; the default) | u = t + 1 (0 when t = 0) | when u ≤ 1 |

`setup_frame` indexes the dispatch tables (`VSP_BY_X`, `VS2_BY_X`, `VA_BY_X`,
`VC_BY_X`) by `(wx & 7) | sched`.

**Why mode 7, not MODE 5.** With the real chip's 8 µs lead-in, a line takes eight
40-column steps. On the row that starts at &7FC0, the eighth step crosses &8000. MODE 5
wraps &8000 to its own base, &5800, which would be wrong here. Mode value 7 is
undocumented: it fetches like MODE 4 and wraps to **&3000** on the real ULA (the CLK
fork models this when its real-ULA switch is on). The FPGA schedule never takes an
eighth step: `gen.py` forbids a MODE 5 step from character 7 to 8.

### 4.4 The phase between CPU and video

The CPU's 1 MHz slots and the ULA's pixel counter run off the same clock, but nothing
sets their relative phase at power-up. `gen.py` has a model of how a write placed
relative to S lands relative to the fetches, as a function of that phase:
`_sim`/`sched_ok`, matched to an nvc simulation of the FPGA HDL. Every FPGA schedule
works at all 12 phases in `S_RANGE` (S = 648..659).

In the HDL simulation of the engine's 55-wide sibling, the FPGA schedule passed at
14 of the 16 phases. The real schedule covered the other two, so between them the two
schedules cover every phase (`VERIFICATION.md`).

### 4.5 The leak byte: what a mid-line ULA write shows

On a real ULA a CPU write to a ULA register while the ULA is fetching for the display
takes that video slot: the slot's RAM cycle uses the CPU's address with A15 dropped,
so instead of its own byte the slot shows **RAM[&7E00 + the register's address low
byte]**, painted in the new mode. Reads seem not to: every window line reads &FE00 in
mid-window, and nothing shows there. Neither the CLK fork nor the FPGA HDL models it
(`ULA-NOTES.md` 15.4). It was found on hardware with this engine:

- **The lead-in's last write** is the window's mode to &FE07, at t + 1 µs on the real
  schedule. Its slot shows **RAM[&7E07]**. With t = 7 it lands at h 120, character
  15: with the window at character 15 that was the window's first character, which
  went black at one position in eight. So the window starts at **character 16**, and
  is 56 wide (WIN_C + WIN_W ≤ 72, 5.4); every lead-in's last slot is in the margin.
- **In the margin** the slot is a gap position, black by design, but it shows &7E07,
  which is screen memory like the rest of the ring: map data, a different cell's line 7
  as the window moves. Unless &7E07 is zero, a one- or two-pixel bar the height of the
  window follows the lead-in's end, coloured by whatever the scroll last drew there.
  The blip (&FE07 in the right margin when t ≤ 1) shows the same byte.
- **The engine keeps &7E07 zero.** `build` stores 0 there every field, after `colop`,
  the notch and `init`, which write only in the bottom of the frame. In the window the
  only writer is the strip's even-row gadget: an even row's line 7 is `VO`, an odd
  row's is 0. When gadget A's entering cell is &7E00, its line-7 tail (`tA6`) loads
  `ZB`, a zero byte just below `VO`, instead: block B5 decides for each A row from the
  address it has just prepared (the `('B', 5)` slice in `gen_loop2`), `build` for the
  rows it sets up. So the test pattern has one black byte: line 7 of whichever map cell
  is at &7E00. The soak expects it, and its audit counts non-zero stores to &7E07 on
  lines 29–199 (`VERIFICATION.md`).
- **Writes in the horizontal blanking** (MODE 3 at +9 µs, the lead-in mode at +15/+17,
  the palette on line 29, the band's ends) have no slot to take.

**For a game.** The ULA decodes A0–A3 in page &FE, so the mode register has sixteen
addresses, &FE07 to &FEF7, which show &7E07 to &7EF7: line 7 of every other cell from
&7E00 to &7EFF. A game whose map cannot spare a black byte at &7E07 could choose, each
field, a mirror whose byte is zero (often a gap cell, or a black line), and fall back
to zeroing one that is not on show; the remaining case, all sixteen on show and
non-zero, needs the chosen byte zeroed for every line but its own.

---

## 5. Keeping the picture up to date

### 5.1 A new column: the beam-raced strip (gen_loop2.s, strip.s)

A coarse step right exposes a new column at the window's right edge, the **entering
column**, and leaves an old one at its left, the **leaving column**, which must
become a zero gap cell. A column is one byte per scanline: 170 bytes, plus the edge
rows.

Instead of drawing it in the vertical blanking, the scanline loop writes it. On each
window line, in that line's horizontal blanking, the gadget stores one byte of the
entering column and one zero of the leaving column (section 3.2). Where the stores
fall relative to the beam:

- **Ahead of the beam** (`smode` 1: the field in which the step is first shown).
  Iteration y stores line y+1's bytes, just before that line is displayed.
- **Behind the beam** (`smode` 2: only for a 2-column step, in the field before).
  Iteration y stores line y's bytes for the step's first column. Line y has already
  been displayed, so nothing shows until the next field, when the screen start moves.
- **Idle** (`smode` 0). Both stores of every line go to one gap cell, column
  `mx + WIN_W + 7`, with zero. That cell is always zero, so the stores change nothing,
  in the same time.

**The stores are absolute.** An indexed store does a dummy read of its target, a
second 1 MHz slot. The gadget's `sta cell_in` and `sta cell_out` are absolute, so
their operands must change every line and every row:

- **Within a row** the line blocks `inc` the two low bytes.
- **At a row change** the other gadget takes over. Its addresses were prepared during
  the current row: it is the current row's cell + 576 (the next ring row), wrapped
  round the ring. That's computed from the live gadget, so a partial first row is
  harmless.

The preparation is striped across the row's eight line blocks:

| block | slice |
|---|---|
| A1/B0 | the other gadget's entering address, low byte |
| A2/B1 | its high byte, ring-wrapped (the carry found again by `cmp`) |
| A3/B2 | the leaving address, low byte |
| A4/B4 | its high byte |
| A5 | the next colour pair's hash value (`VNX`, from `bq` and `permbx`) |
| A6, B3 | the next pair's even- and odd-line bytes (`VEN`, `VON`) |
| A0, A1 | at a pair boundary, `VON`→`VO`, `VEN`→`VE` |
| B6 | `bq` (the pair's block row) advances |

**The data.** The pattern needs only two bytes per colour pair (a block row, two
character rows): `VE` for even lines and `VO` for odd. An odd map row's line 7 is
always 0 (the grid line). So each block's tail loads `VE`, `VO`, `VEN` (the next row
of a new pair) or #0 — or `ZB`, a zero, for an even row's line 7 when its entering cell
holds the leak byte (4.5). For a game these would become tile-data fetches in the same
slots.

**What the builder does.** `build` no longer touches each row. It sets up:
- the first row's gadget, at line k0 of its cells;
- the next row's gadget;
- the first pair's bytes and the next pair's;
- the entry tail, the first block, and the exit block.

That takes 998 cycles (38 of them the leak byte's, 4.5) where the snippet builder took about 3,560. It runs above the
window it sets up, in the free time after the lock (3.1). It touches no main RAM, and
its paths take the same time with no 1 MHz access on them: `addrow` keeps its
intermediate in a variable, not on the stack, because a 1 MHz access's length depends
on its cycle's phase, which would differ between paths.

**Commit timing.** The rule is **at most 2 columns a commit, commits at least 2 fields
apart**, so a field is ahead, behind or idle, never two at once. Together with the
vertical limit this gives a top speed of one character (4 pixels) a field across and
2 scanlines a field down: 200 pixels and 100 scanlines a second.

### 5.2 The edge rows (colop.s)

The strip covers the window's lines, but not every line:

- **Row top.** Line Y0 has no iteration before it: its blanking is the palette
  line's.
- **Row bot.** Its lines below the window are never displayed by the strip's
  iterations.
- **The look-ahead rows.** The rows just above and below the window must hold the
  right cells too, because the next vertical step brings them into view.

`colop` writes these as whole characters, in the fixed-length work below the window.
Going right it writes five rows (top−1, top, bot, bot+1, bot+2); going left, top−2 to
bot+1. Each row gets the entering cell (pattern) and the leaving cell (zero):

| row | entering cell (pattern) | leaving cell (zero) |
|---|---|---|
| top−2 | – | left: if class(xout) ^ 2 is due above |
| top−1 | if class(xin) is due above | right: if class(xout) is due above; left: always |
| top, bot | always | always |
| bot+1 | if class(xin) is due below | right: always; left: if class(xout) is due below |
| bot+2 | – | right: if class(xout) ^ 2 is due below |

Notes on the table:

- **Columns.** Going right, xin = mx + W and xout = mx; going left, mx − 1 and
  mx + W − 1.
- **Classes.** "Due" is the notch rule (5.3). "class ^ 2" is the class of the same
  cell seen as the neighbouring row's gap cell, 72 columns (18 blocks) on.
- **The behind field.** For the behind field of a 2-column step, rows top and bot get
  only their *hidden* lines (the line mask `MLINE`, applied by `PUTCM`), because their
  shown lines would show.
- **Fixed time.** An unwanted cell or line goes to the dummy page (`SELP`, `PUTCM`),
  so `colop` takes the same time whatever is due.

### 5.3 A new row: the notch (notch.s)

Vertical steps are 2 lines, and the row about to come into view must be ready when it
does. The engine spreads the work over the four 2-line steps that bring a row from
just out of view to fully in view.

The map's columns are split into four **classes**, class = (column >> 2) & 3, in
4-character blocks. With phase k = (wy & 7) / 2:

- a cell of the look-ahead row **below** the window is required to be right iff its
  class ≤ k;
- a cell of the row **above** iff its class ≤ 3 − k.

The row below is complete when k = 3, just as it comes into view. The row above is
complete when k = 0.

**One step, one class.** A 2-line step down makes exactly one (row, class) newly due:
the row below the new last row, class k. A step up makes the row above the new first
row due, class 3 − k. The step draws exactly that: the class's cells across the row's
72-cell span, the window's cells as pattern and the gap's as zeros.

**Plan, then store.** The drawing is split across the bottom of the frame (section 6)
so that its stores, the expensive part, are fixed-length work:
- `vstep`, in the variable part, moves `wy` and has `nprep` fill a **plan**: the
  class's five blocks' addresses (`NBL`, `NBH`), and each of their twenty cells' three
  bytes (`NTE` for lines 0, 2, 4 and 6, `NTO` for 1, 3 and 5, `NT7` for line 7). A
  cell's bytes are its block's pattern ANDed with `NSPAN`, a mask by the span's kind
  and the cell's column: $FF in the window's part of the span, else 0. About 1,400
  cycles. With no step this field, `nnull` aims all five blocks at the dummy page.
- `nstore`, the first thing after display end, writes the plan's twenty cells: five
  blocks of four cells, eight stores a cell, the block's page patched into the stores.
  About 2,120 cycles, the same every field, step or not. It has a page to itself
  (segment NSTORE).

**Every cell of the five blocks is written**, with no test per cell. The cells of the
first and last blocks that fall outside the span (up to 3 before it, up to 8 after it)
get zero. Along the tape, row r's cell c is row r+1's cell c − 72. So those cells are
either:
- the neighbouring window row's gap cells, which are always zero; or
- cells of the row two away from the window, which nothing requires. A row's classes
  are drawn one by one after it becomes the look-ahead row, before they are due.

(At start-up, `first_picture` draws every class of 25 rows twice: first all as rows
above, then all top-down as rows below. A row-above drawing zeroes three window cells
of the row before, which the second pass redraws. A row-below drawing zeroes window
cells of the row after, which it draws next.)

**Free interactions.** A column step needs no bookkeeping: `colop` decides from the
column's class and `wy` alone (5.2). Reversing leaves extra classes drawn, which is
harmless: a class is drawn again whenever it becomes due.

**Cost.** About 1,400 cycles of variable work in a field that steps (`nprep`), and
2,120 of fixed work in every field (`nstore`). The stores cost more than the cycle
count of their instructions: each is a main-RAM write, which waits for a 1 MHz slot.
Before the split, the whole drawing was variable work, 3,300–4,100 cycles. There is
one plan, so **at most 2 lines a field** (`DYMAX`, asserted). A second notch would need
another 2,120 cycles of fixed work, which the bottom of the frame doesn't have.

### 5.4 Why 56 characters at 16, and the one-column rule

The position is set by the lead-in: its longest, 8 µs on the real ULA, must end before
the window, and its last write takes a slot (4.5), so the window starts at character
16. The width is then set by the behind column. Going right, a 2-column step's first
entering column is stored a field early, in row y's cell at mx + W. Along the tape
that is row y+1's cell mx + W − 72, its first gap cell:

- **Width.** The cell would be displayed in row y+1 in the early field if the margin
  showed it, and with no lead-in the margin shows WIN_C cells. So WIN_C + WIN_W ≤ 72,
  and 56 is the widest at character 16.
- **The one-column rule.** At WIN_C + WIN_W = 72 the margin can show all 16 gap
  cells. So `logic` takes a 2-column step right as a single column whenever the field
  before the commit would have no lead-in. After that the lead-in's parity stays odd,
  so the rule costs at most one field, once.

(The research tree's 55-wide build at character 16 needed no such rule; the 57-wide
one at character 15 had it, and lost its first character to the leak at t = 7.)

---

## 6. The bottom of the frame (frame.s)

From the exit at line 200 to the next lock at line 0 there are 113 lines, 14,464
cycles, in two parts.

**Variable length**, which must end before line 255 (worst seen: line 223):
- the field parity; the schedule keys (comma, full stop);
- the keyboard (`kbd.s`, from main RAM);
- the trajectory (`logic.s`);
- the vertical step's plan (`vstep`, `nprep`; section 5.3).

Then the program polls for display end, which the ULA flags at line 255 in MODE 4 (a
graphics mode: in MODE 6, a text mode, it would be line 249). The poll absorbs all the
variation, so this part needs no cycle counting.

**Fixed length**, every path padded to the same time:
- **The vertical step's stores** (`nstore`), the same in every field.
- **The column step.** A commit, shown next field: `colop` for the ahead column, then
  `mx` and `wx` move. The behind field of a 2-column step: `colop` for its first
  column, hidden lines only, then `mx` moves. An idle field: an equivalent delay.
- **Spare time** (`CAL_SPARE`): a delay real fixed work can replace.
- **The next field's display parameters** (`setup_frame`, `ula_apply`).
- **A counted delay** (`frame_tail`) to the lock read: `CAL_N64` passes of 64 cycles,
  two more in the 313-line field, and `CAL_REM`.

The fixed part is about 7,130 cycles from display end to `ula_apply`. Of those, 700
are spare delay (`CAL_SPARE`). The counted delay after it is at its minimum (`CAL_N64` =
1, `CAL_REM` = 10). The paths are balanced to within about ±10 cycles: colop's
main-RAM stores are 1 MHz accesses whose lengths depend on their phase. The lock
absorbs that.

**The commit pipeline.** `logic` chooses a commit (`hnew`) two fields ahead of its
display: hnew → cnext2 → cnext. A commit chosen in field N:
- is drawn in the bottom of field N+2 and shown in field N+3;
- if it is a 2-column step, its behind half is in field N+2's window, with its
  `colop` in the bottom of field N+1.

**The fields.** PAL fields alternate 312 and 313 lines. `boot_sync` (init.s) finds
the field once, from the RTC event's position relative to display end, and the
parity (`fpar`) simply alternates after that.

**Budget.** The variable part has about 7,000 cycles before display end at line 255.
Measured on the six fingerprint trajectories, it uses 600–1,300 cycles in a field
without a vertical step and 2,000–2,900 in one with a step. That leaves about 4,000 for
a game in the worst field. Add the free time above the window (2,557 cycles, 3.1) and
the spare delay below it (700).

---

## 7. Timing discipline and calibration

Every cycle from the lock to the exit is counted, and the fixed work below the window
is balanced. The rules the source follows:

- **Delays are macros** that produce an exact cycle count (`PADN`, `DELAY`, `LDELAY`
  in macros.inc). `LDELAY` runs a loop in its own page and returns by a patched jump,
  so it is exact wherever it is placed.
- **No page crossings where timing matters.**
  - A branch that crosses a page when taken costs a cycle, and so does an indexed load
    whose index carries into the next page.
  - The window's variant set (with VX), the line blocks' slots, the tails, the
    vertical step's stores and the delay loop each sit in a page, or the source
    asserts the constraint they need.
  - Every table indexed in the fixed work is asserted not to straddle a page over its
    index range (`NOCROSS`).
  - Every `jmp (vector)` is asserted clear of the 6502's &xxFF bug (`NOWRAP`).
  - `tools/pagecheck.py BUILD` lists every branch that crosses a page. Today the only
    one is in the variable work, where crossings don't matter. When a change moves the
    fixed work's code, the cheapest fix has been to reorder CODE's files (section 8).
- **Equal paths.** Each branch in the fixed work is balanced: by `nop`s, by storing to
  the dummy page instead of skipping a store (`SELP`, `PUTCM`), or by padding a whole
  path (`CAL_CP`, `CAL_CM`, `CAL_BP`, `CAL_BEH`, `CAL_NOC*` in cal.inc). The builder's
  idle and real paths are balanced by `BLD_IDLE`.
- **The window loop** is balanced by construction: every line block is `BLK_LEN` cycles
  (`gen.py` counts each block's cycles and pads it), and the gadget's pads (`PAD_W*`)
  place its writes. `CAL_ENT` sets the loop's phase at the palette line's handover, and
  `CAL_V20` makes variant 0 as long as the others in this loop's 1 MHz alignment.
- **What remains.**
  - Main-RAM stores land on 1 MHz slots, so they take 2 or 3 cycles depending on
    phase.
  - The ring-row wrap (`co_inc`'s mod 320) depends on the row.
  - Together these leave the fixed work's length varying by about 24 cycles (12 µs)
    from field to field, well inside the lock's ±20 µs.

**Retuning.** When the fixed work changes:

1. Measure it with `test/fingerprint.sh` and `test/fpcompare.py`. Run both builds over
   the same trajectories; the comparison reports, per field, the picture writes (which
   must not change), the fixed work's length and the lock read's position, and their
   differences.
2. Move `CAL_REM` by the change in the fixed work's length, so that the lock read
   stays where it was.
3. If the change affects only some paths, adjust that path's pad.
4. Confirm with `test/soak.sh`: its summary gives the range of lock-read positions in
   line 0 over every field.

The soak reports the lock read (the first of the two) at h 312–616 of line 0, about
20–38 µs in. That position is well inside the window in which the two-read lock holds.

---

## 8. Source map and build options

| File | Segment(s) | What |
|---|---|---|
| `elkscroll.s` | – | the root: includes everything in the order that fixes the layout |
| `raster.s` | DLOOP, ENTRY, LOOP (+ LOOP2, VARIANTS) | the lock, the free time above the window, the palette line; includes the window's generated code |
| `gen_loop2.s` (generated) | LOOP2, TABLES3 | the window: gadgets gA/gB and the sixteen line blocks |
| `init.s` | VCODE, TAILS | start-up, `first_picture`, `boot_sync` |
| `frame.s` | CODE, TAILS | the bottom of the frame, `frame_tail` |
| `logic.s` | VCODE | the trajectory and keys |
| `notch.s` | VCODE, NSTORE | `vstep`, `nprep`, `nnull` (the plan); `nstore` (the stores) |
| `colop.s` | CODE | the edge rows |
| `strip.s` | CODE, TABLES4 | `build`: the strip's first two rows and per-field state |
| `display.s` | CODE | `setup_frame`, `ula_apply`, `rowaddr`, `addrow` |
| `tables.s` | TABLES, TABLES2 | the tables (`gen_tables.s` first) |
| `vars.s` | VARS | the variables |
| `kbd.s` | KBDCODE (main RAM, &0900) | the keyboard scan |
| `loader.s` | LOADER (&2000) | finds a sideways RAM bank, copies, starts |

CODE holds only fixed-length work, in an order (colop, strip, frame, display) where no
branch on a fixed path crosses a page (`tools/pagecheck.py`). VCODE holds the
variable-length work, where crossings don't matter.

Memory: the sideways RAM image fills &8000–&ACC3 of the bank (about 11.2K of 16K). Main RAM holds the
screen ring (&3000–&7FFF), the dummy page (&2400), the keyboard routine (&0900) and
its result (&0A00–&0A02), and the stack.

Build options (`make NAME=VALUE`; defaults in init.s):

| Option | Default | |
|---|---|---|
| `START_WX`, `START_WY` | 1283, 1280 | the map position at start (`START_WY` even) |
| `TRAJ` | 0 | 0: the demo script (`gen.py` `SCRIPT`); 1: a random walk |
| `SEED` | &ACE1 | the random walk's seed |
| `MOTION` | 0 | 1: moving from the start (else SPACE starts it) |
| `SCHED` | 8 | the schedule at start: 8 real ULA, 0 FPGA |
| `SCRMODE` | 1 | the window's screen mode: 1 or 2 (section 10; `gen.py`, not the assembler) |
| `LOCK1` | 0 | 1: lock with one read, in line 0 (3.1): a line more free time, about half the margin (default in `cal.inc`) |

---

## 9. Toward a game engine

The display engine is complete. The test pattern stands in for a game's map. To turn
it into the Electron counterpart of beebgame, a game would replace or add:

- **Map data.** The pattern tables (`PERM`, `PE`, `PO` and their use in `build`,
  `colop`, `nprep` and the line blocks' data slices) become tile lookups: each fills a
  cell's eight bytes, or the next line's entering byte, from the map, in the same fixed
  time.
- **Sprites.** The engine is single-buffered, so a sprite is drawn into the ring and
  erased again.
  - A sprite over the entering or leaving column on a raced line needs care: the strip
    overwrites those cells as the beam passes. Draw sprites after the commit field's
    window, or keep them a column inside the edges.
  - Game logic and sprite work fit in three places: the variable-length part before
    display end (about 7,000 cycles less the vertical step's plan and the trajectory,
    about 4,000 in the worst field: section 6); the free time above the window (2,557
    cycles, fixed length, main RAM at 1 MHz: section 3.1); and the spare delay below it
    (700, fixed length).
- **Speed.** As it stands the engine holds the CPU from line 0 to line 200 for the
  scanline loop. A game would run its logic in the bottom of the frame, or at a lower
  frame rate. An experimental port of Cleo onto an earlier version of this engine ran
  its game logic at 6–8 frames a second this way.
- **Integration points.**
  - The line blocks have spare cycles (each is `BLK_LEN` long and does up to about
    40). The fixed-length time is the delays `CAL_TA`, `CAL_TB`, `CAL_TC` (above the
    window) and `CAL_SPARE` (below it). X must keep the
    blip value through the window.
  - Everything from the blip to the variant's write must stay exactly as listed in
    section 3.2.

---

## 10. The MODE 2 window (`SCRMODE=2`)

The same engine shows a **112 × 170-pixel MODE 2 window**, with the same memory layout,
timing and scrolling. It has sixteen logical colours, eight of them distinct on
screen. MODE 0, 1 and 2 fetch identically: 80 bytes a line, one every half
microsecond. So the ring, the lead-in, the blip, the strip and the notch all work on
bytes, unchanged:
- a character is still 8 bytes, now 2 pixels wide;
- a column step is 2 MODE 2 pixels;
- a pattern block (4 characters by 16 lines) is 8 × 16 pixels.

`gen.py` generates either build (`SCRMODE` in the environment; `make one SCRMODE=2`).
The assembly has no conditional code: the two builds differ only in generated values.

**The palette.** The register pairs are independent: pair (&FE08+2i, &FE09+2i) holds
logical colours base_i | {0, 2, 8, 10}, base = 0, 4, 5, 1 (`ULA-NOTES.md` section 9).
Every mode except MODE 2 shows only colours 0, 2, 8 and 10, which &FE08/&FE09 hold:
MODE 1/5 show those four, and MODE 0/3/4/6 and mode value 7 show 0 and 8. Hence:

- &FE0A–&FE0F are written once, in `boot_sync`, and never change. They're &FF in a
  MODE 1 build. They're written there rather than in `init`, so as not to move `CODE`
  (section 7: no fixed-path branch may cross a page).
- The palette line and the exit (VX) black out the window with &FE08/&FE09 exactly as
  in MODE 1.
- **Only the window's lines are MODE 2.** The lines above it and below it are the same
  as in a MODE 1 build (2.1): MODE 1 or 3 on lines 0 and 1, MODE 4 or 6 elsewhere, all
  of which show only colours 0 and 8, black outside the window.

**What the mode changes.**

| | MODE 1 build | MODE 2 build |
|---|---|---|
| the window's mode `MW`: the gadgets' and the palette line's MODE 1 write | M1 | M2 |
| the lead-in mode in the window (`VC_BY_X`: the gadgets, the palette line's `sty`) | M7 / M1 | M7 / M2 |
| the blip in the window (`VA_BY_X`, X in loop 2) | M5 / M1 | M5 / M2 |
| the block's black left pixel (`LMASK`: `PMASK`, `PEM`, `POM`) | &77 | &55 |
| &FE0A–&FE0F | &FF | the MODE 2 palette |

When MODE 2 was added, a MODE 1 build's timing stayed identical to that before: every
write, the fixed work and the lock read, on six fingerprinted trajectories.

**The test card: the Amstrad CPC's palette.** The CPC's 27 colours have each of red,
green and blue off, half or full. Each is the average of two of the Electron's eight
colours:
- A has every component that is at least half on;
- B has every component that is full.

A block is A and B in a 1 × 2 dither: the pair alternates along each line and swaps on
the next. That's exactly the even-line and odd-line bytes the engine already carries
per colour pair (`VE`, `VO`), so the strip's data path is unchanged. The 26 colours
other than black are used, so the grid stays visible. Each colour of a pair appears
under one of its two logical names: logical L shows colour L, or 15 − L above 7. So
the picture uses every palette register. `model.bin` carries the mode and the palette
for elkh's checker.

