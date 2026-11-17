	.segment "CODE"
; ---- the trajectory: this field's dy and the commit for the field after next but one --
; A segment is (fields, dx a commit, fields between commits, dy a step, fields between
; vertical steps): from the
; script (TRAJ = 0) or the random generator (TRAJ = 1); the cursor keys (Z X : /)
; replace it while held.  Rules: commits are at least 2 fields apart and move at most
; 2 columns; dy is at most DYMAX (2) lines a field: one class of a look-ahead row.
logic:	dec	segl
	bne	@keep
	.if	TRAJ = 0
	ldx	scrp
	lda	SCRIPT,x
	bne	:+
	ldx	#0
	lda	SCRIPT
:	sta	segl
	lda	SCRIPT+1,x
	sta	sdx
	lda	SCRIPT+2,x
	sta	sgap
	lda	SCRIPT+3,x
	sta	sdy
	lda	SCRIPT+4,x
	sta	svd
	txa
	clc
	adc	#5
	sta	scrp
	.else
	jsr	rnd			; one draw: the low byte the length, the high the steps
	and	#31
	clc
	adc	#1
	sta	segl
	lda	lfsr+1
	and	#7
	tax
	lda	RDX,x
	sta	sdx
	lda	lfsr+1
	lsr	a
	lsr	a
	lsr	a
	and	#7
	tax
	lda	RDY,x
	sta	sdy
	lda	lfsr
	rol	a
	rol	a
	rol	a
	and	#3
	tax
	lda	RVD,x
	sta	svd
	lda	lfsr+1
	and	#$C0
	bne	@keep
	lda	lfsr
	and	#$60
	bne	@keep
	; one segment in 16: a long maximum-speed diagonal
	jsr	rnd
	and	#63
	ora	#64
	sta	segl
	lda	lfsr+1
	and	#3
	tax
	lda	DGX,x
	sta	sdx
	lda	DGY,x
	sta	sdy
	lda	#1
	sta	svd
	.endif
@keep:	lda	sdx
	sta	tmp
	lda	#0			; a vertical step every svd fields
	sta	dy
	dec	vdiv
	bne	:+
	lda	svd
	sta	vdiv
	lda	sdy
	sta	dy
:
	lda	KSPC			; SPACE toggles the bouncing script
	cmp	kspp
	sta	kspp
	beq	:+
	cmp	#0
	beq	:+
	lda	autob
	eor	#1
	sta	autob
:	lda	autob
	bne	:+
	lda	#0			; (off: the script moves nothing)
	sta	tmp
	sta	dy
:	lda	KEYS			; one step a press: a newly pressed key is latched
	and	#$0F			; until its step is taken
	tax
	eor	kprv2
	stx	kprv2
	and	kprv2
	ora	kpend
	sta	kpend
	beq	@auto
	tax
	lda	KDY,x
	asl	a
	sta	dy
	lda	#1
	sta	vdiv
	lda	KDX,x
	sta	tmp
	beq	:+			; (no horizontal step: nothing left pending)
	txa
	and	#3			; the vertical step is taken this field
:	sta	kpend
@auto:	lda	dy			; the rule: at most DYMAX lines a field
	bmi	:+
	cmp	#DYMAX+1
	bcc	:++
	lda	#DYMAX
	bne	:++
:	cmp	#<(-DYMAX)
	bcs	:+
	lda	#<(-DYMAX)
:	sta	dy
	lda	#0
	sta	hnew
	lda	hcnt
	beq	:+
	dec	hcnt
	bne	@done
:	lda	tmp
	beq	@done
	lda	cnext2			; the rule: no commit in the field after another's
	bne	@done
	; A 2-column step right stores its second column a field early, in the cell that is the
	; next row's first: with the window at character 15 that cell is on screen when the
	; early field has no lead-in.  Take one column then (the phase then stays odd: no cost
	; after the first time).
	lda	tmp
	cmp	#2
	bne	:+
	lda	wx
	clc
	adc	cnext
	eor	#WIN_C			; (WIN_C - wx) & 7 = 0 <=> the low three bits are equal
	and	#7
	bne	:+
	lda	#1
	sta	tmp
:	lda	tmp
	sta	hnew
	lda	#0			; the horizontal step is taken
	sta	kpend
	.if	TRAJ = 0
	ldx	sgap
	.else
	jsr	rnd
	and	#7
	tax
	lda	RGAP,x
	tax
	.endif
	dex
	stx	hcnt
@done:	rts

; 16-bit Galois LFSR; A = its low byte
rnd:	ldx	#8
@l:	lsr	lfsr+1
	ror	lfsr
	bcc	:+
	lda	lfsr+1
	eor	#$B4
	sta	lfsr+1
:	dex
	bne	@l
	lda	lfsr
	rts

