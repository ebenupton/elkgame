; tables.s -- the tables: tools/gen.py's (segment TABLES), then the hand-written ones.
;
; A table indexed in the fixed-length work must not straddle a page over the range of
; its index, or the access costs a cycle more for some indexes and the "fixed" work is
; not fixed: NOCROSS asserts it for each (and gen.py for its own).  The page-aligned
; tables come first.

	.segment "TABLES"
	.include "gen_tables.s"

	.segment "TABLES2"
	.align	256
; cnext2 (a signed column count) -> the direction of a 2-column step's behind field
; (1 right, $FF left), or 0: a whole page, so that a negative index cannot cross one
BEH:	.repeat	256, k
	.byte	<((k = $FE) * $FF + (k = 2))
	.endrep

; Line masks for the edge rows' partial cells (PUTCM), 8 bytes each: lines < 0, 2, 4,
; 6; lines > 1, 3, 5, 7; every line.  Indexed by mrow + line (0..71).
MLINE:	.repeat	4, m
	.repeat	8, i
	.byte	i < 2*m
	.endrep
	.endrep
	.repeat	4, m
	.repeat	8, i
	.byte	i > 2*m+1
	.endrep
	.endrep
	.byte	1, 1, 1, 1, 1, 1, 1, 1
	NOCROSS	MLINE, 72

; ---- the next field's band (setup_frame), by f = ((Y0 - wy) & 7) / 2: the number of
; text rows above the window ----
BAND_N:	.byte	1, 8, 18, 28		; lines from line 0 to the first iteration's
N1TAB:	.byte	27, 20, 10, 0		; iterations of loop 1 (lines above the palette line's)
TOPMODE: .byte	M1, M3, M3, M3		; the mode of line 0 (a 20K mode: the lock reads stall)
F10M:	.byte	<(0-Y0+2560), <(10-Y0+2560), <(20-Y0+2560), <(30-Y0+2560)	; 10 f - Y0 (mod 2560)
F10MH:	.byte	>(0-Y0+2560), >(10-Y0+2560), >(20-Y0+2560), >(30-Y0+2560)
F640L:	.byte	<0, <640, <1280, <1920	; 640 f: the text rows' bytes
F640H:	.byte	>0, >640, >1280, >1920
	NOCROSS	BAND_N, 4*7

; ---- a column step's edge rows (colop), by direction (0 right, 1 left) ----
XINL:	.byte	<WIN_W, <(2560-1)	; the entering column, from mx
XINH:	.byte	>WIN_W, >(2560-1)
XOUTL:	.byte	0, <(WIN_W-1)		; the leaving column, from mx
XOUTH:	.byte	0, >(WIN_W-1)
COFFI:	.byte	0, 5			; the first of the direction's five row offsets
COFFL:	.byte	<(2560-8), 0, <(H-1), <(H+7), <(H+15)	; the rows' scanlines from wy
	.byte	<(2560-16), <(2560-8), 0, <(H-1), <(H+7)	; (+2560 where negative)
COFFH:	.byte	>(2560-8), 0, >(H-1), >(H+7), >(H+15)
	.byte	>(2560-16), >(2560-8), 0, >(H-1), >(H+7)
COFFD:	.byte	2, 8			; the lower run's first offset ...
CRUN2:	.byte	2, 3			; ... and its first row's number
CSKIP:	.byte	4, 0			; the row with no entering cell
CTOP:	.byte	1, 2			; the window's top row
PMASK:	.byte	$77, $FF, $FF, $FF	; column & 3 -> the block's left pixel column black
	NOCROSS	XINL, PMASK+4-XINL

; ---- the variable-length work (no alignment needed) ----
; keys (bits 0..3: left, right, up, down) -> one column, one 2-line step a press
KDX:	.repeat	16, k
	.byte	<(((k >> 1) & 1) - (k & 1))
	.endrep
KDY:	.repeat	16, k
	.byte	<(((k >> 3) & 1) - ((k >> 2) & 1))
	.endrep
; newly pressed keys (bit 4 comma, bit 5 full stop) -> the lead-in schedule: kept
; (neither pressed), or set to 0 (comma: the FPGA ULA's) or 8 (full stop: the real ULA's)
SCHKEEP: .repeat 64, k
	.byte	<(((k >> 4) & 3) = 0) * $FF
	.endrep
SCHSET:	.repeat	64, k
	.byte	((k >> 5) & 1) * 8
	.endrep
; the random walk's choices (logic, TRAJ = 1)
RDX:	.byte	0, 1, $FF, 2, $FE, 2, $FE, 1	; columns a commit
RDY:	.byte	0, 2, $FE, 2, $FE, 0, 2, $FE	; lines a vertical step
RGAP:	.byte	2, 2, 2, 3, 3, 4, 5, 7		; fields between commits
RVD:	.byte	1, 1, 2, 3			; fields between vertical steps
DGX:	.byte	2, 2, $FE, $FE			; a fast diagonal's direction
DGY:	.byte	2, $FE, $FE, 2
