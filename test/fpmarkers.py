#!/usr/bin/env python3
"""The fixed work's sections, from a timing fingerprint (test/fingerprint.sh).

    python3 test/fpmarkers.py FINGERPRINT

After the display-end poll, frame.s reads the status register as a marker at three
points: just after the poll (m1); at wk_pl (m2), after the vertical step's stores
(nstore) and the column step's edge rows, or the idle field's pad; and before
setup_frame (m3), after CAL_SPARE.  Over all fields, prints the distribution of
m2 - m1 (labelled "edge rows": the stores and the edge rows together) and of m3 - m2
(labelled "spare": CAL_SPARE and the commit bookkeeping around it), in CPU cycles.  The work is fixed-length, so each should be a
single value."""
import collections
import sys

sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import fpcompare  # noqa: E402


def sections(acc):
    t = lambda v, h: v * 1024 + h
    reads = [(v, h, val) for v, h, rw, reg, val in acc if rw == 'R' and reg == 'FE00' and v >= 240]
    k = next((i for i, (v, h, val) in enumerate(reads) if int(val, 16) & 4), None)
    if k is None or k + 3 >= len(reads):
        return None
    m1, m2, m3 = (t(v, h) for v, h, _ in reads[k + 1:k + 4])
    return (m2 - m1) // 8, (m3 - m2) // 8


def main(path):
    out = collections.defaultdict(collections.Counter)
    for k, acc in fpcompare.fields(path).items():
        s = sections(acc)
        if s:
            out['edge rows'][s[0]] += 1
            out['spare'][s[1]] += 1
    for name, c in out.items():
        print(f'{name:9s}', ' '.join(f'{d}:{n}' for d, n in sorted(c.items())))


if __name__ == '__main__':
    main(sys.argv[1])
