; colop.s -- a column step's edge rows (docs/DESIGN.md, "The edge rows").
;
; Timing: fixed length for a given direction (cdir) and kind (ctb): the time does not
; depend on which cells are due or wanted.  frame.s calls it in the fixed-length work
; below the window, after nstore: for a commit (ctb = 1), in the bottom of the field
; before the one that shows it; for the behind field of a 2-column step (ctb = 0), in
; the bottom of the field before the behind strip.  The two directions, and the two
; kinds, differ in length; frame.s pads each of its paths (CAL_CP, CAL_CM, CAL_BP,
; CAL_BEH).  An unwanted cell's stores go to the dummy page (SELP), and in rows top and
; bot an unwanted line's store likewise (PUTCM, by the line mask MLINE).
;
; The strip (strip.s) stores the entering and leaving columns on the window's lines;
; colop writes, as whole characters, what the strip cannot be relied on for:
;   - row top (the row of line Y0, which has no iteration before it) and row bot (the
;     row of the last window line, whose lines below the window no iteration stores):
;     every line for a commit; for the behind field only their hidden lines -- top's
;     above the window, bot's below it -- because the shown ones would show the column
;     a field early (the strip stores them behind the beam);
;   - the look-ahead rows, just above and below the window, which a vertical step brings
;     into view: a cell there is entered or zeroed only if its notch class is due
;     (notch.s), and the gap cells beyond them, as the next row's, likewise.
;
; In: cdir (1 right, $FF left), cen (ANDed into every row's flag, cin and clvt; rows
; top and bot use only their line mask, so cen = 0 would not stop their stores: frame.s
; always sets cen = 1), ctb (1: rows top and bot whole; 0: their hidden lines only), mx,
; wy.  Out: sxin, sxout (the entering and
; leaving columns), pmask and permbx, for build.  Five rows, by the scanline they hold:
; going right wy-8, wy, wy+169, wy+177, wy+185 (top-1, top, bot, bot+1, bot+2); going
; left wy-16, wy-8, wy, wy+169, wy+177 (top-2 .. bot+1).  Due is the notch rule: below,
; class <= k; above, class <= 3 - k; k = (wy & 7) / 2.  The stores:
;   enter (pattern at sxin): top, bot; top-1 if sxin's class is due above, bot+1 if due
;                            below
;   leave (zero at sxout):   top, bot; right: bot+1, top-1 if due above, bot+2 if the
;                            cell's class as the row below's gap cell (sxout + 72: class
;                            ^ 2) is due below; left: top-1, bot+1 if due below, top-2
;                            if (sxout - 72)'s class (^ 2) is due above
	.segment "CODE"
colop:	lda	cen			; ctbe: rows top and bot's flag in cin and clvt
	sta	ctbe
	; the line masks (MLINE offsets) of rows top and bot: every line (64) for a commit,
	; or for the behind field only the hidden ones, top's above the window and bot's
	; below it (the strip stores the shown ones behind the beam)
	lda	#64
	ldx	ctb
	bne	:+
	lda	wy
	and	#6
	asl	a
	asl	a			; 8 * (wy & 7)/2: the lines < wy & 7 (wy is even)
	jmp	:++
:	nop				; (pad for ctb = 1)
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
	adc	#32			; the lines > (wy + 169) & 7 = (wy & 7) + 1
	jmp	:++
:	nop				; (pad for ctb = 1)
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
	jmp	co_en			; then co_go and the rows
; ---- co_cols: from cdir and mx, the entering and leaving columns (sxin, sxout: right
; mx + WIN_W and mx, left mx - 1 and mx + WIN_W - 1, mod 2560), 8 x each (xin8, xout8),
; and the entering column's hash term (permbx) and mask (pmask) ----
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
	; 8 x each: their byte offsets in a ring row
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
	lda	sxin+1			; permbx: PERM of the block, sxin >> 2 (its low byte)
	sta	tmp2
	lda	sxin
	lsr	tmp2
	ror	a
	lsr	tmp2
	ror	a
	tax
	lda	PERM,x
	sta	permbx
	lda	sxin			; pmask: a block's first column has its left pixel black
	and	#3
	tax
	lda	PMASK,x
	sta	pmask
	rts
