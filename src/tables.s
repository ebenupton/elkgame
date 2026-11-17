; ---------------------------------------------------------------------------------
	.segment "TABLES"
	.include "gen_tables.s"

	.segment "TABLES2"
	.align	256
; f -> lines from the lock to the first iteration, the first line's phase, top mode
BAND_N:	.byte	1, 8, 18, 28	; lines counted before the first iteration's line
N1TAB:	.byte	27, 20, 10, 0	; iterations above the palette line's: lines 2.., 9.., 19.. to 28
TOPMODE: .byte	M1, M3, M3, M3
F10M:	.byte	<(0-Y0+2560), <(10-Y0+2560), <(20-Y0+2560), <(30-Y0+2560)
F10MH:	.byte	>(0-Y0+2560), >(10-Y0+2560), >(20-Y0+2560), >(30-Y0+2560)
F10:	.byte	0, 10, 20, 30
F640L:	.byte	<0, <640, <1280, <1920
F640H:	.byte	>0, >640, >1280, >1920
; RTC samples set among lines 97..102 -> the field (FF: lost), the lock correction in
; half lines (fewer than expected: early; more: late)
; (RTC samples set + F) -> correction in half lines: 4 is a good lock; fewer means
; the loop ran early (count later), more late
	.ifdef	CAL_NOADJ
LOCKADJ: .byte	0, 0, 0, 0, 0, 0, 0, 0
	.else
LOCKADJ: .byte	1, 1, 1, 1, 0, $FE, $FC, $FA
	.endif
; keys: bit 0 left, 1 right, 2 up, 3 down
KDX:	.repeat	16, k
	.byte	<(((k >> 1) & 1) - (k & 1))	; keys: 2 columns a commit
	.endrep
KDY:	.repeat	16, k
	.byte	<(((k >> 3) & 1) - ((k >> 2) & 1))
	.endrep
; newly pressed keys (bits 4, 5) -> sched step
SCHKEEP:	.repeat	64, k
	.byte	<(((k >> 4) & 3) = 0) * $FF
	.endrep
SCHSET:	.repeat	64, k
	.if	(k >> 5) & 1
	.byte	8
	.elseif	(k >> 4) & 1
	.byte	0
	.else
	.byte	0
	.endif
	.endrep
KANY:	.byte	0
	.repeat	15
	.byte	$FF
	.endrep
; by direction (0 right, 1 left): the entering and leaving columns from mx
XINL:	.byte	<WIN_W, <(2560-1)
XINH:	.byte	>WIN_W, >(2560-1)
XOUTL:	.byte	0, <(WIN_W-1)
XOUTH:	.byte	0, >(WIN_W-1)
; the edge rows' scanlines from wy (+2560 where negative), five a direction
COFFI:	.byte	0, 5
COFFL:	.byte	<(2560-8), 0, <(H-1), <(H+7), <(H+15)
	.byte	<(2560-16), <(2560-8), 0, <(H-1), <(H+7)
COFFH:	.byte	>(2560-8), 0, >(H-1), >(H+7), >(H+15)
	.byte	>(2560-16), >(2560-8), 0, >(H-1), >(H+7)
; by direction: the lower run's first offset, and its first row's number
COFFD:	.byte	2, 8
CRUN2:	.byte	2, 3
CSKIP:	.byte	4, 0
CTOP:	.byte	1, 2
; line masks, 8 bytes each: lines < 0, 2, 4, 6; lines > 1, 3, 5, 7; every line
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
; cnext2 + 2 -> the behind column's direction (a 2-column step), or 0
BEH:	.byte	0, 0, 1		; (indexed from cnext2 = $FE: -2, -1, 0, 1, 2)
	.res	251
	.byte	$FF, 0
; column & 3 -> the block's left pixel column black
PMASK:	.byte	$77, $FF, $FF, $FF
; the random trajectory's choices
RDX:	.byte	0, 1, $FF, 2, $FE, 2, $FE, 1
RDY:	.byte	0, 2, $FE, 2, $FE, 0, 2, $FE
RGAP:	.byte	2, 2, 2, 3, 3, 4, 5, 7
RVD:	.byte	1, 1, 2, 3
DGX:	.byte	2, 2, $FE, $FE
DGY:	.byte	2, $FE, $FE, 2

