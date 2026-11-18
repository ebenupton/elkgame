; strip.s -- setting up the beam-raced strip for this field's window (docs/DESIGN.md
; 5.1).  Fixed length; run above the window (raster.s), in the free time after the lock.
;
; A coarse step's entering column is written into the ring during the field that first
; shows it (or, for a 2-column step's first column, the field before), one byte and
; one zero per window line, in the line's horizontal blanking, by loop 2's gadgets
; (gen_loop2.s): gA for even map rows, gB for odd, each beginning
;     sta cell_in / lda #0 / sta cell_out
; Their line blocks step the two addresses down the cells and prepare the other gadget
; for the next row, so all that is left to do here is the first two rows and the
; per-field state:
;   - the first window row's gadget (P0: A or B by the row's parity) at line k0 of its
;     cells, the other gadget at line 0 of the next row's;
;   - the pattern bytes of the first colour pair (VE, VO) and the next (VEN, VON, VNX),
;     the pair's block row (bq);
;   - the entry (the tail that loads the first window line), VRET (the first block);
;   - the exit: which block turns into the exit, and after how many rows (rows).
;
; smode 0 (idle): both cells of every row are one gap cell (column mx + WIN_W + 7, which
; is always zero), and the pattern bytes are zero (pmask = 0): the stores change
; nothing, in the same time.  Otherwise cell_in is in column sxin, with the pattern's
; bytes, and cell_out in column sxout, with zero.  Ahead of the beam (smode 1) the line
; after each window line is stored; behind it (smode 2), the line itself (k0, frame.s).

	.segment "CODE"
build:	lda	smode			; the columns and the mask (equal paths)
	bne	bld_real
	lda	mx			; idle: a gap column, both cells
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
	lda	#0
	sta	pmask
	jmp	bld_cols
bld_real:	lda	sxin			; the mask: the block's left pixel black
	and	#3
	tax
	lda	PMASK,x
	sta	pmask
	DELAY	BLD_IDLE
bld_cols:	lda	sxin+1			; the hash's block term
	sta	tmp2
	lda	sxin
	lsr	tmp2
	ror	a
	lsr	tmp2
	ror	a
	tax
	lda	PERM,x
	sta	permbx
	; the first window row: grow = wy >> 3; its parity picks the gadget
	lda	wy
	sta	tmp
	lda	wy+1
	sta	tmp+1
	jsr	row_of_tmp
	lda	grow
	sta	yt
	lda	grow+1
	sta	yt_hi
	lda	sxin			; that row's entering cell ...
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
	lda	sxout			; ... and leaving cell
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
	; the gadgets: P0's at line k0 of row grow's cells, the other's at line 0 of the
	; next row's (+576, wrapped).  X = 0 (A first) or 8 (B first): offsets in GOFS.
	lda	grow
	and	#1
	asl	a
	asl	a
	asl	a
	tax				; X = 8 * parity
	lda	cin0
	ora	k0
	ldy	GOFS,x			; P0's entering low byte
	sta	gA+1,y
	lda	cin0+1
	sta	gA+2,y
	lda	cout0
	ora	k0
	sta	gA+6,y
	lda	cout0+1
	sta	gA+7,y
	ldy	GOFS+1,x		; the other gadget: the next row
	lda	cin0
	clc
	adc	#<576
	sta	gA+1,y
	lda	cin0+1
	adc	#>576
	stx	tmp2
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
	; the colour pairs: this one (block row grow >> 1) and the next
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
	; ... except that an A row entered at line 0 or 1 copies VEN (and at line 0 VON)
	; into VE (VO) itself (blocks bA1, bA0): then they must hold this pair's
	lda	k0
	ora	tmp2			; (8 * parity): 0 or 1 only for an A row at line 0 or 1
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
	; ... and a B row entered at line 7 skips bB6, which advances bq: advance it here
	lda	k0
	ora	tmp2
	tay
	lda	bq
	clc
	adc	BQADD,y
	tay
	lda	MOD160,y
	sta	bq
	; the entry and the first block: index 8 * parity + k0 into the block tables
	lda	tmp2
	ora	k0
	tay
	lda	BLKL,y			; VRET: the block after the first window line
	sta	VRET
	lda	BLKH,y
	sta	VRET+1
	dey				; the tail before it loads the first line: block
	tya				;   (index - 1) mod 16
	and	#15
	tay
	lda	TAILL,y
	sta	wtP+1
	lda	TAILH,y
	sta	wtP+2
	; the exit.  The last window line is line k0 + 169 counted from the first row's
	; line 0; the block before it is at k0 + 168: row (k0 + 168) >> 3 of the window,
	; line (k0 + 168) & 7.  The line-7 block ending the row before arms it.
	ldy	hkprev			; first, last field's hook back to normal
	lda	HKAL,y
	sta	@r1+1
	lda	HKAH,y
	sta	@r1+2
	lda	HKBL,y
	sta	@r2+1
	lda	HKBH,y
	sta	@r2+2
	lda	HKNXT,y
@r1:	sta	$FFFF			; the hook's immediate: the next block's low byte
	lda	#<VRET
@r2:	sta	$FFFF			; the hook's store: back to VRET
	lda	k0
	clc
	adc	#Y1-Y0-2
	pha
	lsr	a
	lsr	a
	lsr	a
	sta	rows			; line-7 blocks before the arming one: the row number
	clc
	adc	grow			; the parity of that row ...
	and	#1
	asl	a
	asl	a
	asl	a
	sta	tmp
	pla
	and	#7			; ... and the line
	ora	tmp
	tay
	sty	hkprev
	lda	HKAL,y			; both line-7 blocks' arming stores point at its hook
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
	rts

; by 8 * parity (0: an even first row, gadget A first; 8: odd, B first)
	.segment "TABLES4"
GOFS:	.byte	0, gB-gA, 0, 0, 0, 0, 0, 0
	.byte	gB-gA, 0
; by k0 | 8 * parity: keep the computed next pair (FF) or take this pair (00)
KEEPE:	.byte	0, 0, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
TAKEE:	.byte	$FF, $FF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
KEEPO:	.byte	0, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
TAKEO:	.byte	$FF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
BQADD:	.byte	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
	NOCROSS	GOFS, BQADD+16-GOFS
