; strip.s -- build: the per-field set-up of the beam-raced strip (docs/DESIGN.md, "A new
; column: the beam-raced strip").
;
; Timing: fixed length, 998 cycles on every path (38 of them the leak byte's, below).
; raster.s calls it at the top of the field it serves, between the mode writes on lines
; 9 and 19 (after CAL_TA, before CAL_TB), where the CPU runs uncontended in a 40-column
; mode.  Its paths are padded to the same length (BLD_IDLE), its indexed tables do not
; cross a page (NOCROSS), and every path makes the same main-RAM accesses (the stack,
; for its calls, and the store at LEAK) at the same points, so that their 1 MHz slots'
; phases, and so their lengths, are the same every field.
;
; The strip itself is stored by loop 2 (gen_loop2.s, made by tools/gen.py gen_loop2):
; in each window line's horizontal blanking a gadget -- gA for even map rows, gB for
; odd -- stores one byte of the entering column and one zero of the leaving column, by
; 'sta cell_in / lda #0 / sta cell_out' with absolute operands.  The line blocks step
; the two operands down the cells and, during each row, prepare the other gadget for
; the next row (+576, ring-wrapped) and the next colour pair's bytes.  So build sets up
; only what the loop cannot derive for itself:
;   - the first window row's gadget (A or B by the row's parity) at line k0 of that
;     row's cells, and the other gadget at line 0 of the next row's;
;   - the pattern bytes of this colour pair (VE, VO) and the next (VEN, VON, its hash
;     VNX), and the pair's block row (bq);
;   - the entry tail (wtP: the tail that loads the first gadget's byte) and VRET (the
;     block after the first window line);
;   - the exit: which block's hook becomes the exit, and how many line-7 blocks pass
;     before one arms it (rows);
;   - the leak byte: &7E07 zero, and tA6 aimed at ZB if gadget A's cell holds it.
;
; The three modes (smode, set by frame.s in the bottom of the previous field):
;   1 ahead (a commit shown this field): iteration y stores line y+1, just before it is
;     displayed; k0 = (wy & 7) + 1.  Row top's line Y0 has no iteration before it:
;     colop has written rows top and bot whole.
;   2 behind (the field before a 2-column commit, its first column): iteration y stores
;     line y, already displayed; nothing shows until the screen start moves next field.
;     k0 = wy & 7.
;   0 idle: both cells of every row are one gap cell, column mx + WIN_W + 7, and the
;     pattern bytes are zero (pmask = 0).  That cell is always zero, so the stores change
;     nothing, in the same time as the real ones.
; In the real modes cell_in is in column sxin with the pattern, cell_out in column sxout
; with zero (both left by colop).

	.segment "CODE"
build:	lda	smode			; the columns and the mask: both paths 51 cycles
	bne	bld_real
	lda	mx			; idle: one gap column, mx + WIN_W + 7, for both cells
	clc
	adc	#<(WIN_W+7)
	sta	sxin
	sta	sxout
	lda	mx+1
	adc	#>(WIN_W+7)
	tax
	lda	MOD2560H,x
	sta	sxin+1
	sta	sxout+1
	lda	#0			; and no pattern: every byte zero
	sta	pmask
	jmp	bld_cols
bld_real:	lda	sxin			; real: the mask (a block's first column has its
	and	#3			; left pixel black)
	tax
	lda	PMASK,x
	sta	pmask
	DELAY	BLD_IDLE		; (pads this path to the idle one's length)
bld_cols:	lda	sxin+1			; the hash's block term: PERM of the entering column's
	sta	tmp2			; block (sxin >> 2, its low byte)
	lda	sxin
	lsr	tmp2
	ror	a
	lsr	tmp2
	ror	a
	tax
	lda	PERM,x
	sta	permbx
	; the first window row, grow = wy >> 3: its parity picks the first gadget
	lda	wy
	sta	tmp
	lda	wy+1
	sta	tmp+1
	jsr	row_of_tmp
	lda	grow
	sta	yt
	lda	grow+1
	sta	yt_hi
	lda	sxin			; that row's entering cell (8 x sxin, plus the row) ...
	sta	ra
	lda	sxin+1
	asl	ra
	rol	a
	asl	ra
	rol	a
	asl	ra
	rol	a
	sta	ra+1
	jsr	addrow
	sta	cin0
	sty	cin0+1
	lda	sxout			; ... and its leaving cell
	sta	ra
	lda	sxout+1
	asl	ra
	rol	a
	asl	ra
	rol	a
	asl	ra
	rol	a
	sta	ra+1
	jsr	addrow
	sta	cout0
	sty	cout0+1
	; the gadgets' operands (+1, +2 the entering cell, +6, +7 the leaving one): the first
	; gadget at line k0 of row grow's cells, the other at line 0 of the next row's (+576,
	; wrapped into the ring).  GOFS by 8 * parity gives each gadget's offset from gA.
	lda	grow
	and	#1
	asl	a
	asl	a
	asl	a
	tax				; X = 8 * parity: 0 (A first) or 8 (B first)
	lda	cin0
	ora	k0
	ldy	GOFS,x			; the first gadget
	sta	gA+1,y
	lda	cin0+1
	sta	gA+2,y
	lda	cout0
	ora	k0
	sta	gA+6,y
	lda	cout0+1
	sta	gA+7,y
	ldy	GOFS+1,x		; the other gadget: the next row, line 0
	lda	cin0
	clc
	adc	#<576
	sta	gA+1,y
	lda	cin0+1
	adc	#>576
	stx	tmp2			; (tmp2 = 8 * parity from here on)
	tax
	lda	WRAPHI,x
	sta	gA+2,y
	lda	cout0
	clc
	adc	#<576
	sta	gA+6,y
	lda	cout0+1
	adc	#>576
	tax
	lda	WRAPHI,x
	sta	gA+7,y
	ldx	tmp2
	; the colour pairs: this one (block row bq = grow >> 1) and the next (VNX, the
	; next block row's hash value)
	lda	grow+1
	lsr	a
	lda	grow
	ror	a
	sta	bq
	clc
	adc	permbx
	tay
	lda	PE,y
	and	pmask
	sta	VE
	lda	PO,y
	and	pmask
	sta	VO
	ldy	bq
	lda	MOD160+1,y
	clc
	adc	permbx
	sta	VNX
	tay
	lda	PE,y
	and	pmask
	sta	VEN
	lda	PO,y
	and	pmask
	sta	VON
	; an A row starts a pair, and its blocks bA0 and bA1 copy VON to VO and VEN to VE.
	; Entered at line 0 both run, at line 1 only bA1: then VEN (and at line 0 VON) must
	; already hold this pair's bytes.  The entry tail for an A row at line 0 is tB7,
	; which loads VEN, so it gets this pair's byte too.
	lda	k0
	ora	tmp2			; k0 | 8 * parity: 0 or 1 only for an A row at line 0 or 1
	tay
	lda	VEN
	and	KEEPE,y
	sta	VEN
	lda	VE
	and	TAKEE,y
	ora	VEN
	sta	VEN
	lda	VON
	and	KEEPO,y
	sta	VON
	lda	VO
	and	TAKEO,y
	ora	VON
	sta	VON
	; a B row entered at line 7 skips bB6, which advances bq: advance it here instead
	lda	k0
	ora	tmp2
	tay
	lda	bq
	clc
	adc	BQADD,y
	tay
	lda	MOD160,y
	sta	bq
	; the entry: block index 8 * parity + k0 (BLK*, TAIL*: A0..A7, B0..B7)
	lda	tmp2
	ora	k0
	tay
	lda	BLKL,y			; VRET: the block after the first window line
	sta	VRET
	lda	BLKH,y
	sta	VRET+1
	dey				; the tail of the block before it, (index - 1) mod 16,
	tya				;   loads the first gadget's byte; the palette line
	and	#15			;   jumps to it (wtP, raster.s)
	tay
	lda	TAILL,y
	sta	wtP+1
	lda	TAILH,y
	sta	wtP+2
	; the exit.  Loop 2 runs 170 gadgets, at lines k0 .. k0 + 169 counted from the
	; first row's line 0; the last exits through VX.  So the block after the gadget at
	; k0 + 168 (Y1 - Y0 - 2) has its hook turned into 'lda #<VX / sta VJ': it is block
	; (k0 + 168) & 7 of window row (k0 + 168) >> 3, and the line-7 block that ends the
	; row before arms it, counting the rows down.
	ldy	hkprev			; first restore last field's hook: the immediate to its
	lda	HKAL,y			; successor's low byte, the store to VRET
	sta	@r1+1
	lda	HKAH,y
	sta	@r1+2
	lda	HKBL,y
	sta	@r2+1
	lda	HKBH,y
	sta	@r2+2
	lda	HKNXT,y
@r1:	sta	$FFFF			; patched: the hook's immediate
	lda	#<VRET
@r2:	sta	$FFFF			; patched: the hook's store operand
	lda	k0
	clc
	adc	#Y1-Y0-2
	pha
	lsr	a
	lsr	a
	lsr	a
	sta	rows			; the window row: line-7 blocks to count down to it
	clc
	adc	grow			; that row's map parity ...
	and	#1
	asl	a
	asl	a
	asl	a
	sta	tmp
	pla
	and	#7			; ... and the line: its block index
	ora	tmp
	tay
	sty	hkprev			; (restored next field)
	lda	HKAL,y			; both line-7 blocks' arming stores aim at its hook
	sta	armA1+1
	sta	armB1+1
	lda	HKAH,y
	sta	armA1+2
	sta	armB1+2
	lda	HKBL,y
	sta	armA2+1
	sta	armB2+1
	lda	HKBH,y
	sta	armA2+2
	sta	armB2+2
	; the leak byte (DESIGN.md, "The leak byte"): on a real ULA a write to &FE07 while
	; the ULA fetches for the display (each window line's lead-in's last write, and the
	; blip) shows RAM[&7E07] (LEAK) in its video slot, so &7E07 must be zero while the
	; window is drawn.  In the window its
	; only writer is gadget A's line-7 tail tA6 (an odd row's line 7 is 0), so when
	; gadget A's entering cell is LEAKCELL (&7E00) tA6 loads ZB (VO - 1, always 0)
	; instead of VO.  Here for the gadget A set up above (line k0 of the first row, or
	; line 0 of the second: the line bits masked off); block B5 decides the same for
	; every later A row.  C = (cell <> LEAKCELL), so A = <ZB or <VO.  38 cycles in all.
	lda	gA+1
	and	#$F8
	sta	tmp
	lda	gA+2
	eor	#>LEAKCELL
	ora	tmp
	cmp	#1
	lda	#<(VO-1)
	adc	#0
	sta	tA6+1
	lda	#0			; then the byte itself: colop, the notch and init may write
	sta	LEAK			;   it, but only below the window or at start-up
	rts

; by 8 * parity: the first gadget's offset from gA, then the other's (0: an even first
; row, A first; 8: odd, B first)
	.segment "TABLES4"
GOFS:	.byte	0, gB-gA, 0, 0, 0, 0, 0, 0
	.byte	gB-gA, 0
; by k0 | 8 * parity: keep the computed next pair ($FF) or take this pair (0); only an
; A row entered at line 0 (both) or 1 (the even-line byte) takes this pair's
KEEPE:	.byte	0, 0, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
TAKEE:	.byte	$FF, $FF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
KEEPO:	.byte	0, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
TAKEO:	.byte	$FF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
; by k0 | 8 * parity: bq's advance, 1 only for a B row entered at line 7 (bB6 skipped)
BQADD:	.byte	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
	NOCROSS	GOFS, BQADD+16-GOFS
