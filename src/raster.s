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
; Then the rest of the lines above the window are MODE 4, or MODE 6 in the band (the f
; 10-line rows at the top, docs/DESIGN.md 2.4): 40-column modes, which the ULA fetches
; for without holding up the CPU, so main RAM runs at 1 MHz, uncontended, and the time
; is free for fixed-length work.  No per-line writes are needed: every row above the
; window is 320 bytes, a multiple of 64, so each starts aligned.  The band ends at line
; 10f - 1 with a switch to MODE 4 at S + 17 us: written on lines 9 and 19 by table
; (fw9, fw19: the band's end, or no change), and on line 29 by the palette line's
; lead-in write.  Between the writes: the free time (the strip build, frame.s, and
; delays a game can replace: CAL_TA, CAL_TB, CAL_TC).
;
; Then the palette line and loop 2, the window.  The scanline loop: one iteration a
; line, 128 cycles; iteration y runs from the right margin of line y to the lead-in of
; line y+1 (us after S of line y):
;   -3     the blip: MODE 5 when the lead-in is 0 or 1 us (else the window's mode, no
;          change); not on the palette line, whose line is a 40-column one
;   0..14  two stores (in the window: the entering column's byte and the leaving zero;
;          on the palette line, the palette)
;   +9     MODE 3, inside the line sync
;   +17    the lead-in mode: mode 7 (40 columns), or the window's when there is no
;          lead-in (+15 in the window's gadgets)
;   +23+u  the window's mode (the variant, gen_variants.s; none when u = 0)
	.segment "LOOP"
frame_top:
	lda	SYNCB			; the lock: issued inside line 0's fetches, stalls until S
ftop:	lda	#M4			; patched (setup_frame): M4, or M6 in a band
	sta	ULA_MODE		; line 0, S + 3 us: uncontended from here
	LDELAY	CAL_TA			; (free)
fw9:	lda	#M4			; patched: M4, or M6 if the band runs on past line 9
	sta	ULA_MODE		; line 9, S + 17 us
	jsr	build			; the strip for this field's window (strip.s)
	LDELAY	CAL_TB			; (free)
fw19:	lda	#M4			; patched: M4, or M6 if the band runs on past line 19
	sta	ULA_MODE		; line 19, S + 17 us
	LDELAY	CAL_TC			; (free)
	ldy	vcv			; Y = the lead-in mode value, for the palette line

; the palette line: its two stores the palette's
palb:	PADN	7
	lda	#PAL8
	sta	ULA_PAL8		; S+4
	lda	#M3
	nop
	sta	ULA_MODE		; S+9
	lda	#PAL9
	sta	ULA_PAL9		; S+13
	nop
	sty	ULA_MODE		; S+17: the lead-in mode (on line 29 of a 3-row band, its end)
	lda	#MW			; the window's mode (MODE 1, or MODE 2)
	jmp	(VVECP)			; the lead-in variant
backP:	ldx	vav			; X = the blip's mode value, through the window
	DELAY	CAL_ENT
wtP:	jmp	tA0			; patched (build): the tail that loads the first window line

; ---- loop 2: the window ---------------------------------------------------------------
; Two gadgets of horizontal-blanking code, gA for even map rows and gB for odd, and
; sixteen blocks of visible-part code, b{P}{k} after line k of a P row (gen_loop2.s):
;   gadget (horizontal blanking): the entering byte (A) and the leaving zero, by the
;     8-byte block 'sta in / lda #0 / sta out'; MODE 3 in the sync; the lead-in mode;
;     the variant (VJ), which returns to the next block (VRET);
;   block (the next line's visible part): its slice of the next row's preparation --
;     the other gadget's two addresses (+576, ring-wrapped, from this gadget's), and
;     the pattern bytes of the next colour pair; this gadget's two addresses stepped one
;     byte down their cells; VRET <- the next block;
;   tail (right margin): the blip (X), the next line's entering byte, the jump.
; A row counter in the line-7 blocks arms the exit: one block, chosen per field, has
; its 'sta VRET' turned into 'sta VJ' with VX, so the last line's gadget exits.
	.include "gen_loop2.s"

	.include "gen_variants.s"
