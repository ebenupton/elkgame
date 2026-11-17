; frame.s -- the bottom of the frame: everything between the window's last line and
; the next field's raster lock (docs/DESIGN.md section 6).
;
; Entered from the window's exit block (VX) at line 200.  In order:
;   variable length (must end before line 249, display end in a text mode):
;     the keys and the schedule switch, the trajectory (logic.s), the vertical step
;     (notch.s); then a poll for display end, which absorbs the variation;
;   fixed length (calibrated in cal.inc, every path padded to the same time):
;     the column step's edge rows (colop.s) -- for a commit, for the behind field of a
;     2-column step, or a pad for an idle field; the strip for the next field
;     (strip.s); the next field's display parameters (display.s); and a counted delay
;     (frame_tail) to the lock read in line 0.
; The "bit ULA_STAT" reads are markers: harmless status reads whose raster positions
; the emulator's I/O log records (the soak finds the variable work's end by them).
	.segment "CODE"
work:					; ---- variable length: must end before line 249 ----
	bit	ULA_STAT		; marker: the bottom of the frame begins
	lda	fpar			; the field parity alternates
	eor	#1
	sta	fpar
	lda	bank
	ora	#$30			; clear RTC and display end; keep the bank
	sta	ULA_PAGE
	; the schedule: comma selects the FPGA ULA's lead-ins (sched = 0), full stop the
	; real ULA's (sched = 8), on the key's press
	lda	KEYS
	eor	kprev			; newly pressed
	and	KEYS
	tax
	lda	KEYS
	sta	kprev
	lda	sched
	and	SCHKEEP,x
	ora	SCHSET,x
	sta	sched
	jsr	KBD			; the keys, for the next field's logic and schedule
	jsr	logic			; this field's dy, and hnew: the commit two fields on
	jsr	vstep
	bit	ULA_STAT		; marker: the variable work's end
wk_de:	lda	ULA_STAT
	and	#DE_BIT
	beq	wk_de
	; ---- fixed length from here to the lock: every path padded to the same time ----
	bit	ULA_STAT
	lda	cnext
	beq	wk_noc
	; a commit (shown next field): the ahead column's edge rows now; the strip will
	; store its window lines ahead of the beam
	ldx	#1
	and	#$80
	beq	:+
	ldx	#$FF
	DELAY	CAL_CM			; (the two directions' edge rows differ in length: pad each
	jmp	:++			; so that the lock read lands mid-line whichever it was)
:	nop
	DELAY	CAL_CP
:	stx	cdir
	lda	#1
	sta	cen
	sta	ctb
	sta	smode
	jsr	colop			; (leaves sxin, sxout)
	jsr	mx_step
	lda	cnext			; the window shown moves
	clc
	adc	wx
	sta	wx
	lda	cnext
	and	#$80
	beq	:+
	lda	#$FF
:	adc	wx+1
	tax
	lda	MAPHI,x
	sta	wx+1
	lda	wy
	clc
	adc	#1
	and	#7
	sta	k0
	jmp	wk_pl
wk_noc:	ldx	cnext2			; a 2-column commit the field after next?
	lda	BEH,x
	bne	wk_beh
	lda	#0			; idle: no edge rows, no strip; the same time
	sta	smode
	LDELAY	CAL_NOC1
	LDELAY	CAL_NOC2
	LDELAY	CAL_NOC3
	LDELAY	CAL_NOC
	jmp	wk_pl
wk_beh:	sta	cdir			; the behind field of a 2-column step: its first column's
					; edge rows (hidden lines only), and a strip behind the beam
	bmi	:+			; (going right is the shorter: pad it)
	DELAY	CAL_BP
:
	lda	#1
	sta	cen
	lda	#0
	sta	ctb
	lda	#2
	sta	smode
	jsr	colop
	jsr	mx_step
	lda	wy
	and	#7
	sta	k0
	LDELAY	CAL_BEH
wk_pl:	bit	ULA_STAT		; marker
	lda	cnext2
	sta	cnext
	lda	hnew
	sta	cnext2
	jsr	build			; the strip
	bit	ULA_STAT		; marker
	jsr	setup_frame
	jsr	ula_apply
	jmp	frame_tail

; ---- mx_step: mx += cdir (mod 2560) --------------------------------------------------
mx_step:
	lda	cdir
	clc
	adc	mx
	sta	mx
	lda	cdir
	and	#$80
	beq	:+
	lda	#$FF
:	adc	mx+1
	tax
	lda	MAPHI,x
	sta	mx+1
	rts

; ---- the delay to the lock -----------------------------------------------------------
; Count to the next field's line 0: (312 + F) lines from frame_top, F = 1 in the
; 313-line field, less what the fixed-length work has spent.
	.segment "TAILS"
frame_tail:
	bit	ULA_STAT		; marker
	lda	fpar
	asl	a
	clc
	adc	#CAL_N64
	tax
taild:	DELAY	59
	dex
	bne	taild
	DELAY	CAL_REM
	lda	ULA_STAT		; marker: where the lock read is issued
	jmp	frame_top

	.assert	>boot_sync = >*, error, "the tails must sit in one page"
