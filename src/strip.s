; strip.s -- building the beam-raced strip for the next field (docs/DESIGN.md 5.1).
; Fixed length.
;
; A coarse step's entering column is written into the ring during the field that first
; shows it (or, for a 2-column step's first column, the field before), one byte and
; one zero per window line, in the line's horizontal blanking, by the snippets the
; scanline loop jumps through (gen_snips.s).  One snippet serves a character row: its
; two stores are indexed by X, the line within the row, so the builder patches four
; operand bytes and fills eight data bytes a row, not five bytes a line.
;
; smode 0 (idle): every snippet stores to the dummy page, in the same time.  Otherwise
; snippet p is row (top & ~1) + p: its first store's address is that row's cell in
; column sxin and its bytes (VBUF) the pattern's there; its second store's address is
; the cell in column sxout (it stores zero).  Ahead of the beam (smode 1) iteration y
; stores line y+1's bytes; behind it (smode 2), line y's.  The last snippet is never
; built (only the exit iteration reaches it, ahead of the beam, where it is not needed).
	.segment "CODE"
build:	lda	smode
	beq	:+
	jmp	b_real
:
	lda	#<DUMMY
	.repeat	NSNIP-1, p
	sta	.ident(.sprintf("SN%dA1", p))+1
	sta	.ident(.sprintf("SN%dA2", p))+1
	.endrep
	lda	#>DUMMY
	.repeat	NSNIP-1, p
	sta	.ident(.sprintf("SN%dA1", p))+2
	sta	.ident(.sprintf("SN%dA2", p))+2
	.endrep
	LDELAY	CAL_BI1
	LDELAY	CAL_BI2
	LDELAY	CAL_BI3
	jmp	bfin
b_real:	lda	wy			; from the even row at or above the top row
	and	#$F0
	sta	tmp
	lda	wy+1
	sta	tmp+1
	jsr	row_of_tmp
	lda	grow
	sta	yt
	lda	grow+1
	sta	yt_hi
	lda	sxin
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
	sta	SN0A1+1
	sty	SN0A1+2
	lda	sxout
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
	sta	SN0A2+1
	sty	SN0A2+2
	lda	sxin+1
	sta	tmp2
	lda	sxin
	lsr	tmp2
	ror	a
	lsr	tmp2
	ror	a
	tax
	lda	PERM,x
	sta	permbx
	lda	sxin
	and	#3
	tax
	lda	PMASK,x
	sta	pmask
	lda	grow+1
	lsr	a
	lda	grow
	ror	a
	sta	byr
	.repeat	NSNIP-1, q
	.if	q > 0			; the row below: +576, back into the ring
	lda	.ident(.sprintf("SN%dA1", q-1))+1
	clc
	adc	#$40
	sta	.ident(.sprintf("SN%dA1", q))+1
	lda	.ident(.sprintf("SN%dA1", q-1))+2
	adc	#$02
	tax
	lda	WRAPHI,x
	sta	.ident(.sprintf("SN%dA1", q))+2
	lda	.ident(.sprintf("SN%dA2", q-1))+1
	clc
	adc	#$40
	sta	.ident(.sprintf("SN%dA2", q))+1
	lda	.ident(.sprintf("SN%dA2", q-1))+2
	adc	#$02
	tax
	lda	WRAPHI,x
	sta	.ident(.sprintf("SN%dA2", q))+2
	.endif
	.if	(q & 1) = 0		; a pair of rows is one colour row
	.if	q > 0
	ldx	byr
	lda	MOD160+1,x
	sta	byr
	.else
	lda	byr
	.endif
	clc
	adc	permbx
	tay
	.endif
	lda	PE,y
	and	pmask
	sta	VBUF+8*q
	sta	VBUF+8*q+2
	sta	VBUF+8*q+4
	sta	VBUF+8*q+6
	lda	PO,y
	and	pmask
	sta	VBUF+8*q+1
	sta	VBUF+8*q+3
	sta	VBUF+8*q+5
	.if	(q & 1) = 1		; the odd row's line 7 is the grid's
	lda	#0
	.endif
	sta	VBUF+8*q+7
	.endrep
bfin:	lda	wy			; the top row's snippet: 0 or 1
	and	#8
	asl	a
	asl	a			; SNSTR * (top & 1)
	clc
	adc	#<SN0
	sta	sptr
	lda	#>SN0
	sta	sptr+1
	lda	#Y1-1-Y0
	sta	lcnt
	rts

