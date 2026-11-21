#!/usr/bin/env python3
"""Generated source for the scroll demo, and the model its checks compare against.

    python3 tools/gen.py OUTDIR

writes, into OUTDIR:

    config.inc      geometry, mode values and palette bytes (assembler constants)
    gen_tables.s    the pattern, ring-arithmetic and lead-in dispatch tables (segment
                    TABLES), and small tables and the demo script (segment TABLES3)
    gen_variants.s  the lead-in variants and the window's exit block (segment VARIANTS)
    gen_loop2.s     the window: two gadgets and sixteen line blocks (segment LOOP2),
                    and the line blocks' address tables for strip.s (segment TABLES3)
    model.bin       the pattern and geometry for the emulator's checker (emu/elkh soak)

SCRMODE=2 in the environment (the Makefile sets it) generates the MODE 2 window
(docs/DESIGN.md, "The MODE 2 window").

Everything here is a pure function of the constants below: the build is deterministic.
check_schedules() runs as the variants are generated and fails the build if a lead-in
schedule fails at any phase in S_RANGE.  docs/DESIGN.md explains the engine; the
section titles quoted below are its.

The playfield
-------------
A map of 2560 characters x 2560 scanlines (it repeats in both directions), shown
through a window of WIN_W characters x H scanlines.  The map is a grid of blocks of 4
characters x 2 character rows (16 x 16 pixels in MODE 1, 8 x 16 in MODE 2), each
filled with one colour chosen by a hash of the block's coordinates: in MODE 1 one of
the 35 dithered colours of swatch35, in MODE 2 one of 26 colours of the Amstrad CPC's
palette, each a dither of two Electron colours.  Every block's left pixel column
and bottom scanline are black, so a line or character out of place breaks the grid at
once.  (The bottom, not the top: then line 0 of every character row -- the line whose
lead-in is the most delicate -- carries pattern, never a black grid line.)

Coordinates: wx is the map character column at the window's left edge (0..2559), wy
the map scanline at its top (0..2559).
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import swatch35  # noqa: E402

# ---- geometry ("Screen geometry and memory") ---------------------------------------
Y0 = 30            # first window scanline (the text-mode band above it is at most 30 lines)
Y1 = 200           # first scanline below the window (MODE 4 from here to the field's end)
H = Y1 - Y0        # window height in scanlines: 170
WIN_C = 16         # screen character (MODE 1, 0..79) of the window's left edge.  The
                   # longest lead-in (8 us, t = 7 on the real ULA's schedule) must end
                   # before the window, and its last write, the window's mode to &FE07,
                   # takes the video slot it lands in: on a real ULA that slot shows
                   # RAM[&7E07], not its own byte ("The leak byte").  At t = 7 the write
                   # lands at h 120, character 15, so the window starts at 16 and every
                   # lead-in's last slot is in the left margin (where &7E07, kept zero,
                   # shows black)
WIN_W = 56         # window width in characters: the widest at character 16.  A 2-column
                   # step's first entering column is stored a field early, in the next
                   # ring row's first gap cell; with no lead-in the margin shows WIN_C
                   # cells, so WIN_C + WIN_W <= 72 keeps that cell off screen ("Why 56
                   # characters at 16, and the one-column rule")
assert WIN_C >= 16 and WIN_C + WIN_W <= 72 and WIN_W <= 61   # (WIN_C >= 16: the t = 7 slot, above)
MAPW = 2560        # map period, in characters across and in scanlines down
RING = 0x5000      # the 20K screen ring the ULA wraps (&3000-&7FFF)
ROWB = 576         # bytes in a ring row: 72 characters

# ---- the ULA's mode register values (&FE07; comms off, LED and motor off) ----------
M1, M2, M3, M4, M5, M6 = 0x08, 0x10, 0x18, 0x20, 0x28, 0x30
M7 = 0x38          # mode value 7 (undocumented): fetches like MODE 4 (40 columns).  A
                   # Synertek ULA wraps it at &8000 to &3000; a Ferranti treats it as
                   # MODE 4 and wraps to &5800, as MODE 4 and 5 do (so on a Ferranti the
                   # row starting at &7FC0 is wrong at t = 7: docs/DESIGN.md)

# ---- the window's screen mode: 1 (four colours, the default) or 2 (sixteen) ---------
# MODE 0-2 fetch alike, a byte every half microsecond, so the ring, the lead-in and the
# strip work on bytes unchanged; only the window's lines are MODE 2 ("The MODE 2
# window").  A character is 8 bytes either way: 4 MODE 1 pixels or 2 MODE 2 pixels.
SCRMODE = int(os.environ.get('SCRMODE', '1') or '1')
assert SCRMODE in (1, 2)
MW = M1 if SCRMODE == 1 else M2          # the window's mode value
PPC = 4 if SCRMODE == 1 else 2           # pixels a character
LMASK = 0x77 if SCRMODE == 1 else 0x55   # a byte with its leftmost pixel black

# ---- palette ------------------------------------------------------------------------
K, C, M, Y = 0, 1, 2, 3
PAL_RGB = {0: (0, 0, 0), 1: (0, 1, 1), 2: (1, 0, 1), 3: (1, 1, 0)}   # logical -> RGB


def palette_bytes():
    """(&FE08, &FE09) for PAL_RGB in MODE 1 (a set bit turns the component off)."""
    on8 = on9 = 0
    r, g, b = PAL_RGB[0]
    on9 |= r << 0 | g << 4
    on8 |= b << 4
    r, g, b = PAL_RGB[1]
    on9 |= r << 1 | g << 5
    on8 |= b << 5
    r, g, b = PAL_RGB[2]
    on9 |= r << 2
    on8 |= g << 2 | b << 6
    r, g, b = PAL_RGB[3]
    on9 |= r << 3
    on8 |= g << 3 | b << 7
    return (~on8) & 0xFF, (~on9) & 0xFF


# ---- the pattern --------------------------------------------------------------------
# MODE 2: logical colour L -> 3-bit colour (bit 0 red, 1 green, 2 blue): L for L < 8,
# 15 - L above, so each of the eight colours has two logical names (0 and 15 are black)
# and the test card exercises every palette register.
PAL2 = [L if L < 8 else 15 - L for L in range(16)]


def palette_bytes2():
    """&FE08..&FE0F for PAL2 (a set bit turns the component off).  Register pair
    (&FE08+2i, &FE09+2i) holds logical colours base_i | {0, 2, 8, 10}, base = 0, 4, 5,
    1 (docs/ULA-NOTES.md, "Palette")."""
    regs = [0] * 8
    for i, base in enumerate((0, 4, 5, 1)):
        for j, off in enumerate((0, 2, 8, 10)):
            rgb = PAL2[base | off]
            r, g, b = rgb & 1, (rgb >> 1) & 1, (rgb >> 2) & 1
            lo, hi = 2 * i, 2 * i + 1         # (&FE08+2i, &FE09+2i)
            regs[hi] |= r << j
            if j < 2:
                regs[hi] |= g << (4 + j)
                regs[lo] |= b << (4 + j)
            else:
                regs[lo] |= g << j | b << (4 + j)
    return [(~v) & 0xFF for v in regs]


def mode2_byte(l, r):
    """Two logical colours (left, right) -> a MODE 2 screen byte."""
    v = 0
    for k in range(4):
        v |= ((l >> (3 - k)) & 1) << (7 - 2 * k) | ((r >> (3 - k)) & 1) << (6 - 2 * k)
    return v


# The MODE 2 test card: the Amstrad CPC's palette.  The CPC's 27 colours have each of
# red, green and blue off, half or full; each is the average of two of the Electron's
# eight -- A with every component that is at least half on, B with every component that
# is full -- so a block is A and B in a 1 x 2 dither, the pair alternating along each
# line and swapping on the next.  The 26 colours other than black, each colour of a
# pair under one of its two logical names (chosen per hash value).
CPC = [(r, g, b) for r in range(3) for g in range(3) for b in range(3) if (r, g, b) != (0, 0, 0)]
assert len(CPC) == 26


def cpc_pair(lv):
    """(A, B): the two Electron colours whose average is CPC levels lv."""
    a = sum(int(l >= 1) << i for i, l in enumerate(lv))
    b = sum(int(l == 2) << i for i, l in enumerate(lv))
    return a, b


def dithers2():
    """(even-line, odd-line) MODE 2 bytes for the 256 hash values."""
    name = {c: [L for L in range(16) if PAL2[L] == c] for c in range(8)}
    rng = random.Random(2026)
    out = []
    for v in range(256):
        a, b = cpc_pair(CPC[v % len(CPC)])
        la, lb = rng.choice(name[a]), rng.choice(name[b])
        out.append((mode2_byte(la, lb), mode2_byte(lb, la)))
    return out


def mode1_byte(px):
    """Four logical colours (left to right) -> a MODE 1 screen byte."""
    v = 0
    for p, c in enumerate(px):
        v |= ((c >> 1) & 1) << (7 - p) | (c & 1) << (3 - p)
    return v


def dithers():
    """(even-line, odd-line) MODE 1 bytes for each of the 35 colours."""
    ink = {K: 0, C: 1, M: 2, Y: 3}
    out = []
    for t in swatch35.ALL:
        cell = swatch35.cell(*t)
        ev = mode1_byte([ink[cell[(x & 1, 0)]] for x in range(4)])
        od = mode1_byte([ink[cell[(x & 1, 1)]] for x in range(4)])
        out.append((ev, od))
    return out


_rng = random.Random(1983)
PERM = list(range(256))
_rng.shuffle(PERM)
# The hash repeats every 128 blocks across, so that the 8-bit block index the engine
# steps (wrapping at 256) agrees with the map's 640 blocks (5 periods) at its seam
PERM = [PERM[i & 127] for i in range(256)]
PERM2 = list(range(256))
_rng.shuffle(PERM2)
DITH = dithers() if SCRMODE == 1 else dithers2()
IDX = [PERM2[v] % 35 for v in range(256)] if SCRMODE == 1 else PERM2   # hash value -> colour


def block_colour(bx, by):
    """Colour number of block (bx, by): a hash value through IDX.  The engine steps
    the block row through MOD160 (gen_tables.s), so by stays in 0..159 and the & 255
    only matches its 8-bit sum."""
    return IDX[(PERM[bx & 255] + (by & 255)) & 255]


def pixel(mx, my):
    """Logical colour of map pixel (mx in the window mode's pixels, my in scanlines).
    A block is four characters across: 16 MODE 1 pixels or 8 MODE 2 pixels."""
    bw = 4 * PPC
    if (mx % bw) == 0 or (my & 15) == 15:
        return 0
    ev, od = DITH[block_colour(mx // bw, my >> 4)]
    b = od if (my & 1) else ev
    if SCRMODE == 2:
        s = 1 - (mx & 1)
        return sum(((b >> (2 * k + s)) & 1) << k for k in range(4))
    p = mx & 3
    return ((b >> (7 - p)) & 1) << 1 | ((b >> (3 - p)) & 1)


def expected_window(wx, wy):
    """The window's pixels for position (wx, wy): H rows of WIN_W * PPC logical colours."""
    return [[pixel((wx * PPC + x) % (MAPW * PPC), (wy + y) % MAPW) for x in range(WIN_W * PPC)]
            for y in range(H)]


# ---- the demo script (TRAJ = 0) -----------------------------------------------------
# Segments of (fields, columns a commit, fields between commits, lines a vertical step,
# fields between vertical steps), at the engine's limits throughout: 2 columns every 2
# fields, 2 lines every field, on each axis, the four diagonals and two squares.
SCRIPT = [
    (200, 2, 2, 0, 1), (200, -2, 2, 0, 1),            # columns flat out
    (150, 0, 2, 2, 1), (150, 0, 2, -2, 1),            # lines flat out
    (200, 2, 2, 2, 1), (200, -2, 2, -2, 1),           # the four diagonals
    (200, 2, 2, -2, 1), (200, -2, 2, 2, 1),
    (100, 2, 2, 2, 1), (100, 2, 2, -2, 1), (100, -2, 2, -2, 1), (100, -2, 2, 2, 1),   # a square, twice
    (100, 2, 2, 2, 1), (100, 2, 2, -2, 1), (100, -2, 2, -2, 1), (100, -2, 2, 2, 1),
]
assert len(SCRIPT) <= 51                            # 5 bytes a segment, one page

# ---- lead-in schedules and the FPGA phase model ("Horizontal fine scroll: the
# lead-in") ----------------------------------------------------------------------------
# Every window line has the same shape.  For t = (WIN_C - wx) & 7:
#   t = 1..7: a 40-column mode from the blanking (mode value 7 in the program; the
#             model below steps it as MODE 5), the window's mode at t us: the line's
#             address counter falls t characters behind and the line fetches 80 - t;
#   t = 0:    the window's mode throughout, and MODE 5 for the last 2-3 us of the line,
#             in the right margin (the "blip"): the line fetches 77-78, not 80, so that
#             the start-of-row register (A14..A6) still advances by 576, not 640;
#   always:   MODE 3 for part of the line sync, so that line 7 of a character row is
#             not a "last line" and line 0 of the next row restarts from the latch.
# SCHED_START[t] lists (us after S, mode) for the FPGA ULA.  The real ULA's schedule
# (measured on a Ferranti) is t + 1 us, 0 when t = 0 ("Two ULAs: the schedules",
# lead_in_index); the phase model below is the FPGA's, matched to an nvc simulation
# of hoglet's ElectronFpga, and does not model the leak byte.
SCHED_START = {t: ([(t, 'M1')] if t else []) for t in range(0, 8)}

# Phase model ("The phase between CPU and video"): with a stalled read ending at h = S
# (1/16 us ticks), a write '+u' us after S is first used by the video logic at
# h = 16u + (S - 656); MODE 5 steps the address at h = 15 (mod 16), MODE 1 at h = 7
# (mod 8).  CLK corresponds to S = 648, the FPGA's own power-up phase to 656.
S_RANGE = range(648, 660)      # the phases every schedule must work at
U_BLIP, U_M3, U_C = -3, 9, 15   # the line's other writes, us after S: the blip, MODE 3,
                                # the lead-in mode (the gadgets' +15)
HS0, HS1 = 768, 832            # the line sync (FPGA hsync_start, hsync_end)


def _sim(s0, ws, S, upto=640, forbid=None, mode='M5', blip=None):
    """Step a line's fetches from character s0, starting in mode, under writes ws
    ((us after S, mode)) and, if blip is given, a switch to MODE 5 at h = blip.
    Returns (MODE 5 steps, character reached at h = upto), or None if a MODE 5 step
    leaves a character in forbid (relative to the row)."""
    c, m5, k = s0, 0, 0
    marks = sorted((16 * u + S - 656, v) for u, v in ws)
    if blip is not None:
        marks.append((blip, 'M5'))
    for h in range(0, upto):
        while k < len(marks) and marks[k][0] <= h:
            mode = marks[k][1]
            k += 1
        step = (h % 16 == 15) if mode == 'M5' else (h % 8 == 7)
        if step:
            if mode == 'M5':
                if forbid is not None and c in forbid:
                    return None
                m5 += 1
            c += 1
    return m5, c


def sched_ok(t, S):
    """Does lead-in t work at phase S?  The row register must advance by exactly 576
    bytes, with no 40-column step from character 7 to 8 (the step that would cross
    &8000 on the row starting at &7FC0); the line must fetch 80 - t characters and
    reach the window's last character in the window's mode; the blip must come after
    the window's last pixel; MODE 3 must fall inside the line sync and graphics be back
    before it ends; and the window's-mode write must land before the window's first
    character."""
    ws = SCHED_START[t]
    blip = S + 16 * U_BLIP if t == 0 else None
    init = 'M1' if t == 0 else 'M5'
    r = _sim(0, ws, S, forbid={7}, mode=init, blip=blip)
    if r is None or r[1] // 8 != 9:
        return False                 # the row register must advance by exactly 576
    if t and r[1] != 80 - t:
        return False
    if _sim(0, ws, S, 8 * (WIN_C + WIN_W), mode=init, blip=blip)[1] != WIN_C + WIN_W - t:
        return False                 # the window's characters, to its last
    if blip is not None and blip < 8 * (WIN_C + WIN_W) + 4:
        return False                 # the blip after the window's last pixel
    m3 = S + 16 * U_M3               # MODE 3 inside the sync, graphics again by its end
    if not (HS0 + 8 <= m3 <= HS1 - 8) or S + 16 * U_C < HS1 + 4:
        return False
    return (16 * ws[-1][0] + S - 656 < 8 * WIN_C + 4) if ws else True


def check_schedules(report=False):
    """Assert every schedule works at every phase in S_RANGE; return the phases at
    which all of them do (python3 -c 'import gen; gen.check_schedules(True)')."""
    allok = set(range(640, 672))
    for t in SCHED_START:
        ok = {S for S in range(640, 672) if sched_ok(t, S)}
        allok &= ok
        for S in S_RANGE:
            assert S in ok, (t, S)
        if report:
            print(t, ''.join('.' if S in ok else 'X' for S in range(640, 672)))
    if report:
        print('S 640..671; all schedules work at S =', sorted(allok))
    return allok


# ---- generated code ("The frame and the scanline loop", "Keeping the picture up to
# date") ---------------------------------------------------------------------------------
NROWS = 25          # character rows the strip's tables cover: the window touches 22 or
                    # 23, counted from the even row at or above its first

HEADER = '; generated by tools/gen.py -- do not edit'


def gen_variants():
    """gen_variants.s: the lead-in variants VS{part}{u}, u = 0..8, and VX.  Each
    variant is entered with A = MW (the window's mode); VSu is u nops and the store to
    &FE07 (which lands at S + 23 + u us), padded so that all take the same time, then a
    jump back into the loop.  VS0 writes nothing (no lead-in), and is padded by CAL_V20
    in the window, whose stores' 1 MHz alignment differs from the palette line's.
    Parts: P, the palette line (back to backP); 2, the window (through VRET, which
    each line block sets to the next).  The window's set shares a page with VX, its
    exit block (black palette, MODE 4, then the bottom of the frame), so that VJ (the
    gadgets' jump) changes by its low byte only."""
    check_schedules()

    def variant(part, u, back):
        out = [f'VS{part}{u}:']
        if u:
            out += ['\tnop'] * u + ['\tsta\tULA_MODE', f'\tDELAY\t{2 * (8 - u)}']
        else:          # (the window's: its stores' 1 MHz alignment differs; cal.inc)
            out.append('\tDELAY\tCAL_V20' if part == '2' else '\tDELAY\t21')
        return out + [f'\tjmp\t{back}']

    L = [HEADER, '\t.segment "VARIANTS"',
         'VX:', '\tlda\t#$FF', '\tsta\tULA_PAL8', '\tsta\tULA_PAL9', '\tlda\t#M4', '\tsta\tULA_MODE', '\tjmp\twork']
    for u in range(9):
        L += variant('2', u, '(VRET)')
    L.append('\t.assert\t>VX = >*, error, "the window\'s variants and VX must share a page"')
    for u in range(9):
        L += variant('P', u, 'backP')
    return '\n'.join(L) + '\n'


# ---- loop 2: the window's two gadgets and sixteen line blocks ("The loop") ----------
def gen_loop2():
    """gen_loop2.s.  gA, gB: the line's horizontal-blanking code, A for even map rows,
    B for odd: the two stores (the entering cell's byte, the leaving cell's zero),
    MODE 3 in the sync, the lead-in mode, then the variant through VJ.
    b{P}{k}: the visible part after line k of a P row, BLK_LEN cycles -- a slice of the
    next row's preparation, the two store addresses stepped (k < 7), VRET <- the next
    block (and, on line 7, the row count and the exit's arming), then the tail t{P}{k}:
    the next line's entering byte into A, the blip (stx: X holds its mode value), the
    jump to the gadget.  Then the tables strip.s uses to address the blocks.
    Cycle counts below are for code and data in sideways RAM (2 MHz)."""
    C = {'inc': 6, 'lda#': 2, 'lda': 4, 'sta': 4, 'clc': 2, 'adc#': 2, 'cmp#': 2, 'tay': 2,
         'ldaY': 4, 'ldy': 4, 'and': 4}
    other = {'A': 'B', 'B': 'A'}

    def lo_slice(P, k, ofs):            # Q's address at ofs <- P's - k + 576, low byte
        Q = other[P]
        return ([f'\tlda\tg{P}+{ofs}', '\tclc', f'\tadc\t#<($240-{k})', f'\tsta\tg{Q}+{ofs}'],
                C['lda'] + C['clc'] + C['adc#'] + C['sta'])

    def hi_slice(P, k, ofs):            # and its high byte: the carry from the low byte,
        Q = other[P]                    # found again by cmp; wrapped back into the ring
        return ([f'\tlda\tg{P}+{ofs}', f'\tcmp\t#$C0+{k}', f'\tlda\tg{P}+{ofs + 1}', '\tadc\t#2',
                 '\ttay', '\tlda\tWRAPHI,y', f'\tsta\tg{Q}+{ofs + 1}'],
                C['lda'] + C['cmp#'] + C['lda'] + C['adc#'] + C['tay'] + C['ldaY'] + C['sta'])

    def copy(src, dst):
        return [f'\tlda\t{src}', f'\tsta\t{dst}'], C['lda'] + C['sta']

    def join(*parts):
        code, cyc = [], 0
        for c, n in parts:
            code += c
            cyc += n
        return code, cyc

    # The slices: the A row's blocks prepare the next B row and the B row's the next A
    # row -- the other gadget's two store addresses (each 576 bytes on, less the k
    # steps already taken, wrapped into the ring), the next colour pair's hash, bytes and
    # block row, and the leak byte's tail.  The address slices read the live gadget
    # before this line's step.  Blocks sit in 64-byte slots, four to a page (A0-A3,
    # A4-A7, B0-B3, B4-B7): only the blocks at k = 3 and 7 hand over to another page
    # and set VRET's high byte, so the heavy slices go elsewhere.
    SLICE = {
        ('A', 0): copy('VON', 'VO'),                    # this pair's odd-line byte
        ('A', 1): join(copy('VEN', 'VE'), lo_slice('A', 1, 1)),
        ('A', 2): hi_slice('A', 2, 1),
        ('A', 3): lo_slice('A', 3, 6),
        ('A', 4): hi_slice('A', 4, 6),
        ('A', 5): (['\tldy\tbq', '\tlda\tMOD160+1,y', '\tclc', '\tadc\tpermbx', '\tsta\tVNX'],
                   C['ldy'] + C['ldaY'] + C['clc'] + 4 + C['sta']),     # the next pair's hash
        ('A', 6): (['\tldy\tVNX', '\tlda\tPE,y', '\tand\tpmask', '\tsta\tVEN'],
                   C['ldy'] + C['ldaY'] + C['and'] + C['sta']),
        ('B', 0): lo_slice('B', 0, 1),
        ('B', 1): hi_slice('B', 1, 1),
        ('B', 2): lo_slice('B', 2, 6),
        ('B', 3): (['\tldy\tVNX', '\tlda\tPO,y', '\tand\tpmask', '\tsta\tVON'],
                   C['ldy'] + C['ldaY'] + C['and'] + C['sta']),
        ('B', 4): hi_slice('B', 4, 6),
        # The leak byte ("The leak byte").  Every window line's mode writes show
        # RAM[&7E07] (LEAK), so it must stay 0.  In the window the only store that can
        # put a non-zero byte there is gadget A's entering store on line 7, which takes
        # VO (an odd row's line 7 is #0).  gA+1/gA+2 now hold the next A row's entering
        # cell (the B0/B1 slices set them); if that cell is LEAKCELL (&7E00: low byte
        # 0, high byte >LEAKCELL), the eor/ora gives 0, cmp #1 clears the carry and
        # tA6 (the A6 block's tail, which loads line 7's byte) is pointed at ZB
        # (= VO - 1, always 0); otherwise the carry is set and it loads VO.  build
        # does the same for the rows it sets up, and zeroes LEAK each field.
        ('B', 5): (['\tlda\tgA+2', '\teor\t#>LEAKCELL', '\tora\tgA+1', '\tcmp\t#1',
                    '\tlda\t#<(VO-1)', '\tadc\t#0', '\tsta\ttA6+1'],
                   C['lda'] + 2 + 4 + C['cmp#'] + C['lda#'] + C['adc#'] + C['sta']),
        ('B', 6): (['\tldy\tbq', '\tlda\tMOD160+1,y', '\tsta\tbq'],
                   C['ldy'] + C['ldaY'] + C['sta']),    # the next pair's block row
    }
    # the byte each tail loads: the next line's (line k+1, or the next row's line 0):
    # VE on even lines, VO on odd, an odd row's line 7 always 0.  After line 7: into a
    # B row, the same block row, VE; into an A row, a new block row, VEN (the A1 slice
    # has yet to copy it to VE)
    def src(P, k):
        if k == 7:
            return 'VE' if P == 'A' else 'VEN'
        if P == 'B' and k == 6:
            return '#0'                                 # an odd row's line 7: the grid
        return 'VE' if (k + 1) % 2 == 0 else 'VO'

    L = [HEADER, '\t.segment "LOOP2"', '\t.assert\t<* = 0, error, "loop 2 must start a page"',
         '\t.assert\t<LEAKCELL = 0, error, "the B5 slice compares only the leak cell\'s high byte"']
    for P in ('A', 'B'):
        for k in range(8):
            nxt = f'b{P}{k + 1}' if k < 7 else f'b{other[P]}0'
            code, cyc = SLICE.get((P, k), ([], 0))
            L += ['\t.align\t64', f'b{P}{k}:']
            L += code
            if k < 7:
                L += [f'\tinc\tg{P}+1', f'\tinc\tg{P}+6']
                cyc += 2 * C['inc']
            L += [f'hk{P}{k}:\tlda\t#<{nxt}', '\tsta\tVRET']
            cyc += C['lda#'] + C['sta']
            if k in (3, 7):
                L += [f'\tlda\t#>{nxt}', '\tsta\tVRET+1']
                cyc += C['lda#'] + C['sta']
            else:
                L.append(f'\t.assert\t>{nxt} = >*, error, "a block\'s successor must share its page"')
            if k == 7:
                # arming the exit ("The exit"): when the row count (rows, set by
                # build) reaches zero, the chosen block's 'lda #<next / sta VRET'
                # becomes 'lda #<VX / sta VJ', so the last line's gadget jumps to VX.
                # build patches the two stores' operands (hkA0 here) to point at the
                # chosen block's hook, and restores the block each field.  Both paths
                # take the same time.
                L += ['\tdec\trows', f'\tbne\t:+', '\tlda\t#<VX', f'arm{P}1:\tsta\ta:hkA0+1',
                      '\tlda\t#<VJ', f'arm{P}2:\tsta\ta:hkA0+3', '\tjmp\t:++', ':\tDELAY\t14', ':']
                cyc += 6 + 17
            L.append(f'\tDELAY\tBLK_LEN-{cyc}')
            s_ = src(P, k)
            L += [f't{P}{k}:\tlda\t{s_}\t\t; the next line\'s entering byte']
            if s_.startswith('#'):
                L.append('\tPADN\t2\t\t; (an immediate load: as long as lda abs)')
            L.append('\tstx\tULA_MODE\t\t; the blip (X: its mode value)')
            L.append(f'\tjmp\tg{P if k < 7 else other[P]}')
            L.append(f'\t.assert\t* - b{P}{k} <= 64, error, "a line block must fit its 64-byte slot"')
    for P in ('A', 'B'):
        L += [f'g{P}:\tsta\ta:DUMMY\t\t; the entering cell <- A (address set per row, stepped per line)',
              '\tlda\t#0', '\tsta\ta:DUMMY\t\t; the leaving cell <- 0 (likewise)',
              '\tPADN\tPAD_W1', '\tlda\t#M3', '\tsta\tULA_MODE\t\t; MODE 3 in the sync', '\tPADN\tPAD_W2',
              f'vc{P}:\tlda\t#M1\t\t; patched each field: the lead-in mode (mode 7, or MW)', '\tsta\tULA_MODE',
              '\tlda\t#MW\t\t; the window\'s mode, for the variant',
              '\tPADN\tPAD_W3', '\tjmp\t(VJ)\t\t; the variant, or VX on the last line']
    L.append('\t.assert\t>VRET = >VJ, error, "VRET and VJ must share a page (the exit patch)"')
    # tables by block index 8 * parity + line, for build (strip.s): each block, its
    # tail, its hook's two patch points (the immediate, the store's operand), its
    # successor's low byte
    L.append('\t.segment "TABLES3"')
    idx = [(P, k) for P in ('A', 'B') for k in range(8)]
    nxt = lambda P, k: f'b{P}{k + 1}' if k < 7 else f'b{other[P]}0'
    for name, f in (('BLKL', lambda P, k: f'<b{P}{k}'), ('BLKH', lambda P, k: f'>b{P}{k}'),
                    ('TAILL', lambda P, k: f'<t{P}{k}'), ('TAILH', lambda P, k: f'>t{P}{k}'),
                    ('HKAL', lambda P, k: f'<(hk{P}{k}+1)'), ('HKAH', lambda P, k: f'>(hk{P}{k}+1)'),
                    ('HKBL', lambda P, k: f'<(hk{P}{k}+3)'), ('HKBH', lambda P, k: f'>(hk{P}{k}+3)'),
                    ('HKNXT', lambda P, k: f'<{nxt(P, k)}')):
        L.append(f'{name}:\t.byte ' + ','.join(f(P, k) for P, k in idx))
    L.append('\tNOCROSS\tBLKL, 16*9')
    return '\n'.join(L) + '\n'


def table(name, vals, align=True):
    out = ['\t.align 256'] if align else []
    out.append(f'{name}:')
    for i in range(0, len(vals), 16):
        out.append('\t.byte ' + ','.join(f'${v & 255:02X}' for v in vals[i:i + 16]))
    return out


def lead_in_index():
    """t = (WIN_C - wx) & 7 for each wx & 7, and the variant number u for each dispatch
    table index (wx & 7) | sched: sched = 0, the FPGA ULA's schedule, u = t; sched = 8,
    the real ULA's, u = t + 1 (its 40-column address steps half a microsecond earlier,
    so the switch out of the 40-column mode costs a character fewer), 0 when t = 0
    ("Two ULAs: the schedules")."""
    tx = [(WIN_C - x) & 7 for x in range(8)]
    ux = [(0 if tx[x] == 0 else tx[x] + 1) if real else tx[x] for real in (0, 1) for x in range(8)]
    return tx, ux


def gen_tables():
    pe = [DITH[IDX[v]][0] for v in range(256)]
    po = [DITH[IDX[v]][1] for v in range(256)]
    L = [HEADER, '\t.segment "TABLES"']
    # the pattern: hash value -> the block's even- and odd-line bytes, and the same with
    # the block's left (black) pixel column
    L += table('PERM', PERM)
    L += table('PE', pe)
    L += table('PO', po)
    L += table('PEM', [b & LMASK for b in pe])
    L += table('POM', [b & LMASK for b in po])
    # ring arithmetic: hi byte of an address that may have left &3000-&7FFF -> back in
    L += table('WRAPHI', [(h - 0x50) & 0xFF if h >= 0x80 else (h + 0x50) & 0xFF if h < 0x30 else h
                          for h in range(256)])
    # hi byte of a sum < &A000 -> (mod &5000) + &30: a ring address
    L += table('RINGHI', [((h % 0x50) + 0x30) if h < 0xA0 else 0 for h in range(256)])
    # map coordinates: hi byte mod &0A (2560 = &0A00); block row + 1 mod 160; the hi
    # byte after a step of at most +-255 back into 0..2559
    L += table('MOD2560H', [h % 0x0A for h in range(256)])
    L += table('MOD160', [h % 160 for h in range(256)])
    L += table('MAPHI', [0 if h == 0x0A else (0x09 if h == 0xFF else h) for h in range(256)])
    # (576 * row) mod &5000 for rows 0..319, lo and hi tables of 320
    r576 = [(ROWB * y) % RING for y in range(320)]
    L += table('R576L', [v & 255 for v in r576[:256]])
    L += table('R576H', [v >> 8 for v in r576[:256]])
    # rows 256..319: the two 64-entry tails share a page (indexed 0..63, no crossing)
    L += table('R576LT', [v & 255 for v in r576[256:]])
    L += table('R576HT', [v >> 8 for v in r576[256:]], align=False)
    # the lead-in dispatch, 16 entries each by (wx & 7) | sched (lead_in_index()),
    # fills the rest of the tails' page: the variant of each loop part, the blip's mode
    # value (M5 when u <= 1, else MW: no change) and the lead-in write's (MW when u = 0,
    # else mode 7)
    tx, ux = lead_in_index()
    L.append('VSP_BY_X:\t.byte ' + ','.join(f'<VSP{u}' for u in ux))
    L.append('VSPH_BY_X:\t.byte ' + ','.join(f'>VSP{u}' for u in ux))
    L.append('VS2_BY_X:\t.byte ' + ','.join(f'<VS2{u}' for u in ux))   # (VJ: low byte only)
    L.append('VA_BY_X:\t.byte ' + ','.join(f'${M5 if u < 2 else MW:02X}' for u in ux))
    L.append('VC_BY_X:\t.byte ' + ','.join(f'${M7 if u else MW:02X}' for u in ux))
    L.append('\tNOCROSS\tR576LT, VC_BY_X + 16 - R576LT')
    # small tables, unaligned, after the hand-written ones (segment TABLES3)
    L.append('\t.segment "TABLES3"')
    # LE[4 c + k] = 1 if notch class c is due at phase k (c <= k)
    L.append('LE:\t.byte ' + ','.join(str(int(c <= k)) for c in range(4) for k in range(4)))
    L.append('\tNOCROSS\tLE, 16')
    L.append('T_BY_X:\t.byte ' + ','.join(str(t) for t in tx))
    L.append('\tNOCROSS\tT_BY_X, 8')
    scr = []
    for seg in SCRIPT:
        scr += [seg[0], seg[1] & 255, seg[2], seg[3] & 255, seg[4]]
    L += table('SCRIPT', scr + [0], align=False)
    return '\n'.join(L) + '\n', pe, po


def gen_config():
    if SCRMODE == 1:
        p8, p9 = palette_bytes()
        rest = [0xFF] * 6                       # (only MODE 2 reads &FE0A-&FE0F)
    else:
        p8, p9, *rest = palette_bytes2()
    return '\n'.join([
        HEADER,
        f'Y0 = {Y0}', f'Y1 = {Y1}', f'H = {H}', f'WIN_C = {WIN_C}', f'WIN_W = {WIN_W}',
        f'GAP = {72 - WIN_W}',
        f'M1 = ${M1:02X}', f'M3 = ${M3:02X}', f'M4 = ${M4:02X}', f'M5 = ${M5:02X}', f'M6 = ${M6:02X}', f'M7 = ${M7:02X}',
        f'NROWS = {NROWS}',
        f'PAL8 = ${p8:02X}', f'PAL9 = ${p9:02X}',
        *[f'PAL{r} = ${v:02X}' for r, v in zip('ABCDEF', rest)],
        f'SCRMODE = {SCRMODE}', f'M2 = ${M2:02X}', f'MW = ${MW:02X}', f'LMASK = ${LMASK:02X}',
    ]) + '\n'


def main(out):
    os.makedirs(out, exist_ok=True)
    tables, pe, po = gen_tables()
    files = {
        'config.inc': gen_config(),
        'gen_tables.s': tables,
        'gen_variants.s': gen_variants(),
        'gen_loop2.s': gen_loop2(),
    }
    for name, text in files.items():
        with open(os.path.join(out, name), 'w') as f:
            f.write(text)
    # the model for emu/elkh's soak: Y0, H, WIN_C, WIN_W, then PERM, PE, PO
    with open(os.path.join(out, 'model.bin'), 'wb') as f:
        f.write(bytes([Y0, H, WIN_C, WIN_W]) + bytes(PERM) + bytes(pe) + bytes(po))
        # then the window's mode and PAL2 as the emulator's pixel values (red 4, green
        # 2, blue 1), written in both modes; the checker uses it for MODE 2
        f.write(bytes([SCRMODE]) + bytes(((c & 1) << 2) | (c & 2) | (c >> 2) for c in PAL2))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
