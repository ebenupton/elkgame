# elkgame: design of the scroll engine

This document explains how the demo puts a 228 × 170-pixel MODE 1 window on an Acorn
Electron and scrolls it at 50 Hz. It covers the display tricks first (sections 2–4),
then how the picture is kept up to date as it moves (5), then the frame's timetable
(6) and the timing discipline that holds it together (7). Section 9 says what a game
built on the engine would add.

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
- **Vertical fine scroll** comes from a band of text-mode rows above the window
  (section 2).
- **Timing** comes from a stalled read that locks the program to the raster once a
  field. Interrupts are off and every cycle from there to the window's last line is
  counted (sections 3 and 7).
- **New picture** is written as the window moves, at a fixed and small cost per field.
  A new column is written by the scanline loop itself, one byte a line, just ahead
  of the beam. A new row is drawn a quarter at a time (section 5).

---

## 2. Screen geometry and memory

### 2.1 The window

| | |
|---|---|
| size | 57 characters × 170 scanlines = 228 × 170 pixels |
| position | screen character 15 (of 80) across; lines 30–199 |
| above it | lines 0–29: black, with 0–3 rows of 10-line text mode (MODE 3) at the top |
| below it | lines 200–312: black, MODE 6 (a text mode: no contention, CPU at full speed) |
| palette | black, cyan, magenta, yellow; set on line 29, blacked out at line 200 |

`gen.py` sets the geometry (`WIN_C`, `WIN_W`, `Y0`, `Y1`) and writes it to
`config.inc` for the assembler.

### 2.2 The ring

