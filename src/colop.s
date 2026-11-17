	.segment "CODE"
; ---- a column step's edge rows (fixed length) ------------------------------------------
; In: cdir (1: right, $FF: left), cen (0: no stores), mx, wy.  Out: sxin, sxout (the
; entering and leaving columns).  Five rows: right, the rows of scanlines wy-8, wy,
; wy+169, wy+177, wy+185 (top-1, top, bot, bot+1, bot+2); left, wy-16 .. wy+177.  The
; window lines of rows top+1..bot-1 are the strip's; top and bot are done whole here.
;   enter (pattern at sxin): top, bot; top-1 and bot+1 if sxin's class is due there
;   leave (zero at sxout):   top, bot; right: bot+1, top-1 if due, bot+2 if the cell's
;                            class (as the row below's gap: sxout + 72) is due; left:
;                            top-1, bot+1 if due, top-2 if (sxout - 72)'s is due above
colop:	lda	cen
	sta	ctbe
	; rows top and bot: every line (ctb), or only the hidden ones -- top's above the
	; window, bot's below it (the behind column: the strip does the shown lines next field)
	lda	#64
	ldx	ctb
	bne	:+
	lda	wy
	and	#6
	asl	a
	asl	a			; 8 * (wy & 7)/2: lines < wy & 7
	jmp	:++
:	nop
	nop
	nop
	nop
	nop
	nop
	nop
:	sta	mtop
	lda	#64
	ldx	ctb
	bne	:+
	lda	wy
	and	#6
	asl	a
	asl	a
	clc
	adc	#32			; lines > (wy + 169) & 7 = (wy & 7) + 1
	jmp	:++
:	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
:	sta	mbot
	jsr	co_cols
	jmp	co_en
; sxin, sxout, xin8, xout8, the hash and mask of the entering column, from cdir and mx
co_cols:
	lda	cdir
	lsr	a
	and	#1
	tax				; 0 right, 1 left
	stx	cdx
	lda	mx
	clc
	adc	XINL,x
	sta	sxin
	lda	mx+1
	adc	XINH,x
	tay
	lda	MOD2560H,y
	sta	sxin+1
	lda	mx
	clc
	adc	XOUTL,x
	sta	sxout
	lda	mx+1
	adc	XOUTH,x
	tay
	lda	MOD2560H,y
	sta	sxout+1
	; 8 * column
	lda	sxin
	sta	xin8
	lda	sxin+1
	asl	xin8
	rol	a
	asl	xin8
	rol	a
	asl	xin8
	rol	a
	sta	xin8+1
	lda	sxout
	sta	xout8
	lda	sxout+1
	asl	xout8
	rol	a
	asl	xout8
	rol	a
	asl	xout8
	rol	a
	sta	xout8+1
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
	rts
co_en:	; phases and classes: 4 class + phase indexes LE
	lda	wy
	and	#7
	lsr	a
	sta	tmp			; kd
	eor	#3
	sta	tmp+1			; ku
	lda	sxin
	and	#$0C			; 4 * class
	sta	tmp2
	ora	tmp+1
	tay
	lda	LE,y
	and	cen
	sta	ceu			; enter, the row above
	lda	tmp2
	ora	tmp
	tay
	lda	LE,y
	and	cen
	sta	ced			; enter, the row below
	lda	sxout
	and	#$0C
	sta	tmp2
	ldx	cdx
	bne	co_left
	ora	tmp+1
	tay
	lda	LE,y
	and	cen
	sta	clvt			; right: top-1 if due
	lda	tmp2
	eor	#8
	ora	tmp
	tay
	lda	LE,y
	and	cen
	sta	clvt+4			; bot+2 if (class ^ 2) due below
	lda	ceu
	sta	cin
	lda	ced
	sta	cin+3
	lda	#0
	sta	cin+4
	lda	ctbe
	sta	cin+1
	sta	cin+2
	jmp	co_go
co_left:	eor	#8
	ora	tmp+1
	tay
	lda	LE,y
	and	cen
	sta	clvt			; left: top-2 if (class ^ 2) due above
	lda	tmp2
	ora	tmp
	tay
	lda	LE,y
	and	cen
	sta	clvt+4			; bot+1 if due
	lda	ceu
	sta	cin+1
	lda	ced
	sta	cin+4
	lda	#0
	sta	cin
	lda	ctbe
	sta	cin+2
	sta	cin+3
	nop
	nop
	nop
co_go:	; the leaving cell in the three middle rows: right top, bot, bot+1; left top-1, top, bot
	ldx	cdx
	lda	ctbe
	sta	clvt+2
	cpx	#0
	bne	:+
	sta	clvt+1
	lda	cen
	sta	clvt+3
	jmp	:++
:	sta	clvt+3
	lda	cen
	sta	clvt+1
	nop
:
	; two runs of rows: the upper (crow 0 ..) and the lower (from crow 2 going right,
	; 3 going left)
	ldx	cdx
	lda	CRUN2,x
	sta	crun2
	lda	CSKIP,x
	sta	cskip
	lda	CTOP,x
	sta	ctop
	lda	CRUN2,x			; (bot is the lower run's first row)
	sta	cbot
	lda	COFFI,x
	tax
	jsr	co_first
	lda	#0
	sta	crow
co_u:	jsr	co_do
	lda	crow
	cmp	crun2
	beq	:+
	jsr	co_inc
	jmp	co_u
:	ldx	cdx
	lda	COFFD,x
	tax
	jsr	co_first
co_d:	jsr	co_do
	lda	crow
	cmp	#5
	beq	:+
	jsr	co_inc
	jmp	co_d
:	rts

co_inc:	lda	pin			; the next row of a run: +576, back into the ring
	clc
	adc	#$40
	sta	pin
	lda	pin+1
	adc	#$02
	tax
	lda	WRAPHI,x
	sta	pin+1
	lda	pout
	clc
	adc	#$40
	sta	pout
	lda	pout+1
	adc	#$02
	tax
	lda	WRAPHI,x
	sta	pout+1
	inc	grow
	bne	:+
	inc	grow+1
:	lda	grow+1			; mod 320
	beq	:+
	lda	grow
	cmp	#<320
	bcc	:+
	lda	#0
	sta	grow
	sta	grow+1
:	rts

; a row: the entering cell (never wanted in row cskip), then the leaving one.  Rows
; top and bot (ctop, cbot) go through the line mask (co_dom); the others are whole.
co_do:	ldx	crow
	cpx	ctop
	bne	:+
	lda	mtop
	sta	mrow
	jmp	co_dom
:	cpx	cbot
	bne	:+
	lda	mbot
	sta	mrow
	jmp	co_dom
:	jmp	co_dop
co_dom:	ldx	crow
	cpx	cskip
	bne	:+
	jmp	co_lvm
:	lda	pin
	sta	plo
	lda	pin+1
	sta	phi
	lda	grow+1
	lsr	a
	lda	grow
	ror	a
	clc
	adc	permbx
	tax
	lda	PE,x
	and	pmask
	sta	pve
	lda	PO,x
	and	pmask
	sta	pvo
	sta	pv7
	lda	grow
	and	#1
	beq	:+
	lda	#0
	sta	pv7
	jmp	:++
:	nop
	nop
	nop
	nop
:	PUTCM	me
co_lvm:	ldx	crow
	lda	pout
	sta	plo
	lda	pout+1
	sta	phi
	lda	#0
	sta	pve
	sta	pvo
	sta	pv7
	PUTCM	ml
co_nxm:	inc	crow
	rts

co_dop:	ldx	crow
	cpx	cskip
	bne	:+
	jmp	co_lvp
:	lda	pin
	ldy	pin+1
	SELP	cin
	lda	grow+1
	lsr	a
	lda	grow
	ror	a
	clc
	adc	permbx
	tax
	lda	PE,x
	and	pmask
	sta	pve
	lda	PO,x
	and	pmask
	sta	pvo
	sta	pv7
	lda	grow
	and	#1
	beq	:+
	lda	#0
	sta	pv7
	jmp	:++
:	nop
	nop
	nop
	nop
:	PUTCC	ce
co_lvp:	ldx	crow
	lda	pout
	ldy	pout+1
	SELP	clvt
	lda	#0
	sta	pve
	sta	pvo
	sta	pv7
	PUTCC	cl
co_nxp:	inc	crow
	rts

; pin, pout, grow <- the cells of sxin, sxout in the row of scanline wy + offset X
co_first:
	lda	wy
	clc
	adc	COFFL,x
	sta	tmp
	lda	wy+1
	adc	COFFH,x
	tay
	lda	MOD2560H,y
	lsr	a			; >> 3
	ror	tmp
	lsr	a
	ror	tmp
	lsr	a
	ror	tmp
	sta	grow+1
	sta	yt_hi
	lda	tmp
	sta	grow
	sta	yt
	lda	xin8
	sta	ra
	lda	xin8+1
	sta	ra+1
	jsr	addrow
	sta	pin
	sty	pin+1
	lda	xout8
	sta	ra
	lda	xout8+1
	sta	ra+1
	jsr	addrow
	sta	pout
	sty	pout+1
	rts

