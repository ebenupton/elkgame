; display.s -- the next field's display parameters, from wx and wy (docs/DESIGN.md
; sections 2 and 4), and the ring-address helpers.  Fixed length.
;
; Horizontally: t = (WIN_C - wx) & 7 characters of lead-in, and a screen start at the
; 64-byte-aligned column cb = wx - WIN_C + t, so that the window's first pixel is map
; column wx.  Vertically: f = ((Y0 - wy) & 7) / 2 rows of 10-line text mode (MODE 6,
; MODE 3 on lines 0 and 1) at the top push the rows below down by 2f lines.  There are
; always three rows above the window's first (f band rows and 3 - f MODE 4 rows: 10f +
; 8 (3 - f) + (wy & 7) = Y0), each 320 bytes (40 columns), so the screen start is the
; window's first row less 960.
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
	; f = ((Y0 - wy) & 7) >> 1: the modes of lines 0 and 1, the rest of the band, and
	; lines 9 and 19 (the band's end, or no change)
	lda	#Y0
	sec
	sbc	wy
	and	#7
	lsr	a
	tax
	lda	TOPMODE,x
	sta	topmode
	lda	TOP2,x
	sta	ftop+1
	lda	W9TAB,x
	sta	fw9+1
	lda	W19TAB,x
	sta	fw19+1
	; the window's first row: wy >> 3
	lda	wy+1
	sta	tmp+1
	lda	wy
	lsr	tmp+1
	ror	a
	lsr	tmp+1
	ror	a
	lsr	tmp+1
	ror	a
	sta	tmp			; low; tmp+1 = high (0 or 1)
	jsr	rowaddr			; A:Y = &3000 + (576 row + cb8) mod &5000 (Y high)
	; the screen start = that - 960 (>= &2C40: no wrap, and above &0800)
	sec
	sbc	#<960
	sta	tmp
	tya
	sbc	#>960
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
	lda	VSP_BY_X,x
	sta	VVECP
	lda	VSPH_BY_X,x
	sta	VVECP+1
	lda	VS2_BY_X,x		; the window's variant (its set shares VX's page)
	sta	VJ
	lda	#>VX
	sta	VJ+1
	lda	VA_BY_X,x		; the blip in the window
	sta	vav
	lda	VC_BY_X,x		; the lead-in mode (the palette line's sty, the gadgets)
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
; ra < &5000.  Both paths take the same time, with no main-RAM (stack) access: a 1 MHz
; access's length depends on its cycle's phase, which would differ between the paths.
addrow:
	ldy	yt
	lda	yt_hi
	bne	@hi
	lda	R576L,y
	clc
	adc	ra
	sta	art
	lda	R576H,y
	jmp	@s
@hi:	nop				; (balances the jmp)
	lda	R576LT,y
	clc
	adc	ra
	sta	art
	lda	R576HT,y
@s:	adc	ra+1
	tay
	lda	RINGHI,y
	tay
	lda	art
	rts

