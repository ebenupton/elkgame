; macros.inc -- cycle-exact delays and the fixed-time cell writers.
;
; Cycle counts are 2 MHz CPU cycles, for code running from sideways RAM (every fetch
; at 2 MHz).  Accesses to main RAM or I/O take a 1 MHz slot: 2 or 3 cycles depending
; on the phase they start in (docs/ULA-NOTES.md section 6), which the calibration
; (cal.inc) absorbs.  None of these macros touches main RAM except the cell writers'
; stores.

; PADN n: exactly n cycles (n = 0 or n >= 2) of nop, with one jmp *+3 for an odd n.
; Changes no register or flag.
	.macro	PADN	n
	.if	(n) = 0
	.elseif	(n) = 1
	.error	"PADN 1"
	.elseif	((n) & 1) = 1
	jmp	*+3
	.repeat	((n)-3)/2
	nop
	.endrep
	.else
	.repeat	(n)/2
	nop
	.endrep
	.endif
	.endmacro

; DELAY n: exactly n cycles (n = 0 or n >= 2).  Below 14, PADN; otherwise a counted
; loop (5 cycles a pass, 3 to set up) and PADN for the rest.  The loop must not cross
; a page (asserted).  Clobbers A and the flags.
	.macro	DELAY	n
	.local	lp
	.if	(n) < 14
	PADN	(n)
	.else
	kk	.set	((n) - 3) / 5
	rr	.set	(n) - (5*kk + 3)
	.if	rr = 1
	kk	.set	kk - 1
	rr	.set	rr + 5
	.endif
	lda	#kk		; 2
	sec			; 2
lp:	sbc	#1		; 2
	bne	lp		; 3 (2 the last time)
	.assert	>lp = >*, error, "DELAY loop crosses a page"
	PADN	rr
	.endif
	.endmacro

; LDELAY n: exactly n cycles (21 <= n <= 1296) wherever it sits: the loop lives in its
; own page (dlp, raster.s), entered by jmp and left by a jmp whose operand the macro
; patches, so it needs no stack and is not upset by page crossings at the call site.
; Clobbers A and the flags.
	.macro	LDELAY	n
	.local	ret
	lk	.set	((n) - 21) / 5
	lr	.set	(n) - (5*lk + 21)
	.if	lr = 1
	lk	.set	lk - 1
	lr	.set	lr + 5
	.endif
	lda	#<ret			; 2
	sta	dret+1			; 4
	lda	#>ret			; 2
	sta	dret+2			; 4
	lda	#lk			; 2
	jmp	dlp			; 3, then 2 + 5k - 1 + 3
ret:	PADN	lr
	.endmacro

; SELP en: (plo, phi) <- A:Y (a real cell) if en,x is set, else the dummy; fixed time
	.macro	SELP	en
	.local	sdone, sreal
	sta	plo
	sty	phi
	lda	en,x
	bne	sreal
	lda	#<DUMMY
	sta	plo
	lda	#>DUMMY
	sta	phi
	jmp	sdone
sreal:	PADN	14
sdone:
	.endmacro

; PUTCC p: the cell at (plo, phi) <- pve (lines 0, 2, 4, 6), pvo (1, 3, 5), pv7 (7), in line, fixed time
	.macro	PUTCC	p
	lda	phi
	.repeat	8, i
	sta	.ident(.sprintf("%s%d", .string(p), i))+2
	.endrep
	ldx	plo
	lda	pve
.ident(.sprintf("%s0", .string(p))):	sta	a:$FF00,x
.ident(.sprintf("%s2", .string(p))):	sta	a:$FF02,x
.ident(.sprintf("%s4", .string(p))):	sta	a:$FF04,x
.ident(.sprintf("%s6", .string(p))):	sta	a:$FF06,x
	lda	pvo
.ident(.sprintf("%s1", .string(p))):	sta	a:$FF01,x
.ident(.sprintf("%s3", .string(p))):	sta	a:$FF03,x
.ident(.sprintf("%s5", .string(p))):	sta	a:$FF05,x
	lda	pv7
.ident(.sprintf("%s7", .string(p))):	sta	a:$FF07,x
	.endmacro

; PUTCM p: as PUTCC, but line i is stored only if MLINE+mrow+i is set (else it goes to
; the dummy page); fixed time
	.macro	PUTCM	p
	lda	#>DUMMY
	sta	msel
	lda	phi
	sta	msel+1
	ldy	mrow
	.repeat	8, i
	ldx	MLINE+i,y
	lda	msel,x
	sta	.ident(.sprintf("%s%d", .string(p), i))+2
	.endrep
	ldx	plo
	lda	pve
.ident(.sprintf("%s0", .string(p))):	sta	a:$FF00,x
.ident(.sprintf("%s2", .string(p))):	sta	a:$FF02,x
.ident(.sprintf("%s4", .string(p))):	sta	a:$FF04,x
.ident(.sprintf("%s6", .string(p))):	sta	a:$FF06,x
	lda	pvo
.ident(.sprintf("%s1", .string(p))):	sta	a:$FF01,x
.ident(.sprintf("%s3", .string(p))):	sta	a:$FF03,x
.ident(.sprintf("%s5", .string(p))):	sta	a:$FF05,x
	lda	pv7
.ident(.sprintf("%s7", .string(p))):	sta	a:$FF07,x
	.endmacro


; NOCROSS label, n: assert that the n bytes from label lie in one page (an indexed
; access to them never costs the extra cycle of a page crossing).
	.macro	NOCROSS	label, n
	.assert	>(label) = >(label + n - 1), error, .sprintf("%s crosses a page", .string(label))
	.endmacro

; NOWRAP vector: assert that a jmp (vector) does not meet the 6502's indirect-jump bug
; (a vector at &xxFF takes its high byte from &xx00).
	.macro	NOWRAP	vector
	.assert	<(vector) <> $FF, error, .sprintf("%s is at &xxFF", .string(vector))
	.endmacro
