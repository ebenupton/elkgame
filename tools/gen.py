#!/usr/bin/env python3
"""Generated source for the scroll demo, and the model its checks compare against.

    python3 tools/gen.py OUTDIR

writes, into OUTDIR:

    config.inc      geometry, mode values and palette bytes (assembler constants)
    gen_tables.s    the pattern, ring-arithmetic and dispatch tables (segment TABLES)
    gen_variants.s  the lead-in variants and the window's exit block (segment VARIANTS)
    gen_snips.s     the strip's row snippets (segment SNIPS)
    model.bin       the pattern for the emulator's in-process checker (emu/elkh soak)

Everything here is a pure function of the constants below: the build is deterministic.
docs/DESIGN.md explains the engine; the references below (section numbers) are to it.

The playfield
-------------
A map of 2560 x 2560 MODE 1 characters (it repeats in both directions), shown through
a window of WIN_W characters x H scanlines.  The map is a grid of 16 x 16-pixel blocks
(4 characters x 2 character rows), each filled with one of the 35 dithered colours of
swatch35, chosen by a hash of the block's coordinates.  Every block's left pixel column
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

# ---- geometry (DESIGN.md section 2) ------------------------------------------------
Y0 = 30            # first window scanline (the text-mode band above it is at most 30 lines)
Y1 = 200           # first scanline below the window (MODE 6 from here to the field's end)
H = Y1 - Y0        # window height in scanlines
WIN_C = 15         # screen character (MODE 1, 0..79) of the window's left edge: the
                   # longest lead-in (8 us on the real ULA) must end before it
WIN_W = 57         # window width in characters.  WIN_C + WIN_W <= 72, so the cells a
                   # coarse step exposes are the 72-character ring row's gap cells
assert WIN_C >= 14 and WIN_C + WIN_W <= 72 and WIN_W <= 61
MAPW = 2560        # map period, in characters across and in scanlines down
RING = 0x5000      # the 20K screen ring the ULA wraps (&3000-&7FFF)
ROWB = 576         # bytes in a ring row: 72 characters

# ---- the ULA's mode register values (&FE07; comms off, LED and motor off) ----------
M1, M3, M5, M6 = 0x08, 0x18, 0x28, 0x30
M7 = 0x38          # mode value 7: fetches like MODE 4 (40 columns), but the real ULA
                   # wraps it at &8000 to &3000 (MODE 5 wraps to &5800)

# ---- palette ------------------------------------------------------------------------
K, C, M, Y = 0, 1, 2, 3
PAL_RGB = {0: (0, 0, 0), 1: (0, 1, 1), 2: (1, 0, 1), 3: (1, 1, 0)}   # logical -> RGB


def palette_bytes():
    """&FE08/&FE09 for PAL_RGB in MODE 1 (a set bit turns the component off)."""
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
DITH = dithers()
IDX = [PERM2[v] % 35 for v in range(256)]          # hash value -> colour number


def block_colour(bx, by):
    """Colour number of block (bx, by).  The map's 160 block rows step the second term
    mod 256 in the engine as well: rows wrap through MOD160 (gen_tables.s)."""
    return IDX[(PERM[bx & 255] + (by & 255)) & 255]


def pixel(mx, my):
    """Logical colour of map pixel (mx in MODE 1 pixels, my in scanlines)."""
    if (mx & 15) == 0 or (my & 15) == 15:
        return 0
    ev, od = DITH[block_colour(mx >> 4, my >> 4)]
    b = od if (my & 1) else ev
    p = mx & 3
    return ((b >> (7 - p)) & 1) << 1 | ((b >> (3 - p)) & 1)


def expected_window(wx, wy):
    """The window's pixels for position (wx, wy): H rows of WIN_W * 4 logical colours."""
    return [[pixel((wx * 4 + x) % (MAPW * 4), (wy + y) % MAPW) for x in range(WIN_W * 4)]
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

# ---- lead-in schedules and the FPGA phase model (DESIGN.md section 4) --------------
# Every window line has the same shape.  For t = (WIN_C - wx) & 7:
#   t = 1..7: MODE 5 (40 columns) from the blanking, MODE 1 at t us: the line's address
#             counter falls t characters behind and the line fetches 80 - t;
#   t = 0:    MODE 1 throughout, and MODE 5 for the last 2-3 us of the line, in the
#             right margin (the "blip"): the line fetches 77-78, not 80, so that the
#             start-of-row register (A14..A6) still advances by 576, not 640;
#   always:   MODE 3 for part of the line sync, so that line 7 of a character row is
#             not a "last line" and line 0 of the next row restarts from the latch.
# SCHED_START[t] lists (us after S, mode) for the FPGA ULA.  The real ULA's schedule
# is t + 1 us, with mode 7 in place of MODE 5 (DESIGN.md 4.3); the phase model below
# is the FPGA's, matched to an nvc simulation of hoglet's ElectronFpga.
SCHED_START = {t: ([(t, 'M1')] if t else []) for t in range(0, 8)}

# Phase model: with a stalled read ending at h = S (1/16 us ticks), a write '+u' us
# after S is first used by the video logic at h = 16u + (S - 656); MODE 5 steps the
# address at h = 15 (mod 16), MODE 1 at h = 7 (mod 8).  CLK corresponds to S = 648,
# the FPGA's own power-up phase to 656.
S_RANGE = range(648, 660)      # the phases every schedule must work at
U_BLIP, U_M3, U_C = -3, 9, 18  # the line's other writes, us after S
HS0, HS1 = 768, 832            # the line sync (FPGA hsync_start, hsync_end)


def _sim(s0, ws, S, upto=640, forbid=None, mode='M5', blip=None):
    """Step a line's fetches from character s0 under writes ws.  Returns (MODE 5 steps,
    character reached at h = upto), or None if a MODE 5 step leaves a character in
    forbid (relative to the row)."""
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
    """Does lead-in t work at phase S?"""
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


# ---- generated code (DESIGN.md sections 3 and 5) -----------------------------------
NSNIP = 25          # row snippets: the window touches 22 or 23 character rows
SNSTR = 32          # bytes a snippet (8 a page)

HEADER = '; generated by tools/gen.py -- do not edit'


def gen_variants():
    """The lead-in variants VS{part}{u}, u = 0..8, for the scanline loop's three parts
    (1: the lines above the window, P: the palette line, 2: the window).  Each is
    entered by jmp (vector) at cycle 41 after S with A = M1; VSu is u nops and the
    store (which lands at S + 23 + u us), padded so that all take the same time, then
    jmp back{part}.  VS0 writes nothing.  The window's variants share a page with VX,
    the exit block, entered through the same vector at offset M1 or M5 (the last
    iteration takes the vector's low byte from Y, the +17 mode value)."""
    check_schedules()
    L = [HEADER, '\t.segment "VARIANTS"']
    vx = ['\tlda\t#$FF', '\tsta\tULA_PAL8', '\tsta\tULA_PAL9', '\tlda\t#M6', '\tsta\tULA_MODE', '\tjmp\twork']
    L += ['VPAGE:', f'\t.res\t{M1}', 'VX:'] + vx + [f'\t.res\t{M7 - M1 - 16}'] + vx
    for part in ('2', '1', 'P'):
        for u in range(9):
            L.append(f'VS{part}{u}:')
            if u:
                L += ['\tnop'] * u + ['\tsta\tULA_MODE', f'\tDELAY\t{2 * (8 - u)}']
            else:
                L.append('\tDELAY\t21')
            L.append(f'\tjmp\tback{part}')
            if part == '2' and u == 8:
                L.append('\t.assert\t>VPAGE = >*, error, "the window\'s variants and VX must share a page"')
    return '\n'.join(L) + '\n'


def gen_snips():
    """The strip: NSNIP row snippets of SNSTR bytes, and the dummy one (DESIGN.md 5.2).
    Snippet p stores, for line X of its character row, the entering column's byte
    (from VBUF) at SNpA1 and a zero at SNpA2 -- both operands patched by build --
    writes MODE 3 in the sync and the +17 mode value (Y), and jumps to the variant."""
    def body(n, vbuf, vec):
        return [f'\tlda\tVBUF+{vbuf},x' if n is not None else '\tlda\tVBUF,x',
                f'SN{n}A1:\tsta\ta:DUMMY,x' if n is not None else '\tsta\ta:DUMMY,x',
                '\tlda\t#M3', '\tsta\tULA_MODE', '\tlda\t#0',
                f'SN{n}A2:\tsta\ta:DUMMY,x' if n is not None else '\tsta\ta:DUMMY,x',
                '\tsty\tULA_MODE', '\tlda\t#M1', f'\tjmp\t({vec})']
    L = [HEADER, '\t.segment "SNIPS"']
    for p in range(NSNIP - 1):
        L += [f'SN{p}:'] + body(p, 8 * p, 'VVEC2') + [f'\t.res\t{SNSTR - 24}']
    # The last is never built: only the exit iteration can reach it, ahead of the
    # beam, where its stores are not needed
    L += [f'SN{NSNIP - 1}:'] + body(None, 0, 'VVEC2')
    L += ['DSNIP:'] + body(None, 0, 'VVEC1')
    return '\n'.join(L) + '\n'


def table(name, vals, align=True):
    out = ['\t.align 256'] if align else []
    out.append(f'{name}:')
    for i in range(0, len(vals), 16):
        out.append('\t.byte ' + ','.join(f'${v & 255:02X}' for v in vals[i:i + 16]))
    return out


def lead_in_index():
    """t = (WIN_C - wx) & 7 for each wx & 7, and the variant number u for each table
    index (wx & 7) | 8 (the real ULA's schedule).  FPGA ULA: u = t.  Real ULA: u = t + 1
    (its switch out of the 40-column mode costs a character fewer), 0 when t = 0
    (DESIGN.md 4.3)."""
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
    L += table('PEM', [b & 0x77 for b in pe])
    L += table('POM', [b & 0x77 for b in po])
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
    # the lead-in dispatch, by lead_in_index(), fills the rest of the tails' page: the
    # variant of each loop part, the blip's mode value (M5 when u <= 1) and the +17
    # write's (M1 when u = 0, else mode 7)
    tx, ux = lead_in_index()
    for part in ('1', 'P', '2'):
        L.append(f'VS{part}_BY_X:\t.byte ' + ','.join(f'<VS{part}{u}' for u in ux))
        L.append(f'VS{part}H_BY_X:\t.byte ' + ','.join(f'>VS{part}{u}' for u in ux))
    L.append('VA_BY_X:\t.byte ' + ','.join(f'${M5 if u < 2 else M1:02X}' for u in ux))
    L.append('VC_BY_X:\t.byte ' + ','.join(f'${M7 if u else M1:02X}' for u in ux))
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
    p8, p9 = palette_bytes()
    return '\n'.join([
        HEADER,
        f'Y0 = {Y0}', f'Y1 = {Y1}', f'H = {H}', f'WIN_C = {WIN_C}', f'WIN_W = {WIN_W}',
        f'GAP = {72 - WIN_W}',
        f'M1 = ${M1:02X}', f'M3 = ${M3:02X}', f'M5 = ${M5:02X}', f'M6 = ${M6:02X}', f'M7 = ${M7:02X}',
        f'NSNIP = {NSNIP}', f'SNSTR = {SNSTR}',
        f'PAL8 = ${p8:02X}', f'PAL9 = ${p9:02X}',
    ]) + '\n'


def main(out):
    os.makedirs(out, exist_ok=True)
    tables, pe, po = gen_tables()
    files = {
        'config.inc': gen_config(),
        'gen_tables.s': tables,
        'gen_variants.s': gen_variants(),
        'gen_snips.s': gen_snips(),
    }
    for name, text in files.items():
        with open(os.path.join(out, name), 'w') as f:
            f.write(text)
    # the model for emu/elkh's soak: Y0, H, WIN_C, WIN_W, then PERM, PE, PO
    with open(os.path.join(out, 'model.bin'), 'wb') as f:
        f.write(bytes([Y0, H, WIN_C, WIN_W]) + bytes(PERM) + bytes(pe) + bytes(po))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
