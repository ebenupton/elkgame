#!/usr/bin/env python3
"""Every branch in the demo's code that crosses a page when taken (and so costs a
cycle more), with its source line -- and the line inside a macro, if it is in one.

    python3 tools/pagecheck.py BUILD [SEGMENT,...]

Reads BUILD/elk.dbg (ld65's debug file, which the Makefile writes) and BUILD/elk.bin.
The segments default to every one that holds code.  A crossing branch in the
fixed-length work below the window adds a cycle to one path only, which the
calibration then has to absorb; in the scanline loop's segments there must be none
(the source asserts each loop's page).  Adapted from beebgame's tools/pagecheck.py.
"""
import re
import sys

CODE = 'ENTRY,LOOP,LOOP2,SNIPS,TAILS,VARIANTS,DLOOP,CODE,NSTORE,VCODE'
BRANCHES = {0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0}


def crossings(build, want):
    dbg = open(f'{build}/elk.dbg').read()
    files = {m[1]: m[2] for m in re.finditer(r'^file\tid=(\d+),name="([^"]+)"', dbg, re.M)}
    segs = {m[1]: dict(name=m[2], start=int(m[3], 16), size=int(m[4], 16), ooffs=m[5])
            for m in re.finditer(r'^seg\tid=(\d+),name="(\w+)",start=0x([0-9A-F]+),size=0x([0-9A-F]+)'
                                 r'[^\n]*?(?:ooffs=(\d+))?$', dbg, re.M)}
    spans = {m[1]: (m[2], int(m[3]), int(m[4]))
             for m in re.finditer(r'^span\tid=(\d+),seg=(\d+),start=(\d+),size=(\d+)', dbg, re.M)}
    src, mac, starts = {}, {}, set()
    for m in re.finditer(r'^line\tid=\d+,file=(\d+),line=(\d+)(,type=\d+)?(,count=\d+)?,span=([\d+]+)', dbg, re.M):
        loc = f'{files[m[1]].split("/")[-1]}:{m[2]}'
        table = mac if m[3] else src
        for sid in m[5].split('+'):
            sg, st, sz = spans[sid]
            if sz == 2:
                starts.add((sg, st))        # a 2-byte instruction (or datum) starts here
            for a in range(st, st + sz):
                if (sg, a) not in table or sz < table[(sg, a)][1]:
                    table[(sg, a)] = (loc, sz)
    image = open(f'{build}/elk.bin', 'rb').read()
    out = []
    for sid, sg in segs.items():
        if sg['name'] not in want or sg['ooffs'] is None:
            continue
        img = image[int(sg['ooffs']):int(sg['ooffs']) + sg['size']]
        for off in range(len(img) - 1):
            s0, m0 = src.get((sid, off)), mac.get((sid, off))
            if img[off] not in BRANCHES or s0 is None or (sid, off) not in starts:
                continue                    # not the first byte of a 2-byte span
            d = img[off + 1] - 256 if img[off + 1] > 127 else img[off + 1]
            pc = sg['start'] + off + 2
            target = (pc + d) & 0xFFFF
            if pc >> 8 != target >> 8:
                out.append((sg['name'], sg['start'] + off, target, s0[0] + (' > ' + m0[0] if m0 else '')))
    return sorted(out)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    found = crossings(sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else CODE).split(','))
    for name, addr, target, loc in found:
        print(f'{name:8s} ${addr:04X} -> ${target:04X}  {loc}')
    print(f'{len(found)} crossing branches')
