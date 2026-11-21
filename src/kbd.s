; kbd.s -- the keyboard scan, in main RAM at &0900 (KBD), copied there by the loader.
;
; Timing: variable length; frame.s calls it once a field in the variable-length work
; below the window, before logic.  Its time is not counted.
;
; The Electron's keyboard is read through ROM slot 8: paging it in maps the keyboard
; matrix over &8000-&BFFF (an address line held low selects a column -- the comments
; name it -- and the low four data bits are the rows, 1 for a key held), which unmaps
; this program's bank: so the routine runs from main RAM.  Leaving slots 8-11 must go
; by way of slot 12 (AUG section 15.4).  Result in KEYS (bits 0..5: left or Z, right or
; X, up or :, down or /, comma, full stop; logic reads bits 0..3, frame.s bits 4..5, the
; lead-in schedule) and KSPC (SPACE: 8 while held, else 0).  The ULA_PAGE writes leave
; the interrupt-clear bits 0.
	.segment "KBDCODE"
kbd:	lda	#8
	sta	ULA_PAGE
	lda	$AFFF			; Z: line 12 bit 3 -> bit 0, with LEFT
	lsr	a
	lsr	a
	lsr	a
	ora	$BFFD			; LEFT: line 1 bit 0
	and	#1
	sta	KTMP
	lda	$B7FF			; X: line 11 bit 3 -> bit 1, with RIGHT
	lsr	a
	lsr	a
	lsr	a
	ora	$BFFE			; RIGHT: line 0 bit 0
	and	#1
	asl	a
	ora	KTMP
	sta	KTMP
	lda	$BFFB			; UP: line 2 bit 1, COLON bit 2 -> bit 2
	lsr	a
	ora	$BFFB
	lsr	a
	and	#1
	asl	a
	asl	a
	ora	KTMP
	sta	KTMP
	lda	$BFF7			; SLASH: line 3 bit 3 -> bit 3, with DOWN
	lsr	a
	lsr	a
	ora	$BFFD			; DOWN: line 1 bit 1
	and	#2
	asl	a
	asl	a
	ora	KTMP
	sta	KTMP
	lda	$BFDF			; COMMA: line 5 bit 3 -> bit 4
	and	#8
	asl	a
	ora	KTMP
	sta	KTMP
	lda	$BFEF			; FULL STOP: line 4 bit 3 -> bit 5
	and	#8
	asl	a
	asl	a
	ora	KTMP
	sta	KEYS
	lda	$BFFE			; SPACE: line 0 bit 3
	and	#8
	sta	KSPC
	lda	#$0C			; out of 8-11 by way of 12 (AUG 15.4)
	sta	ULA_PAGE
	lda	#0			; back to this program's bank
kbd_bank = * - 1			; (init patches in its number)
	sta	ULA_PAGE
	rts
