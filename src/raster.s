; raster.s -- the top of the frame: the raster lock and the scanline loop.
;
; Everything here is cycle-counted (docs/DESIGN.md section 3).  Times are in us after
; S, the end of a stalled main-RAM read on the same line (h ~648 of 1024, in the right
; margin): all the loop's writes are placed relative to S, the only raster position
; the program can observe.  A 64 us line is 128 cycles.

; ---- the long-delay loop (LDELAY, macros.inc) ------------------------------------------
	.segment "DLOOP"
dlp:	sec
@l:	sbc	#1
	bne	@l
dret:	jmp	$0000			; patched by LDELAY: back to the caller

; ---------------------------------------------------------------------------------------
	.segment "ENTRY"
entry:	jmp	init			; &8000, from the loader, with A = this bank's number

; ---- the frame top ---------------------------------------------------------------------
; The lock is two stalled reads.  A main-RAM read on a line the ULA is fetching for in a
; 20K mode stalls until the line's fetches end (S).  The first read is aimed late in
; line 0; if it arrives after line 0's fetches have ended it returns at once, and the
; second, mid line 1, still stalls to the end of line 1.  So the lock tolerates errors
; of about +-20 us in the timing of the work below the window (frame.s).  Line 0 and
; line 1 are MODE 1 or MODE 3 (topmode), so both reads stall.
;
; Then: band_n - 1 more lines counted, to the first iteration's line; the iterations of
; loop 1 (the lines above the palette line, n1 of them); the palette line; and loop 2,
; the window.
;
; The scanline loop.  One iteration a line, 128 cycles.  Iteration y runs from the
; right margin of line y to the lead-in of line y+1 (us after S of line y):
;   -3     the blip: MODE 5 when the lead-in is 0 or 1 us (else MODE 1, no change)
;   +5     the first store of the pair (window: the entering column's byte)
;   +9     MODE 3, inside the line sync
;   +14    the second store (window: the leaving column's zero)
;   +17    the lead-in mode: mode 7 (40 columns), or MODE 1 when there is no lead-in
;   +23+u  MODE 1 (the variant, gen_variants.s; none when u = 0)
; Three parts: loop 1, the lines above the window (both stores go to the dummy); the
; palette line (iteration Y0-1, whose two stores are the palette's); loop 2,
; iterations Y0..Y1-2, whose stores are a row snippet's (gen_snips.s).  In loop 2,
; X = the line within the character row and Y = the +17 mode value.
	.segment "LOOP"
frame_top:
	lda	SYNCB			; stalls until S of line 0 -- or, issued late (after
	DELAY	CAL_L2			; line 0's last fetch), returns at once
	ldx	band_n			; >= 1: lines to the first iteration, counted from line 0
	dex
	lda	SYNCB			; the lock: stalls until S of line 1 either way
	txa
	beq	fnob
bandl:	DELAY	123
	dex
	bne	bandl			; 128 a line, 127 the last
	nop
fnob:
	DELAY	CAL_PRE
	ldy	vcv			; Y = the +17 mode value, for the whole loop
	ldx	#0
	lda	n1
	beq	@pal			; (no lines above the palette line's)
	sta	cnt1
	jmp	wl1b
@pal:	DELAY	CAL_PREP
	jmp	palb

; loop 1: the lines above the window
wl1:	PADN	3
va1:	lda	#M1			; patched (setup_frame): the blip's mode value
	sta	ULA_MODE		; S-3
wl1b:	PADN	2
	jmp	DSNIP			; the dummy snippet: stores to DUMMY, MODE 3, +17
back1:	DELAY	37
	dec	cnt1
	bne	wl1

; the palette line: the same skeleton, its two stores the palette's
	PADN	4
vap:	lda	#M1			; patched: the blip
	sta	ULA_MODE
palb:	PADN	7
	lda	#PAL8
	sta	ULA_PAL8		; S+4
	lda	#M3
	nop
	sta	ULA_MODE		; S+9
	lda	#PAL9
	sta	ULA_PAL9		; S+13
	nop
	sty	ULA_MODE		; S+17
	lda	#M1
	jmp	(VVECP)			; the lead-in variant
backP:	ldx	k0			; X = the first window line's line within its row
	DELAY	39
	jmp	wl2
	.assert	>frame_top = >*, error, "loop 1 must sit in one page"

; loop 2: the window
	.segment "LOOP2"
wl2:	PADN	3
va2:	lda	#M1			; patched: the blip
	sta	ULA_MODE		; S-3
	jmp	(sptr)			; the row's snippet: both stores, MODE 3, the +17 write,
					; then the variant, which returns to back2
back2:	inx
	cpx	#8
	bne	same
	ldx	#0			; the row's last line: the next row's snippet (C = 1)
	lda	sptr
	adc	#SNSTR-1
	sta	sptr
	lda	sptr+1
	adc	#0
	sta	sptr+1
rtc:	lda	ULA_STAT		; a status sample each line, kept in RTCLOG (a record for
rtst:	sta	RTCLOG			; debugging; the operand's low byte is the loop counter:
	dec	rtst+1			; the iterations left, 169..1)
	bne	wl2
	; iteration Y1-1: the snippet once more (line Y1-1's bytes, behind the beam), whose
	; variant is VX: black, and MODE 6 for the rest of the field (a text mode, so no
	; contention, and display end is flagged at line 249).  Y is M1 or M5, the offsets
	; of VX's two entries in the variants' page.
	sty	VVEC2
va3:	lda	#M1			; patched: the blip, for line Y1's row start
	sta	ULA_MODE		; S-3
	jmp	(sptr)
same:	DELAY	18
	jmp	rtc
	.assert	>wl2 = >*, error, "loop 2 must sit in one page"

	.include "gen_variants.s"
	.include "gen_snips.s"