The ULA displays 80 characters a line, but the engine lays the 20K screen ring out
(&3000–&7FFF, which the ULA wraps) as rows of **72 characters (576 bytes)**. Each
displayed line therefore fetches only 72 to 79 characters before the next row begins,
and a row's 72 cells hold the window's 57 and 15 gap cells, which are kept zero (black).

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
- **Fine.** `f = ((Y0 − wy) & 7) / 2` rows of MODE 3 at the top of the frame push the
  first MODE 1 row down by 2f lines. A MODE 3 row is 10 scanlines tall but advances
  the address by only one row (8 scanlines' worth).

Vertical steps are therefore 2 scanlines, and `wy` is always even. The band's lines
are black: the palette is black until line 29. `setup_frame` (display.s) works out the
screen start, `f`, the band's line counts (`BAND_N`, `N1TAB`) and line 0's mode
(`TOPMODE`).

---

## 3. The frame and the scanline loop (raster.s)

### 3.1 The lock

Interrupts are off for good. Each field starts with `frame_top`, two reads of a
main-RAM byte (`SYNCB`):

- The first is aimed late in line 0.
- The second is aimed mid line 1.

In MODE 1 or MODE 3 a read stalls until that line's fetches end (S), so the second
read always returns at S of line 1. The first read exists so that the lock tolerates
errors: if the work below the window took a little too long, the first read lands
after line 0's fetches and returns at once, and the second still stalls. The
work below the window may be off by about **±20 µs** with every field still
pixel-exact, so the fixed work need not be counted to the cycle. Its measured spread
is about 12 µs (section 7).

### 3.2 The loop

From the lock, the program counts to the first iteration. Each **iteration** is
exactly 128 cycles, one line. Iteration y runs from the right margin of line y to the
lead-in of line y+1, and makes these writes (µs after S of line y):

| µs after S | write | |
|---|---|---|
| −3 | &FE07: the **blip** | MODE 5 when the lead-in is 0 or 1 µs, else MODE 1 (no change). Section 4.2 |
| +5 | first store | window: the entering column's byte (section 5.1) |
| +9 | &FE07: MODE 3 | inside the line sync. Section 4.2 |
| +14 | second store | window: the leaving column's zero |
| +17 | &FE07: the lead-in mode | mode 7 (a 40-column mode), or MODE 1 if there is no lead-in |
| +23+u | &FE07: MODE 1 | the **variant**: u nops then the store (none when u = 0). Section 4 |

The loop has three parts, sharing this skeleton:

- **loop 1**: the lines above the window. Both stores go to the dummy page (`DSNIP`).
- **the palette line** (iteration Y0−1): its two stores are the palette's, &FE08 and
  &FE09.
- **loop 2**: the window, iterations Y0..Y1−2. Its stores come from the current
  character row's **snippet** (section 5.1). X holds the line within the row, and Y
  the +17 mode value.

Loop 2, cycle by cycle (c = cycles after S of line y; sideways RAM fetches run at
2 MHz; an I/O or main-RAM access takes a 1 MHz slot, 2 or 3 cycles depending on phase):

    c      code                            lands (us after S)
    -14    wl2:  lda #vA                   (patched: the blip's mode value)
    -12          sta &FE07                 -3
    -6           jmp (sptr)
    -1     SNp:  lda SNpD,x                (the row's 8 bytes, in the snippet's own tail)
    3            sta a1,x                  +5    (main RAM, in the blanking: never contended)
    10           lda #M3
    12           sta &FE07                 +9    (inside the sync, h 768-832)
    18           lda #0
    20           sta a2,x                  +14
    28           sty &FE07                 +17
    34           lda #M1
    36           jmp (VVEC2)
    41     VS2u: u nops; sta &FE07         +23+u
                 ... padded to the same length; jmp back2
    63     back2: inx; cpx #8; bne same
    69           (row done) ldx #0; sptr += 32       | same: 18 cycles of pad
    91     rtc:  lda &FE00                 (kept for its 1 MHz timing)
    96           (4 cycles of pad)
    100          dec lcnt                  the iterations left
    106          bne wl2
    109    (5 cycles of pad) -> 114 = -14 of the next line

The loop's two parts each sit in one page (asserted), and the variants all take the
same time (`gen.py` `gen_variants`).

### 3.3 The exit

Iteration Y1−1 (line 199) runs its snippet once more: line 199's bytes, behind the
beam (section 5.1). Its variant is **VX**, the exit block:

- black palette (&FE08 = &FE09 = &FF);
- MODE 6 for the rest of the field;
- then `jmp work`, the bottom of the frame (section 6).

MODE 6 is a text mode, so display end is flagged at line 249 and main RAM is not
contended. The program reaches VX through the same `jmp (VVEC2)` as every other
iteration: the last iteration stores Y, the +17 mode value, into the vector's low
byte. VX has two entries in the variants' page, at offsets M1 and M5.

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

The window starts at character 15 because the longest lead-in (8 µs on the real ULA,
section 4.3) must be over before the window's first pixel.

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

`setup_frame` indexes the dispatch tables (`VS1_BY_X`, `VSP_BY_X`, `VS2_BY_X`,
`VA_BY_X`, `VC_BY_X`) by `(wx & 7) | sched`.

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

---

## 5. Keeping the picture up to date

### 5.1 A new column: the beam-raced strip (strip.s, gen_snips.s)

A coarse step right exposes a new column at the window's right edge, the **entering
column**, and leaves an old one at its left, the **leaving column**, which must
become a zero gap cell. A column is one byte per scanline: 170 bytes, plus the edge
rows.

Instead of drawing it in the vertical blanking, the scanline loop writes it. On each
window line, in that line's horizontal blanking, it stores one byte of the entering
column and one zero of the leaving column. Those are the stores at +5 and +14 in
section 3.2. Where the stores fall relative to the beam:

- **Ahead of the beam** (`smode` 1: the field in which the step is first shown).
  Iteration y stores line y+1's bytes, just before that line is displayed.
- **Behind the beam** (`smode` 2: only for a 2-column step, in the field before).
  Iteration y stores line y's bytes for the step's first column. Line y has already
  been displayed, so nothing shows until the next field, when the screen start moves.
- **Idle** (`smode` 0). Every store goes to the dummy page (`DUMMY`, in main RAM like
  the screen, so a store takes the same time either way).

**One snippet per character row.** The stores come from a snippet per character row.
Each is 32 bytes, 25 of them, generated by `gen.py`:

    SNp:    lda SNpD,x          ; the entering column's byte for line X of this row
    SNpA1:  sta a:cell,x        ; operand patched: the row's cell in the entering column
            lda #M3
            sta &FE07           ; MODE 3, in the sync
            lda #0
    SNpA2:  sta a:cell,x        ; operand patched: the row's cell in the leaving column
            sty &FE07           ; the +17 mode value
            lda #M1
            jmp (VVEC2)         ; the variant

X is the line within the row, so the eight lines of a row share a snippet. Per field,
`build` patches four operand bytes and fills the snippet's last eight bytes (`SNpD`) for
each of the 24 rows, about 3,560 cycles, instead of five bytes a line. It is a loop over
row pairs (the two rows of a block row share the pattern's colour), run once for each
page of snippets. The indexed store costs one
more 1 MHz slot than an absolute one, and the blanking has room for it.

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
row due, class 3 − k. `vstep` draws exactly that (`group`): the class's cells across the
row's 72-cell span, the window's cells as pattern and the gap's as zeros. That is
about 18 cells, the same work every step.

**Free interactions.** A column step needs no bookkeeping: `colop` decides from the
column's class and `wy` alone (5.2). Reversing leaves extra classes drawn, which is
harmless: a class is drawn again whenever it becomes due.

**Cost.** One class of a row is up to 20 characters, about 3,900 cycles with every
main-RAM access a 1 MHz slot. Two do not fit beside everything else before display
end, hence **at most 2 lines a field** (`DYMAX`).

### 5.4 Why 57 characters, and the one-column rule

The window's width and position are set by the behind column. Going right, a 2-column
step's first entering column is stored a field early, in row y's cell at mx + W. Along
the tape that is row y+1's cell mx − 15, its first gap cell:

- **Width.** With a 58-character window the gap is only 14 cells, which the left
  margin shows when t = 0, and the cell would be displayed in row y+1 in the early
  field. 57 is the widest that avoids this.
- **The rule at character 15.** At character 15 the margin can show all 15 gap
  cells. So `logic` takes a 2-column step right as a single column whenever the field
  before the commit would have no lead-in. After that the lead-in's parity stays odd,
  so the rule costs at most one field, once.

The 55-wide sibling at character 16 needs no such rule.

---

## 6. The bottom of the frame (frame.s)

From the exit at line 200 to the next lock at line 0 there are 113 lines, 14,464
cycles, in two parts.

**Variable length**, which must end before line 249 (worst seen: line 244):
- the field parity; the schedule keys (comma, full stop);
- the keyboard (`kbd.s`, from main RAM);
- the trajectory (`logic.s`);
- the vertical step (`vstep`).

Then the program polls for display end, which the ULA flags at line 249 after a text
mode. The poll absorbs all the variation, so this part needs no cycle counting.

**Fixed length**, every path padded to the same time:
- **The column step.** A commit, shown next field: `colop` for the ahead column, then
  `mx` and `wx` move. The behind field of a 2-column step: `colop` for its first
  column, hidden lines only, then `mx` moves. An idle field: an equivalent delay.
- **The strip** for the next field (`build`).
- **The next field's display parameters** (`setup_frame`, `ula_apply`).
- **A counted delay** (`frame_tail`) to the lock read: `CAL_N64` passes of 64 cycles,
  two more in the 313-line field, and `CAL_REM`.

The fixed part is about 7,880 cycles from display end to `ula_apply`. That leaves the
counted delay at its minimum (`CAL_N64` = 1, `CAL_REM` = 10): more fixed work would have
to come out of something else, or move the lock read later within its tolerance
(section 3.1), which allows about 30 µs more.

**The commit pipeline.** `logic` chooses a commit (`hnew`) two fields ahead of its
display: hnew → cnext2 → cnext. A commit chosen in field N:
- is drawn in the bottom of field N+2 and shown in field N+3;
- if it is a 2-column step, its behind half is in field N+2's window, with its
  `colop` in the bottom of field N+1.

**The fields.** PAL fields alternate 312 and 313 lines. `boot_sync` (init.s) finds
the field once, from the RTC event's position relative to display end, and the
parity (`fpar`) simply alternates after that.

**Budget.** The variable part has about 6,200 cycles before display end. A vertical
step takes up to about 3,900 of them; the trajectory and keyboard most of the rest.

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
  - The scanline loop's two parts, the variants, the snippets, the tails and the delay
    loop each sit in a page, which the source asserts.
  - Every table indexed in the fixed work is asserted not to straddle a page over its
    index range (`NOCROSS`).
  - Every `jmp (vector)` is asserted clear of the 6502's &xxFF bug (`NOWRAP`).
  - `tools/pagecheck.py BUILD` lists every branch that crosses a page. Today they are
    all in the variable work, where crossings don't matter.
- **Equal paths.** Each branch in the fixed work is balanced: by `nop`s, by storing to
  the dummy page instead of skipping a store (`SELP`, `PUTCM`), or by padding a whole
  path (`CAL_CP`, `CAL_CM`, `CAL_BP`, `CAL_BEH`, `CAL_NOC*`, `CAL_BI*` in cal.inc).
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
| `raster.s` | DLOOP, ENTRY, LOOP, LOOP2 (+ VARIANTS, SNIPS) | the lock and the scanline loop |
| `init.s` | CODE, TAILS | start-up, the first picture, `boot_sync` |
| `frame.s` | CODE, TAILS | the bottom of the frame, `frame_tail` |
| `logic.s` | CODE | the trajectory and keys |
| `notch.s` | CODE | `vstep`, `group`, the cell writers `putc` and `pcl` |
| `colop.s` | CODE | the edge rows |
| `strip.s` | CODE | `build`, the strip |
| `display.s` | CODE | `setup_frame`, `ula_apply`, `rowaddr`, `addrow` |
| `tables.s` | TABLES, TABLES2 | the tables (`gen_tables.s` first) |
| `vars.s` | VARS | the variables |
| `kbd.s` | KBDCODE (main RAM, &0900) | the keyboard scan |
| `loader.s` | LOADER (&2000) | finds a sideways RAM bank, copies, starts |

Memory: the sideways RAM image fills &8000–&A97E of the bank (about 10.6K of 16K). Main RAM holds the
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

---

## 9. Toward a game engine

The display engine is complete. The test pattern stands in for a game's map. To turn
it into the Electron counterpart of beebgame, a game would replace or add:

- **Map data.** The pattern tables (`PERM`, `PE`, `PO` and their use in `build`,
  `colop` and `group`) become tile lookups. Each fills a cell's eight bytes, or a
  snippet's data bytes, from the map, in the same fixed time.
- **Sprites.** The engine is single-buffered, so a sprite is drawn into the ring and
  erased again.
  - A sprite over the entering or leaving column on a raced line needs care: the strip
    overwrites those cells as the beam passes. Draw sprites after the commit field's
    window, or keep them a column inside the edges.
  - The variable-length part before display end is where game logic and sprite work
    fit: about 6,200 cycles less the vertical step.
- **Speed.** As it stands the engine holds the CPU from line 0 to line 200 for the
  scanline loop. A game would run its logic in the bottom of the frame, or at a lower
  frame rate. An experimental port of Cleo onto an earlier version of this engine ran
  its game logic at 6–8 frames a second this way.
- **Integration points.**
  - `back2`'s tail (cycles 63–109 of an iteration) is free for other work, provided X
    and Y come back intact and `sptr` advances when X wraps.
  - Everything from the blip to the variant's write must stay exactly as listed in
    section 3.2.
