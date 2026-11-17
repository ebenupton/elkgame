#!/usr/bin/env python3
"""Disc and tape images of the scroll demo.

    python3 tools/mkimages.py BINARY OUTDIR

Writes OUTDIR/elkscroll.ssd, a DFS disc (80 tracks, single-sided) whose !BOOT *RUNs
ELKSCRL, with boot option 3 so that SHIFT+BREAK starts it (a Plus 3 with a DFS, MMFS on
an ElkSD, a Gotek, ...), and OUTDIR/elkscroll.uef, the same program on tape (*RUN or
CHAIN"" and PLAY).  The program loads and runs at &2000."""
import os
import struct
import sys

NAME = 'ELKSCRL'
LOAD = EXEC = 0x2000


def ssd(data, title='ELK SCROLL'):
    """A DFS disc image holding !BOOT and the program."""
    boot = b'*RUN ' + NAME.encode() + b'\r'
    files = [('!BOOT', boot, 0, 0), (NAME, data, LOAD, EXEC)]
    sectors = 800
    img = bytearray(sectors * 256)
    sec = 2
    placed = []
    for name, body, load, exe in files:
        img[sec * 256: sec * 256 + len(body)] = body
        placed.append((name, body, load, exe, sec))
        sec += (len(body) + 255) // 256
    t = title.ljust(12)[:12].encode()
    img[0:8] = t[:8]
    img[256:260] = t[8:12]
    img[256 + 4] = 0x00                       # cycle number
    img[256 + 5] = len(placed) * 8
    img[256 + 6] = (3 << 4) | ((sectors >> 8) & 3)   # boot option 3: *EXEC !BOOT
    img[256 + 7] = sectors & 255
    # catalogue order: highest start sector first
    for i, (name, body, load, exe, start) in enumerate(sorted(placed, key=lambda p: -p[4])):
        e = 8 + 8 * i
        img[e:e + 7] = name.ljust(7).encode()
        img[e + 7] = ord('$')
        ln = len(body)
        img[256 + e + 0] = load & 255
        img[256 + e + 1] = (load >> 8) & 255
        img[256 + e + 2] = exe & 255
        img[256 + e + 3] = (exe >> 8) & 255
        img[256 + e + 4] = ln & 255
        img[256 + e + 5] = (ln >> 8) & 255
        # start sector bits 8-9, load address bits 16-17 (&FFFF: the I/O processor's),
        # length bits 16-17, execution address bits 16-17 (likewise)
        img[256 + e + 6] = ((start >> 8) & 3) | (3 << 2) | (((ln >> 16) & 3) << 4) | (3 << 6)
        img[256 + e + 7] = start & 255
    return bytes(img)


def crc16(data):
    """The Acorn tape filing system's block CRC (CRC-16/XMODEM: polynomial &1021,
    initial 0, MSB first)."""
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else (crc << 1)
            crc &= 0xFFFF
    return crc


def uef(data):
    """A UEF tape image: 256-byte CFS blocks with carrier tone between them."""
    out = bytearray(b'UEF File!\0' + bytes([10, 0]))

    def chunk(cid, body):
        out.extend(struct.pack('<HI', cid, len(body)) + body)

    chunk(0x0110, struct.pack('<H', 5000))     # leading carrier
    nblocks = (len(data) + 255) // 256
    for n in range(nblocks):
        part = data[n * 256:(n + 1) * 256]
        flag = 0x80 if n == nblocks - 1 else 0x00
        hdr = (NAME.encode() + b'\0' + struct.pack('<IIHHB', 0xFFFF0000 | LOAD, 0xFFFF0000 | EXEC,
                                                     n, len(part), flag) + struct.pack('<I', 0))
        blk = b'*' + hdr + struct.pack('>H', crc16(hdr)) + part + struct.pack('>H', crc16(part))
        chunk(0x0100, blk)
        chunk(0x0110, struct.pack('<H', 600 if n < nblocks - 1 else 2000))
    return bytes(out)


def main(binary, outdir):
    data = open(binary, 'rb').read()
    os.makedirs(outdir, exist_ok=True)
    open(os.path.join(outdir, 'elkscroll.ssd'), 'wb').write(ssd(data))
    open(os.path.join(outdir, 'elkscroll.uef'), 'wb').write(uef(data))
    print(f'{len(data)} bytes -> elkscroll.ssd, elkscroll.uef')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
