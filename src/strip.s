; strip.s -- building the beam-raced strip for the next field (docs/DESIGN.md 5.1).
; Fixed length.
;
; A coarse step's entering column is written into the ring during the field that first
; shows it (or, for a 2-column step's first column, the field before), one byte and
; one zero per window line, in the line's horizontal blanking, by the snippets the
; scanline loop jumps through (gen_snips.s).  One snippet serves a character row: its
; two stores are indexed by X, the line within the row, so the builder patches four
; operand bytes and fills eight data bytes (the snippet's last eight, SNpD) a row.
;
; smode 0 (idle): every snippet stores to the dummy page, in the same time.  Otherwise
; snippet p is row (top & ~1) + p: its first store's address is that row's cell in
; column sxin and its data the pattern's there; its second store's address is the
; cell in column sxout (it stores zero).  Ahead of the beam (smode 1) iteration y
; stores line y+1's bytes; behind it (smode 2), line y's.  The last snippet is left
; storing to the dummy (only the exit iteration reaches it, ahead of the beam, where
; it is not needed).
;
; The rows are built two at a time (the two rows of a block row share the pattern's
; colour), by a loop over the snippets eight to a page (X steps 2 x SNSTR), once for
; each of the three pages they occupy.

SN_A1	= SN0A1 - SN0			; offsets in a snippet: the first store,
SN_A2	= SN0A2 - SN0			; the second store,
SN_D	= SN0D - SN0			; the row's eight bytes
	.assert	SNSTR * 8 = 256, error, "build assumes eight snippets a page"
	.assert	NSNIP = 25, error, "build assumes 24 built snippets and a dummy"

; NEXTCELL cur, prev, ofs: the store at ofs in snippet cur,x <- the one in prev,x plus
; 576 (the next ring row), wrapped back into &3000-&7FFF.  Fixed time; clobbers A, Y.
	.macro	NEXTCELL cur, prev, ofs
	lda	prev+ofs+1,x
	clc
	adc	#<576
	sta	cur+ofs+1,x
	lda	prev+ofs+2,x
	adc	#>576
	tay
	lda	WRAPHI,y
	sta	cur+ofs+2,x
	.endmacro

; BPAGE base: the four row pairs whose first snippet is in the page at base (X = 0,
; 64, 128, 192): their data, and the cells of each pair's second row and the next
; pair's first.  Fixed time.
	.macro	BPAGE	base
	.local	lp, done
	ldx	#0
lp:	lda	byr			; the pair's hash value: PERM[block] + block row
	clc
	adc	permbx
	tay
	lda	PO,y			; odd lines: 1 3 5 (and 7 in the even row)
	and	pmask
	sta	base+SN_D+1,x
	sta	base+SN_D+3,x
	sta	base+SN_D+5,x
	sta	base+SN_D+7,x
	sta	base+SNSTR+SN_D+1,x
	sta	base+SNSTR+SN_D+3,x
	sta	base+SNSTR+SN_D+5,x
	lda	PE,y			; even lines: 0 2 4 6
	and	pmask
	sta	base+SN_D+0,x
	sta	base+SN_D+2,x
	sta	base+SN_D+4,x
	sta	base+SN_D+6,x
	sta	base+SNSTR+SN_D+0,x
	sta	base+SNSTR+SN_D+2,x
	sta	base+SNSTR+SN_D+4,x
	sta	base+SNSTR+SN_D+6,x
	lda	#0			; the odd row's line 7: the grid line
	sta	base+SNSTR+SN_D+7,x
	ldy	byr			; the next block row, mod 160
	lda	MOD160+1,y
	sta	byr
	NEXTCELL base+SNSTR, base, SN_A1
	NEXTCELL base+SNSTR, base, SN_A2
	NEXTCELL base+2*SNSTR, base+SNSTR, SN_A1
	NEXTCELL base+2*SNSTR, base+SNSTR, SN_A2
	txa
	clc
	adc	#2*SNSTR
	tax
	beq	done			; (fixed time: X takes the same four values every field)
	jmp	lp
done:
	.endmacro

	.segment "CODE"
build:	lda	smode
	beq	:+
	jmp	b_real
:	ldx	#0			; idle: every built snippet stores to the dummy
@idle:	lda	#<DUMMY
	.repeat	3, g
	sta	SN0+256*g+SN_A1+1,x
	sta	SN0+256*g+SN_A2+1,x
	.endrep
	lda	#>DUMMY
	.repeat	3, g
	sta	SN0+256*g+SN_A1+2,x
	sta	SN0+256*g+SN_A2+2,x
	.endrep
	txa
	clc
	adc	#SNSTR
	tax
	bne	@idle
	.assert	>@idle = >*, error, "the idle loop must not cross a page"
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
	BPAGE	SN0
	BPAGE	SN0+256
	BPAGE	SN0+512
	lda	#<DUMMY			; the last snippet: back to the dummy
	sta	SN0+24*SNSTR+SN_A1+1
	sta	SN0+24*SNSTR+SN_A2+1
	lda	#>DUMMY
	sta	SN0+24*SNSTR+SN_A1+2
	sta	SN0+24*SNSTR+SN_A2+2
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

