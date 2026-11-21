; notch.s -- the vertical step: a look-ahead row drawn a class at a time (docs/DESIGN.md,
; "A new row: the notch").
;
; The rows just above and just below the window (the look-ahead rows) are drawn in
; four classes of map columns: class = (column >> 2) & 3, a 4-character block of the
; map.  With phase k = (wy & 7) / 2, a cell of the row below is required to be right
; iff its class <= k, and a cell of the row above iff its class <= 3 - k.  So the row
; below is complete just as it comes into view (k = 3), and so is the row above (k = 0).
; A 2-line step makes exactly one (row, class) newly due, and draws just that.  colop
; uses the same rule for a column step's look-ahead cells.
;
; Timing: the drawing is split across the bottom of the frame (frame.s):
;   vstep, in the variable-length work (before the display-end poll): moves wy and has
;     nprep fill a plan -- the class's five blocks' addresses (NBL, NBH) and each of
;     their twenty cells' three bytes (NTE even lines, NTO lines 1, 3, 5, NT7 line 7) --
;     or, with no step this field, nnull aims the plan at the dummy page;
;   nstore, fixed length, the first of the fixed-length work after display end: writes
;     the plan's twenty cells in the same time every field, step or not.
; ndraw (both at once) is for init's first picture.
;
; Every cell of the five blocks is written.  The span (the row's 72 cells: the window's
; WIN_W and the gap's GAP) holds pattern in the window's columns and zero in the gap's;
; the few cells of the first and last blocks that fall outside it get zero, which is
; right or harmless: they are the neighbouring window row's gap cells (always zero) or
; cells of a row two away from the window (not shown, and drawn class by class before
; they are due).

	.assert	DYMAX = 2, error, "one notch a field: vstep prepares a single plan"

; ---- vstep: move wy by dy (0 or +-2 lines) and prepare the step's plan --------------
; Variable length.  Also clears gch (the cells drawn this field, for the soak).
	.segment "VCODE"
vstep:	lda	#0
	sta	gch
	lda	dy
	bne	:+
	jmp	nnull			; no step: the plan aims at the dummy page
:	bmi	@up
	lda	wy			; down 2 lines (mod 2560)
	clc
	adc	#2
	sta	wy
	lda	wy+1
	adc	#0
	tax
	lda	MAPHI,x
	sta	wy+1
	lda	wy			; the row below the window's last: scanline wy + H - 1 + 8
	clc
	adc	#<(H-1+8)
	sta	tmp
	lda	wy+1
	adc	#>(H-1+8)
	tax
	lda	MOD2560H,x
	sta	tmp+1
	jsr	row_of_tmp
	lda	wy			; class k = (wy & 7) / 2, now due
	and	#7
	lsr	a
	sta	gcls
	lda	#1			; drawn as the row below
	sta	gkind
	jmp	nprep
@up:	lda	wy			; up 2 lines (mod 2560)
	sec
	sbc	#2
	sta	wy
	lda	wy+1
	sbc	#0
	tax
	lda	MAPHI,x
	sta	wy+1
	lda	wy			; the row above the window's first: scanline wy - 8
	sec
	sbc	#8
	sta	tmp
	lda	wy+1
	sbc	#0
	tax
	lda	MAPHI,x
	sta	tmp+1
	jsr	row_of_tmp
	lda	wy			; class 3 - k, now due
	and	#7
	lsr	a
	eor	#3
	sta	gcls
	lda	#0			; drawn as the row above
	sta	gkind
	jmp	nprep

; ---- row_of_tmp: grow <- tmp >> 3, the map row of scanline tmp (also build's) --------
row_of_tmp:
	lda	tmp+1
	sta	grow+1
	lda	tmp
	lsr	grow+1
	ror	a
	lsr	grow+1
	ror	a
	lsr	grow+1
	ror	a
	sta	grow
	rts

; ---- nnull: a plan that changes nothing: every block at the dummy page's start (the
; cells' bytes are left as they are; they land on the dummy page) --------------------
nnull:	ldx	#4
@l:	lda	#>DUMMY
	sta	NBH,x
	lda	#0
	sta	NBL,x
	dex
	bpl	@l
	rts

; ---- nprep: the plan for one class of a look-ahead row --------------------------------
; Row grow, class gcls.  gkind 0: drawn as the row above the window, whose span is GAP
; gap cells then the window's WIN_W, from column mx - GAP; gkind 1: as the row below,
; the window's WIN_W then GAP gap cells, from mx.  A cell's bytes are its block's
; pattern ANDed with NSPAN (by gkind and the cell's column relative to the span): $FF in
; the span's window part, else 0.  Variable length (about 1,300 cycles by its
; instructions; it runs before the display-end poll, so the time is not counted).
nprep:	lda	#20
	sta	gch
	lda	gkind			; the span's first column S0 (mod 2560)
	bne	@k1
	lda	mx
	sec
	sbc	#GAP
	sta	tmp
	lda	mx+1
	sbc	#0
	tax
	lda	MAPHI,x
	sta	tmp+1
	jmp	@s
@k1:	lda	mx
	sta	tmp
	lda	mx+1
	sta	tmp+1
@s:	; bs = S0 >> 2, the span's first block (its low byte is the hash's index: the
	; map's 640 blocks are 5 of the hash's periods)
	lda	tmp
	and	#3
	sta	tmp2			; S0 & 3
	lda	tmp+1
	sta	gb+1
	lda	tmp
	lsr	gb+1
	ror	a
	lsr	gb+1
	ror	a
	sta	gb			; bs
	; the class's first block b = bs + ((gcls - bs) & 3); its first cell's NSPAN index
	; grel = 4 (b - bs) - (S0 & 3) + 3, plus 96 for gkind 1 (NSPOFF)
	lda	gcls
	sec
	sbc	gb
	and	#3
	tax
	asl	a
	asl	a
	ldy	gkind
	clc
	adc	NSPOFF,y
	sec
	sbc	tmp2
	sta	grel
	txa
	clc
	adc	gb
	sta	gb
	bcc	:+
	inc	gb+1
:	; the first block's address: 32 b (8 bytes x 4 cells), plus the row (addrow)
	lda	gb+1
	sta	ra+1
	lda	gb
	asl	a
	rol	ra+1
	asl	a
	rol	ra+1
	asl	a
	rol	ra+1
	asl	a
	rol	ra+1
	asl	a
	rol	ra+1
	sta	ra
	lda	ra+1			; mod &5000 (b can be up to 642: 32 b past &5000)
	cmp	#$50
	bcc	:+
	sbc	#$50
	sta	ra+1
:	lda	grow
	sta	yt
	lda	grow+1
	sta	yt_hi
	jsr	addrow
	sta	plo
	sty	phi
	; the row's colour term (its block row, grow >> 1) and its grid line: gm = 0 for
	; an odd row, whose line 7 is the blocks' black bottom line, else $FF
	lda	grow+1
	lsr	a
	lda	grow
	ror	a
	sta	byr
	lda	grow
	and	#1
	sec
	sbc	#1
	sta	gm
	ldy	grel			; Y: the cell's NSPAN index
	.repeat	5, b			; the five blocks (b), unrolled
	lda	plo			; the block's address
	sta	NBL+b
	lda	phi
	sta	NBH+b
	ldx	gb			; X: its colours, PERM[block] + block row
	lda	PERM,x
	clc
	adc	byr
	tax
	lda	PEM,x			; the first cell: a block's first column, its left pixel black
	and	NSPAN,y
	sta	NTE+4*b
	lda	POM,x
	and	NSPAN,y
	sta	NTO+4*b
	and	gm
	sta	NT7+4*b
	.repeat	3, c			; the other three cells
	iny
	lda	PE,x
	and	NSPAN,y
	sta	NTE+4*b+1+c
	lda	PO,x
	and	NSPAN,y
	sta	NTO+4*b+1+c
	and	gm
	sta	NT7+4*b+1+c
	.endrep
	.if	b < 4			; on to the class's next block: 16 columns on (NSPAN index
	tya				;   +16 in all) ...
	clc
	adc	#13
	tay
	lda	gb
	clc
	adc	#4
	sta	gb
	lda	plo			; ... 16 cells (128 bytes) on, back into the ring
	clc
	adc	#128
	sta	plo
	lda	phi
	adc	#0
	tax
	lda	WRAPHI,x
	sta	phi
	.endif
	.endrep
	rts

