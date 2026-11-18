; vars.s -- the variables, in the sideways RAM bank (2 MHz, like the code).  There is
; no zero-page use: the bank's absolute addressing is as fast as main RAM's zero page,
; and the OS's workspace is left alone.

	.segment "VARS"
	.align	256
; ---- the scanline loop's parameters for the next field (setup_frame, build) ----
VVEC1:	.res	2			; the lead-in variant, for loop 1 and the palette line
VVECP:	.res	2
	NOWRAP	VVEC1
	NOWRAP	VVECP
k0:	.res	1			; the first window line's line within its row
VRET:	.res	2			; loop 2: the next line's block (set by each block)
VJ:	.res	2			; loop 2: the gadgets' jump: this field's variant, or VX
	NOWRAP	VRET
	NOWRAP	VJ
vav:	.res	1			; the blip's mode value (X through loop 2)
VE:	.res	1			; the entering column's bytes for this colour pair:
VO:	.res	1			;   even lines, odd lines (an odd row's line 7 is 0)
VEN:	.res	1			; and for the next pair
VON:	.res	1
VNX:	.res	1			; the next pair's hash value
bq:	.res	1			; this pair's block row (0..159)
rows:	.res	1			; line-7 blocks until the exit is armed
hkprev:	.res	1			; the block (8 parity + line) whose hook the exit patched last field
cin0:	.res	2			; strip.s: the first row's entering and leaving cells
cout0:	.res	2
n1:	.res	1			; loop 1's iterations (lines above the palette line's)
cnt1:	.res	1			; (its counter)
vcv:	.res	1			; the lead-in mode value (loop 1, the palette line)
tv:	.res	1			; t, the lead-in in characters
cb8:	.res	2			; 8 x the window's first fetched column
band_n:	.res	1			; lines from line 0 to the first iteration
topmode: .res	1			; line 0's mode
fe02v:	.res	1			; the screen start registers' values
fe03v:	.res	1

; ---- position and motion ----
bank:	.res	1			; this bank's number (for paging back after the keyboard)
wx:	.res	2			; the window position shown next field: map column ...
wy:	.res	2			; ... and scanline
mx:	.res	2			; the window's left column as the ring holds it
cnext:	.res	1			; columns committed for the next field (-2..2)
cnext2:	.res	1			; and for the field after
hnew:	.res	1			; the commit logic chose this field (cnext2 next)
smode:	.res	1			; the strip: 0 idle, 1 ahead (a commit), 2 behind
dy:	.res	1			; lines to move this field (-2..2)
fpar:	.res	1			; the field: 1 = the 313-line one
gch:	.res	1			; characters the vertical step drew this field (for the soak)

; ---- the trajectory and the keys (logic) ----
segl:	.res	1			; fields left in the segment
sdx:	.res	1			; the segment's columns a commit,
sgap:	.res	1			;   fields between commits,
sdy:	.res	1			;   lines a vertical step,
svd:	.res	1			;   and fields between vertical steps
vdiv:	.res	1			; fields to the next vertical step
hcnt:	.res	1			; fields to the next commit allowed
scrp:	.res	1			; the script's offset (5 bytes a segment)
lfsr:	.res	2			; the random walk's generator
autob:	.res	1			; the motion is on (SPACE toggles it)
kspp:	.res	1			; SPACE last field
kprv2:	.res	1			; the cursor keys last field
kpend:	.res	1			; cursor key steps not yet taken
kprev:	.res	1			; KEYS last field (the schedule keys)
sched:	.res	1			; the lead-in schedule: 0 the FPGA ULA's, 8 the real ULA's

; ---- scratch, and the pattern's values for a cell ----
tmp:	.res	2
tmp2:	.res	1
ra:	.res	2			; addrow's column offset, rowaddr's result low byte
yt:	.res	1			; addrow's row (low, high)
yt_hi:	.res	1
byr:	.res	1			; the block row (a pattern hash term)
gm:	.res	1			; line 7's mask: 0 on a block's bottom (grid) line
permbx:	.res	1			; PERM of the entering column's block
pmask:	.res	1			; $77 on a block's first column (its black pixel), else $FF
fdn:	.res	1			; (init: rows left to draw)

; ---- the vertical step (notch.s) ----
vcnt:	.res	1			; 2-line steps left this field
grow:	.res	2			; the row being drawn (0..319); also colop's
gcls:	.res	1			; its class (0..3)
gkind:	.res	1			; 0: drawn as the row above the window, 1: as the row below
gb:	.res	2			; the current block (map column / 4)
grel:	.res	1			; the current cell's column relative to the span, + 3
gzlo:	.res	1			; the span's pattern columns: grel in gzlo..gzhi-1
gzhi:	.res	1
gplo:	.res	1			; a whole block of pattern: gplo <= grel < gphi
gphi:	.res	1
gz0:	.res	1			; a whole block of zeros: gz0 <= grel < gz1
gz1:	.res	1
gsw:	.res	1			; the fast block's cell after which the plain values apply
gbc:	.res	1			; blocks left
gcc:	.res	1			; cells left in the block (slow path)
ve:	.res	1			; the block's even- and odd-line bytes ...
vo:	.res	1
vem:	.res	1			; ... and with its left pixel black
vom:	.res	1

; ---- the cell writers (putc, PUTCC, PUTCM) ----
plo:	.res	1			; the cell's address
phi:	.res	1
pve:	.res	1			; lines 0, 2, 4, 6
pvo:	.res	1			; lines 1, 3, 5
pv7:	.res	1			; line 7

; ---- a column step's edge rows (colop.s) ----
cdir:	.res	1			; the direction: 1 right, $FF left
cdx:	.res	1			; (0 right, 1 left)
cen:	.res	1			; 0: every store to the dummy
ctb:	.res	1			; 1: rows top and bot whole; 0: their hidden lines only
ctbe:	.res	1			; (cen for those rows)
sxin:	.res	2			; the entering column
sxout:	.res	2			; the leaving column
xin8:	.res	2			; 8 x each
xout8:	.res	2
pin:	.res	2			; the current row's entering and leaving cells
pout:	.res	2
crow:	.res	1			; the row (0..4) of the five
crun2:	.res	1			; the lower run's first row
cskip:	.res	1			; the row with no entering cell
ctop:	.res	1			; rows top and bot (line-masked)
cbot:	.res	1
mtop:	.res	1			; their MLINE offsets
mbot:	.res	1
mrow:	.res	1			; (the current one)
msel:	.res	2			; PUTCM's page choice: the dummy's or the cell's
ceu:	.res	1			; the entering cell is due in the row above / below
ced:	.res	1
cin:	.res	5			; per row: store the entering cell
clvt:	.res	5			; per row: store the leaving cell
	NOCROSS	msel, 2
	NOCROSS	cin, 5
	NOCROSS	clvt, 5
