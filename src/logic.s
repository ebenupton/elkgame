; logic.s -- the trajectory: where the window goes next.
;
; Timing: variable length.  frame.s calls it once a field in the variable-length work
; below the window (after the keyboard, before vstep); the display-end poll that follows
; absorbs its time.
;
; It sets
;   dy    the lines to move this field (0 or +-2).  vstep moves wy and plans the notch
;         this field, nstore draws it after display end, and it is shown next field.
;   hnew  the columns to commit (0, +-1 or +-2).  A commit moves down a pipeline in
;         frame.s (hnew -> cnext2 -> cnext, one stage a field): chosen in field N, its
;         edge rows are drawn in the bottom of field N+2 and the window moves in field
;         N+3, whose strip stores the column ahead of the beam.  For a 2-column commit
;         the first column goes a field early: its edge rows (hidden lines) in the bottom
;         of field N+1 and its strip behind the beam in field N+2 (the behind field).
; The motion comes in segments of (fields, columns a commit, fields between commits,
; lines a vertical step, fields between vertical steps): from the script (TRAJ = 0,
; gen.py SCRIPT) or a random walk (TRAJ = 1).  SPACE starts and stops it (MOTION = 1:
; moving from the start).  The cursor keys (or Z X : /) each take one step a press --
; one column, or 2 lines -- whether or not the motion is on.
;
; The engine's rules, enforced here:
;   - a commit moves at most 2 columns, and commits are at least 2 fields apart (none
;     while one is in cnext2), so a field's strip is ahead, behind or idle, never two
;     at once;
;   - dy is at most DYMAX = 2 lines a field: one notch class of one look-ahead row, the
;     single plan vstep prepares;
;   - the one-column rule (below), which holds because WIN_C + WIN_W = 72.
	.segment "VCODE"
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
	jsr	rnd			; one draw: the low byte's bits 0-4 the length (1..32),
	and	#31
	clc
	adc	#1			;   the high byte the steps, the low's bits 6-7 the
	sta	segl			;   vertical step's period
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
	; one segment in 16 (four bits zero): a long diagonal (64..127 fields), 2 columns
	; a commit and 2 lines every field
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
	lda	#0			; the segment's vertical step every svd fields
	sta	dy
	dec	vdiv
	bne	:+
	lda	svd
	sta	vdiv
	lda	sdy
	sta	dy
:
	lda	KSPC			; SPACE toggles the motion, on its press
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
	lda	#0			; (off: the segment moves nothing)
	sta	tmp
	sta	dy
:	lda	KEYS			; the cursor keys, one step a press: a newly pressed key
	and	#$0F			; is latched in kpend until its step is taken, and
	tax				; overrides the segment's step this field
	eor	kprv2
	stx	kprv2
	and	kprv2
	ora	kpend
	sta	kpend
	beq	@auto
	tax
	lda	KDY,x			; up or down: 2 lines
	asl	a
	sta	dy
	lda	#1			; (the segment's next vertical step a field on)
	sta	vdiv
	lda	KDX,x			; left or right: one column
	sta	tmp
	beq	:+			; (no horizontal step: nothing stays pending)
	txa
	and	#3			; the vertical step is taken now; left and right stay
:	sta	kpend			;   pending until the commit is made
@auto:	lda	dy			; the rule: at most DYMAX lines a field, either way
	bmi	:+
	cmp	#DYMAX+1
	bcc	:++
	lda	#DYMAX
	bne	:++
:	cmp	#<(-DYMAX)
	bcs	:+
	lda	#<(-DYMAX)
:	sta	dy
	lda	#0			; the commit: none unless the gap since the last has run
	sta	hnew
	lda	hcnt
	beq	:+
	dec	hcnt
	bne	@done
:	lda	tmp
	beq	@done
	lda	cnext2			; the rule: no commit in the field after another's
	bne	@done
	; The one-column rule (DESIGN.md, "Why 56 characters at 16, and the one-column
	; rule").  A 2-column step right stores its first entering column a field early, in
	; the behind field, in row y's cell at mx + WIN_W.  Along the ring that is row
	; y+1's cell mx + WIN_W - 72 = mx - WIN_C: with WIN_C + WIN_W = 72, the leftmost
	; cell the margin shows when there is no lead-in.  So if the behind field would
	; have no lead-in (t = (WIN_C - wx) & 7 = 0, at the position wx + cnext it shows),
	; take one column instead.  After that a run of 2-column steps keeps t odd, so the
	; rule costs one field, once.
	lda	tmp
	cmp	#2
	bne	:+
	lda	wx
	clc
	adc	cnext
	eor	#WIN_C			; t = 0 <=> the low three bits are equal
	and	#7
	bne	:+
	lda	#1
	sta	tmp
:	lda	tmp
	sta	hnew
	lda	#0			; the key's horizontal step, if any, is taken
	sta	kpend
	.if	TRAJ = 0			; the gap to the next commit: the script's, or random
	ldx	sgap
	.else
	jsr	rnd
	and	#7
	tax
	lda	RGAP,x
	tax
	.endif
	dex				; hcnt = gap - 1: the next commit may come gap - 1 fields
	stx	hcnt			;   on (and never the next field: cnext2)
@done:	rts

; ---- rnd: a 16-bit Galois LFSR (taps &B400), eight steps; returns its low byte in A --
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