; ---- co_en: which cells are due.  LE[4 * class + k] = (class <= k): below the window
; with k = kd = (wy & 7) / 2, above with k = ku = 3 - kd.  Fills cin and clvt, one flag
; a row (0: the store goes to the dummy page) ----
co_en:
	lda	wy
	and	#7
	lsr	a
	sta	tmp			; kd, the phase below
	eor	#3
	sta	tmp+1			; ku, the phase above
	lda	sxin
	and	#$0C			; 4 * class: class = (column >> 2) & 3
	sta	tmp2
	ora	tmp+1
	tay
	lda	LE,y
	and	cen
	sta	ceu			; the entering cell due above
	lda	tmp2
	ora	tmp
	tay
	lda	LE,y
	and	cen
	sta	ced			; and below
	lda	sxout
	and	#$0C
	sta	tmp2			; (the leaving cell's 4 * class)
	ldx	cdx
	bne	co_left
	ora	tmp+1
	tay
	lda	LE,y
	and	cen
	sta	clvt			; right: leave top-1 if due above
	lda	tmp2
	eor	#8
	ora	tmp
	tay
	lda	LE,y
	and	cen
	sta	clvt+4			; leave bot+2 if (class ^ 2) is due below
	lda	ceu			; enter: top-1, top, bot, bot+1; never bot+2
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
	sta	clvt			; left: leave top-2 if (class ^ 2) is due above
	lda	tmp2
	ora	tmp
	tay
	lda	LE,y
	and	cen
	sta	clvt+4			; leave bot+1 if due below
	lda	ceu			; enter: never top-2; top-1, top, bot, bot+1
	sta	cin+1
	lda	ced
	sta	cin+4
	lda	#0
	sta	cin
	lda	ctbe
	sta	cin+2
	sta	cin+3
	nop				; (pads left to right's length)
	nop
	nop
co_go:	; leave, in the three middle rows: right top, bot (cen) and bot+1 (always); left
	; top-1 (always), top and bot.  Both paths 17 cycles.
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
	nop				; (balances the jmp)
:
	; two runs of rows, each stepped +576 from its first: the upper from crow 0 (top-1
	; going right, top-2 going left) up to crun2, and the lower from crow crun2 (bot)
	; to 4.  Rows top and bot are not adjacent, so each run starts with co_first.
	ldx	cdx
	lda	CRUN2,x
	sta	crun2
	lda	CSKIP,x
	sta	cskip
	lda	CTOP,x
	sta	ctop
	lda	CRUN2,x			; (row bot is the lower run's first)
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

; ---- co_inc: the next row of a run: pin, pout +576, back into the ring; grow + 1, mod
; 320.  (The mod-320 test's time depends on grow: when a run crosses grow 256 or 320.)
co_inc:	lda	pin
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

; ---- co_do: one row (crow): the entering cell (none in row cskip: bot+2 going right,
; top-2 going left), then the leaving one.  Rows top and bot (ctop, cbot) go through the
; line mask (co_dom, PUTCM); the others are whole cells, or the dummy page (co_dop,
; PUTCC).  Each row's path is fixed by the direction. ----
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
:	lda	pin			; the entering cell: the pattern of block row grow >> 1
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
	lda	grow			; an odd row's line 7 is the block's black grid line
	and	#1
	beq	:+
	lda	#0
	sta	pv7
	jmp	:++
:	nop				; (both paths 11 cycles)
	nop
	nop
	nop
:	PUTCM	me
co_lvm:	ldx	crow			; the leaving cell: zero, through the line mask
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
:	lda	pin			; the entering cell, or the dummy if not wanted (cin)
	ldy	pin+1
	SELP	cin
	lda	grow+1			; the pattern of block row grow >> 1
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
	lda	grow			; an odd row's line 7 is the block's black grid line
	and	#1
	beq	:+
	lda	#0
	sta	pv7
	jmp	:++
:	nop				; (both paths 11 cycles)
	nop
	nop
	nop
:	PUTCC	ce
co_lvp:	ldx	crow			; the leaving cell: zero, or the dummy (clvt)
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

; ---- co_first: pin, pout, grow (and yt) <- the cells of sxin and sxout in the row of
; scanline wy + COFF[X] (mod 2560) ----
co_first:
	lda	wy
	clc
	adc	COFFL,x
	sta	tmp
	lda	wy+1
	adc	COFFH,x
	tay
	lda	MOD2560H,y
	lsr	a			; the row: scanline >> 3
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

