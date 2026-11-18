; init.s -- start-up: the machine, the variables, the first picture, and the
; bootstrap raster sync that finds the field and enters the frame loop.

; ---- build options (make START_WX=... etc.; docs/DESIGN.md section 8) ------------------
	.ifndef	START_WX
START_WX = 1280+3		; the map position at start: character column ...
	.endif
	.ifndef	START_WY
START_WY = 1280			; ... and scanline (even: vertical steps are 2 lines)
	.endif
	.ifndef	SEED
SEED = $ACE1			; the random walk's seed (TRAJ = 1)
	.endif
	.ifndef	TRAJ
TRAJ = 0			; 0: the demo script (gen.py SCRIPT); 1: a random walk
	.endif
	.ifndef	MOTION
MOTION = 0			; 1: moving from the start (else SPACE starts and stops it)
	.endif
	.ifndef	SCHED
SCHED = 8			; the lead-in schedule at start: 8 the real ULA's, 0 the FPGA's
	.endif
	.ifndef	DYMAX
DYMAX = 2			; lines a field, at most (one notch class a field)
	.endif
	.assert	(START_WY & 1) = 0, error, "START_WY must be even"

; ---- start-up ---------------------------------------------------------------------------
; Entered from the loader with A = this bank.  Interrupts stay off from here on.
; Variable length (VCODE), like the first picture.
	.segment "VCODE"

init:	sei
	sta	bank
	sta	kbd_bank
	cld
	ldx	#$FF
	txs
	lda	#0
	sta	ULA_IRQEN
	lda	bank
	ora	#$70			; clear display end, RTC, high tone; keep the bank
	sta	ULA_PAGE
	lda	#$FF
	sta	ULA_PAL8
	sta	ULA_PAL9
	lda	#M1
	sta	ULA_MODE
	; clear &2400-&7FFF (the dummy area and the screen)
	lda	#0
	tay
	ldx	#$24
@clr:	stx	@cst+2
@cst:	sta	$2400,y
	iny
	bne	@cst
	inx
	bpl	@clr
	lda	#<START_WX
	sta	wx
	sta	mx
	lda	#>START_WX
	sta	wx+1
	sta	mx+1
	lda	#<START_WY
	sta	wy
	lda	#>START_WY
	sta	wy+1
	lda	#<SEED
	sta	lfsr
	lda	#>SEED
	sta	lfsr+1
	lda	#0
	sta	fpar
	sta	kprev
	lda	#SCHED			; the lead-in schedule
	sta	sched
	lda	#0
	sta	kprv2
	sta	kpend
	sta	kspp
	.if	MOTION
	lda	#1
	sta	autob
	lda	#0
	.else
	sta	autob
	.endif
	sta	KSPC
	sta	KEYS
	sta	cnext
	sta	cnext2
	sta	smode
	.ifdef	SCR0
	lda	#5*SCR0
	.endif
	sta	scrp
	lda	#0
	sta	hcnt
	sta	gch
	lda	#1
	sta	segl
	sta	vdiv
	sta	svd
	jsr	first_picture
	jsr	build
	jsr	setup_frame
	jsr	ula_apply
	jmp	boot_sync

; ---- first_picture: the window and its look-ahead rows, drawn at start-up ----------
	.segment "VCODE"
first_picture:
	; the first picture: all four notch classes of the 25 rows from top-1, drawn as
	; rows above the window (pass gkind 0), then, top down, as rows below (gkind 1),
	; so that each row's gap cells on both sides are zero.  A drawing also zeroes a
	; few cells past each end of its span (notch.s): as a row above, window cells of
	; the row before, which the second pass redraws; as a row below, window cells of
	; the row after, which it draws next.
	lda	#0
	sta	gkind
fpass:	lda	wy
	sec
	sbc	#8
	sta	tmp
	lda	wy+1
	sbc	#0
	tax
	lda	MAPHI,x
	sta	tmp+1
	jsr	row_of_tmp		; grow = top - 1
	lda	#25
	sta	fdn
ffr:	lda	#3
	sta	gcls
ffc:	jsr	ndraw
	dec	gcls
	bpl	ffc
	inc	grow			; next row, mod 320
	bne	:+
	inc	grow+1
:	lda	grow+1
	beq	:+
	lda	grow
	cmp	#<320
	bcc	:+
	lda	#0
	sta	grow
	sta	grow+1
:	dec	fdn
	bne	ffr
	inc	gkind
	lda	gkind
	cmp	#2
	bne	fpass
	lda	#0
	sta	gch
	rts

; ---- bootstrap: find the field and the bottom of the frame ----------------------------
; The PAL fields alternate 312 and 313 lines.  Wait for the RTC flag (line 99, at its
; start or half way along, by field), then count polls to display end (line 255 in a
; graphics mode): the count is shorter in the 313-line field (CAL_BTHR divides the
; two).  From display end, count to line 0 of the next field and enter frame_top.
; From then on the field parity (fpar) simply alternates.
	.segment "TAILS"		; (the delay loops of TAILS must not cross a page)
boot_sync:
	lda	#PALA			; the six palette registers only MODE 2 reads: set once
	sta	ULA_PAL8+2		; (here, in TAILS, so as not to move CODE: DESIGN.md 10)
	lda	#PALB
	sta	ULA_PAL8+3
	lda	#PALC
	sta	ULA_PAL8+4
	lda	#PALD
	sta	ULA_PAL8+5
	lda	#PALE
	sta	ULA_PAL8+6
	lda	#PALF
	sta	ULA_PAL8+7
	lda	#M1			; a graphics mode at line 255: display end fires
	sta	ULA_MODE
	lda	bank
	ora	#$30			; clear RTC and display end
	sta	ULA_PAGE
@w1:	lda	ULA_STAT
	and	#RTC_BIT
	beq	@w1
	lda	bank
	ora	#$30			; clear RTC and display end again
	sta	ULA_PAGE
	ldx	#0
	ldy	#0
@w2:	lda	ULA_STAT
	and	#DE_BIT
	bne	@de
	inx
	bne	@w2
	iny
	jmp	@w2
@de:	; F = (count < threshold) ? 1 : 0
	lda	#0
	cpx	#<CAL_BTHR
	tya
	sbc	#>CAL_BTHR		; C clear if count < threshold
	lda	#0
	rol	a
	eor	#1			; 1 if short count: the 313-line field
	sta	fpar
	; to the next field's line 0: (312 + F - 255) lines from display end
	DELAY	208			; past line 256 before a MODE 1 top mode
	lda	topmode
	sta	ULA_MODE
	lda	fpar
	asl	a
	clc
	adc	#CAL_BN64
	tax
bootd:	DELAY	59
	dex
	bne	bootd
	DELAY	CAL_BREM
	lda	ULA_STAT		; marker: where the lock read is issued
	jmp	frame_top

