; display.s -- the next field's display parameters, from wx and wy (docs/DESIGN.md
; sections 2 and 4), and the ring-address helpers.  Fixed length.
;
; Horizontally: t = (WIN_C - wx) & 7 characters of lead-in, and a screen start at the
; 64-byte-aligned column cb = wx - WIN_C + t, so that the window's first pixel is map
; column wx.  Vertically: f = ((Y0 - wy) & 7) / 2 rows of 10-line text mode (MODE 3)
; above the window push the first MODE 1 row down by 2f lines; the screen start is
; then the row of map scanline wy + 10f - Y0, less the 640 f bytes the text rows fetch.
	.segment "CODE"
setup_frame:
	; t = (WIN_C - wx) & 7: the lead-in
	lda	wx
	and	#7
	tax
	lda	T_BY_X,x
	sta	tv
	; cb = wx - WIN_C + t (mod 2560); cb8 = 8 cb
	lda	wx
	sec
	sbc	#WIN_C
	sta	cb8
	lda	wx+1
	sbc	#0
	sta	cb8+1
	lda	cb8
	clc
	adc	tv
	sta	cb8
	lda	cb8+1
	adc	#0
	tax
	lda	MAPHI,x
	sta	cb8+1
	asl	cb8
	rol	cb8+1
	asl	cb8
	rol	cb8+1
	asl	cb8
	rol	cb8+1
	; f = ((Y0 - wy) & 7) >> 1
	lda	#Y0
	sec
	sbc	wy
	and	#7
	lsr	a
	tax
	lda	BAND_N,x
	sta	band_n
	lda	N1TAB,x
	sta	n1
	lda	TOPMODE,x
	sta	topmode
	; y0 = ((wy + 10f - Y0) mod 2560) >> 3
	lda	wy
	clc
	adc	F10M,x			; 10f - Y0 + 2560, low byte
	sta	tmp
	lda	wy+1
	adc	F10MH,x
	tay
	lda	MOD2560H,y		; hi byte mod &0A
	sta	tmp+1
	lda	tmp			; >> 3
	lsr	tmp+1
	ror	a
	lsr	tmp+1
	ror	a
	lsr	tmp+1
	ror	a
	sta	tmp			; y0 low; tmp+1 = y0 high (0 or 1)
	jsr	rowaddr			; A:Y = &3000 + (576 y0 + cb8) mod &5000 (Y high)
	; the screen start = that - 640 f (the text rows fetch 640 bytes each)
	sec
	sbc	F640L,x
	sta	tmp
	tya
	sbc	F640H,x
	sta	tmp+1
	; &FE02 = (S >> 1) & &E0, &FE03 = (S >> 9) & &3F
	lsr	a
	sta	fe03v
	lda	tmp
	ror	a
	and	#$E0
	sta	fe02v
	; the lead-in: the variants of the loop's three parts and the two mode values, by
	; (wx & 7) | sched (0: the FPGA ULA's schedule, 8: the real ULA's)
	lda	wx
	and	#7
	ora	sched
	tax
	lda	VS1_BY_X,x
	sta	VVEC1
	lda	VS1H_BY_X,x
	sta	VVEC1+1
	lda	VSP_BY_X,x
	sta	VVECP
	lda	VSPH_BY_X,x
	sta	VVECP+1
	lda	VS2_BY_X,x		; the window's variant (its set shares VX's page)
	sta	VJ
	lda	#>VX
	sta	VJ+1
	lda	VA_BY_X,x		; the blip
	sta	va1+1
	sta	vap+1
	sta	vav
	lda	VC_BY_X,x		; the lead-in mode
	sta	vcv
	sta	vcA+1
	sta	vcB+1
	rts

; ---- rowaddr: A:Y <- &3000 + (576 * row + cb8) mod &5000 (Y high, ra low), row in
; tmp (low), tmp+1 (0 or 1).  Keeps X.  Both paths take the same time.
rowaddr:
	ldy	tmp
	lda	tmp+1
	bne	@hi
	lda	R576L,y
	clc
	adc	cb8
	sta	ra
	lda	R576H,y
	jmp	@sum
@hi:	nop				; (balances the jmp)
	lda	R576LT,y
	clc
	adc	cb8
	sta	ra
	lda	R576HT,y
@sum:	adc	cb8+1
	tay
	lda	RINGHI,y
	tay
	lda	ra
	rts

; ---- ula_apply: the screen start and line 0's mode, for the next field ---------------
ula_apply:
	lda	fe02v
	sta	ULA_SA_L
	lda	fe03v
	sta	ULA_SA_H
	lda	topmode
	sta	ULA_MODE
	rts

; ---- addrow: A:Y <- &3000 + (576 yt + ra) mod &5000 (Y high), yt 0..319 (yt, yt_hi),
; ra < &5000.  Both paths take the same time.
addrow:
	ldy	yt
	lda	yt_hi
	bne	@hi
	lda	R576L,y
	clc
	adc	ra
	pha
	lda	R576H,y
	jmp	@s
@hi:	nop				; (balances the jmp)
	lda	R576LT,y
	clc
	adc	ra
	pha
	lda	R576HT,y
@s:	adc	ra+1
	tay
	lda	RINGHI,y
	tay
	pla
	rts

