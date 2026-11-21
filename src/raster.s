; raster.s -- the top of the frame: the raster lock, the lines above the window, the
; palette line and the window's scanline loop.
;
; Everything from the lock to the window's exit is cycle-counted (docs/DESIGN.md, "The
; frame and the scanline loop").  Times are in us after S, the end of a stalled main-RAM
; read on the same line (about h 648 of 1024, just after the line's display fetches end,
; in the right margin): S is the only raster position the program can observe, so every
; write is placed relative to it.  A 64 us line is 128 cycles.

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
; The lock is one stalled read.  Line 0 is MODE 1, or MODE 3 when there is a band
; (topmode, written by ula_apply on line 311): a 20K mode, in which a main-RAM read
; issued while the ULA fetches the line stalls until the fetches end, at S.  The read
; of SYNCB is aimed inside line 0's fetches (h 0 to about 648); the soak finds it issued
; at h 152-488 (the marker read 3 us before it), which leaves about 12 us early and 7 us late for the work below the window
; (frame.s).  Too early is the worse failure: a read issued before line 0's fetches
; returns at once, and every later field's read then arrives too early as well.  A read
; issued after S also returns at once, and the field's writes are late.
;
; From S of line 0 the code is counted.  At S + 3 us the mode goes to MODE 4, or MODE 6
; in a band (the f 10-line text rows at the top: docs/DESIGN.md, "Vertical fine scroll:
; the band"): 40-column modes, which the ULA fetches for without holding up the CPU, so
; main RAM runs at 1 MHz, uncontended, and the time down to the palette line is free
; for fixed-length work.  No per-line writes are needed: every row above the window is
; 320 bytes, a multiple of 64, so each starts aligned.  The band ends on line 10f - 1
; with a switch to MODE 4 at S + 17 us: written on lines 9 and 19 by table (fw9, fw19:
; the band's end, or no change), and for f = 3 on line 29 by the palette line's
; lead-in write.  Between the writes is the free time: CAL_TA (1,170 cycles), the strip
; build (998) and CAL_TB (280), and CAL_TC (1,235) -- 2,685 cycles of delay a game can
; replace with its own fixed-length work.  These writes are all in the horizontal
; blanking, so none takes a video slot (the leak byte, below).
;
; Then the palette line (line 29) and loop 2, the window (lines 30-199).  One iteration
; a line, 128 cycles; iteration y runs from the right margin of line y to the lead-in
; of line y+1, with these writes (us after S of line y):
;   -3     the blip: MODE 5 when u <= 1 (the lead-in is 0 or 1 us), else the window's
;          mode (no change); not on the palette line, whose line is a 40-column one
;   0..13  two stores: in the window, the entering column's byte just after S and the
;          leaving column's zero about 3 us later; on the palette line, the palette
;          (&FE08 at +4, &FE09 at +13)
;   +9     MODE 3, inside the line sync
;   +15    the lead-in mode (+17 on the palette line): mode value 7, a 40-column mode,
;          or the window's mode when there is no lead-in (u = 0)
;   +23+u  the window's mode, MODE 1 or MODE 2 (the variant, gen_variants.s; no write
;          when u = 0).  It lands at about h 16u - 8 of line y+1, character 2u - 1.
; u is the lead-in in us: t = (WIN_C - wx) & 7 on the FPGA ULA's schedule, t + 1 (0 when
; t = 0) on the real ULA's (docs/DESIGN.md, "Two ULAs: the schedules").
;
; The leak byte: the blip and the variant's write fall inside the fetches, and on a real
; ULA each takes its video slot, which shows RAM[&7E07] (LEAK, hw.inc) in place of the
; slot's own byte.  Both slots are in the margins, so the engine keeps &7E07 zero and
; they show black (docs/DESIGN.md, "The leak byte").
;
; On a Ferranti ULA mode value 7 is plain MODE 4, which wraps at &8000 to &5800, not to
; &3000: a line with an 8 us lead-in (t = 7 on the real schedule) takes its eighth
; 40-column step across &8000 on the ring row that starts at &7FC0, and that row's
; lines show the wrong bytes.  The engine does not avoid this yet.
	.segment "LOOP"
frame_top:
	lda	SYNCB			; the lock: issued inside line 0's fetches, stalls until S
ftop:	lda	#M4			; patched (setup_frame): M4, or M6 in a band
	sta	ULA_MODE		; line 0, S + 3 us: uncontended from here
	LDELAY	CAL_TA			; (free)
fw9:	lda	#M4			; patched: M4, or M6 if the band runs on past line 9
	sta	ULA_MODE		; line 9, S + 17 us
	jsr	build			; the strip for this field's window (strip.s): 998 cycles
	LDELAY	CAL_TB			; (free)
fw19:	lda	#M4			; patched: M4, or M6 if the band runs on past line 19
	sta	ULA_MODE		; line 19, S + 17 us
	LDELAY	CAL_TC			; (free)
	ldy	vcv			; Y = the lead-in mode value, for the palette line

; the palette line (line 29): its two stores are the palette's
palb:	PADN	7
	lda	#PAL8
	sta	ULA_PAL8		; S+4
	lda	#M3
	nop
	sta	ULA_MODE		; S+9
	lda	#PAL9
	sta	ULA_PAL9		; S+13
	nop
	sty	ULA_MODE		; S+17: the lead-in mode (for f = 3, also the band's end)
	lda	#MW			; the window's mode (MODE 1, or MODE 2)
	jmp	(VVECP)			; the lead-in variant, entered at cycle 41 after S
backP:	ldx	vav			; X = the blip's mode value, through the window
	DELAY	CAL_ENT
wtP:	jmp	tA0			; patched (build): the tail that loads the first window line
					; (its blip at S - 3 us of line 30)

; ---- loop 2: the window ---------------------------------------------------------------
; Two gadgets of horizontal-blanking code, gA for even map rows and gB for odd, and
; sixteen blocks of visible-part code, b{P}{k} after line k of a P row (gen_loop2.s):
;   gadget (horizontal blanking): the entering byte (A) and the leaving zero, by the
;     8-byte block 'sta in / lda #0 / sta out'; MODE 3 in the sync; the lead-in mode;
;     the variant (through VJ), which returns to the next block (through VRET);
;   block (the next line's visible part, BLK_LEN cycles): its slice of the next row's
;     preparation -- the other gadget's two addresses (+576, ring-wrapped, from this
;     gadget's), the pattern bytes of the next colour pair, and in B5 the choice of
;     ZB for the next A row's line 7 if its entering cell is LEAKCELL; this gadget's
;     two addresses stepped one byte down their cells (not after line 7); VRET <- the
;     next block;
;   tail (right margin): the next line's entering byte, the blip (X), the jump.
; A row counter in the line-7 blocks arms the exit: one block, chosen per field, has
; its 'sta VRET' turned into 'sta VJ' with VX, so line 199's gadget goes to VX, which
; blackens the palette, leaves MODE 4 and jumps to the bottom of the frame (frame.s).
	.include "gen_loop2.s"

	.include "gen_variants.s"