; NSPAN, by a cell's column relative to the span + 3 (at least 0: a class's first cell
; is at most 3 before the span), plus 96 for gkind 1: $FF in the span's window part
; (gkind 0: GAP .. 71; gkind 1: 0 .. WIN_W - 1), else 0.  The index within a kind is at
; most 3 + 12 + 4 x 16 + 3 = 82.
NSPOFF:	.byte	3, 3+96			; by gkind: the first cell's index, less 4 (b - bs) - (S0 & 3)
NSPAN:	.repeat	96, i
	.byte	<(((i >= 3+GAP) && (i < 3+72)) * $FF)
	.endrep
	.repeat	96, i
	.byte	<(((i >= 3) && (i < 3+WIN_W)) * $FF)
	.endrep

; ---- nstore: write the plan's twenty cells (fixed length) -----------------------------
; Five blocks, each four cells (32 bytes, 32-aligned since a ring row is 576 = 18 x 32
; bytes: never across a page), each cell eight stores.  The same time every field,
; whether the plan is real or the dummy page's (about 2,120 cycles, frame.s: the stores
; are main-RAM writes, each waiting for a 1 MHz slot).  Its own page (NSTORE), so that
; no branch or indexed access crosses one.
	.segment "NSTORE"
nstore:	ldy	#0			; Y: the cell (0..19), the plan's index
	sty	gbc			; the block (0..4)
@blk:	ldx	gbc			; the block's page into the eight stores
	lda	NBH,x
	sta	@s0+2
	sta	@s1+2
	sta	@s2+2
	sta	@s3+2
	sta	@s4+2
	sta	@s5+2
	sta	@s6+2
	sta	@s7+2
	lda	NBL,x			; X: the cell's low byte in that page
	tax
@cell:	lda	NTE,y
@s0:	sta	$FF00,x
@s2:	sta	$FF02,x
@s4:	sta	$FF04,x
@s6:	sta	$FF06,x
	lda	NTO,y
@s1:	sta	$FF01,x
@s3:	sta	$FF03,x
@s5:	sta	$FF05,x
	lda	NT7,y
@s7:	sta	$FF07,x
	iny
	txa
	clc
	adc	#8
	tax
	and	#31			; four cells: back at a 32-byte boundary
	bne	@cell
	inc	gbc
	lda	gbc
	cmp	#5
	bne	@blk
	.assert	>@blk = >*, error, "nstore's loops must not cross a page"
	rts

; ---- ndraw: one class of a row, planned and stored at once (init's first picture) ----
	.segment "VCODE"
ndraw:	jsr	nprep
	jmp	nstore
