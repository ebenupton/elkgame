#!/usr/bin/env python3
"""Compare two timing fingerprints (test/fingerprint.sh) of the same trajectory.

    python3 test/fpcompare.py OLD NEW

For each field, three things:
  picture   every mode and palette write (&FE07-&FE09) from line 0 to the window's
            exit, at its raster position: these place the picture, and must match
            exactly -- the lock re-synchronises every field, so nothing done below the
            window can move them unless the lock fails;
  fixed     the length of the fixed work below the window: from the display-end poll's
            last read (the first status read at line >= 240 with the flag set) to the
            screen-start write in ula_apply (&FE02);
  lock      where the lock read lands in line 0 (the last status read before the
            palette line's first write).
The two runs are first aligned on their sequences of screen-start writes (a change to
the start-up code can shift the program's fields against the capture's by one or two).
Prints the fields whose picture writes differ (exit status 1 if any) and histograms of
the differences in the fixed work's length and the lock position, in CPU cycles.
"""
import collections
import sys


def fields(path):
    out = collections.defaultdict(list)
    with open(path) as f:
        for line in f:
            k, v, h, rw, reg, val = line.split()
            out[int(k)].append((int(v), int(h), rw, reg, val))
    return out


def summary(acc):
    pic = [(v, h, reg, val) for v, h, rw, reg, val in acc
           if rw == 'W' and reg in ('FE07', 'FE08', 'FE09') and v <= 200]
    t = lambda v, h: v * 1024 + h
    de = next((t(v, h) for v, h, rw, reg, val in acc
               if rw == 'R' and reg == 'FE00' and v >= 240 and int(val, 16) & 4), None)
    sa = next((t(v, h) for v, h, rw, reg, val in acc if rw == 'W' and reg == 'FE02' and v >= 240), None)
    fixed = (sa - de) // 8 if de is not None and sa is not None else None
    lock = None
    for v, h, rw, reg, val in acc:
        if rw == 'W' and reg == 'FE08' and val != 'FF':
            break
        if rw == 'R' and reg == 'FE00' and v == 0:
            lock = h // 8
    return pic, fixed, lock


def screen_starts(fs):
    return [tuple(val for v, h, rw, reg, val in fs[k] if rw == 'W' and reg in ('FE02', 'FE03') and v >= 240)
            for k in sorted(fs)]


def main(a, b):
    fa, fb = fields(a), fields(b)
    sa, sb = screen_starts(fa), screen_starts(fb)
    W = 20                         # the alignment's search range, fields
    n = min(len(fa), len(fb)) - W
    off = max(range(-W, W + 1), key=lambda o: sum(1 for k in range(W + 10, n) if sa[k] == sb[k + o]))
    print(f'aligned with an offset of {off} field(s)')
    bad = 0
    dfix, dlock = collections.Counter(), collections.Counter()
    for k in range(W + 10, n):     # (the first fields are the start-up's)
        pa, xa, la = summary(fa[k])
        pb, xb, lb = summary(fb[k + off])
        if pa != pb:
            bad += 1
            if bad <= 5:
                print(f'field {k}: picture writes differ')
        if xa is not None and xb is not None:
            dfix[xb - xa] += 1
        if la is not None and lb is not None:
            dlock[lb - la] += 1
    print(f'{n - W - 10} fields: picture writes differ in {bad}')
    print('fixed work, new - old (cycles: fields):', ' '.join(f'{d:+d}:{c}' for d, c in sorted(dfix.items())))
    print('lock read, new - old (cycles: fields): ', ' '.join(f'{d:+d}:{c}' for d, c in sorted(dlock.items())))
    return 1 if bad else 0


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
