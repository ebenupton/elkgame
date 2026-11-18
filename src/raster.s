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
;   0..14  two stores (in the window: the entering column's byte and the leaving zero)
;   +9     MODE 3, inside the line sync
;   +17    the lead-in mode: mode 7 (40 columns), or MODE 1 when there is no lead-in
;          (+15 in the window's gadgets)
;   +23+u  MODE 1 (the variant, gen_variants.s; none when u = 0)
; Three parts: loop 1, the lines above the window (the dummy snippet DSNIP: both
; stores to the dummy page); the palette line (iteration Y0-1, whose two stores are
; the palette's); loop 2, the window (gen_loop2.s, below).  In loop 1 and the palette
; line, Y is the lead-in mode value (vcv).
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
	ldy	vcv			; Y = the lead-in mode value, for loop 1 and the palette line
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
	sty	ULA_MODE		; S+17: the lead-in mode
	lda	#MW			; the window's mode (MODE 1, or MODE 2)
	jmp	(VVECP)			; the lead-in variant
backP:	ldx	vav			; X = the blip's mode value, through the window
	DELAY	CAL_ENT
wtP:	jmp	tA0			; patched: the tail that loads the first window line
	.assert	>frame_top = >*, error, "loop 1 must sit in one page"

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
	.include "gen_snips.s"
