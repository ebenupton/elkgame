	.segment "CODE"
; ---- the vertical step: |dy|/2 fine steps, each the class of the look-ahead row that
; the new position makes due -------------------------------------------------------
vstep:	lda	#0
	sta	gch
	lda	dy
	beq	@done
	bmi	@up
	lsr	a
	sta	vcnt
@dl:	lda	wy			; down 2 lines
	clc
	adc	#2
	sta	wy
	lda	wy+1
	adc	#0
	tax
	lda	MAPHI,x
	sta	wy+1
	lda	wy			; the row below the window's last, class (wy & 7)/2
	clc
	adc	#<(H-1+8)
	sta	tmp
	lda	wy+1
	adc	#>(H-1+8)
	tax
	lda	MOD2560H,x
	sta	tmp+1
	jsr	row_of_tmp
	lda	wy
	and	#7
	lsr	a
	sta	gcls
	lda	#1
	sta	gkind
	jsr	group
	dec	vcnt
	bne	@dl
@done:	rts
@up:	eor	#$FF
	clc
	adc	#1
	lsr	a
	sta	vcnt
@ul:	lda	wy			; up 2 lines
	sec
	sbc	#2
	sta	wy
	lda	wy+1
	sbc	#0
	tax
	lda	MAPHI,x
	sta	wy+1
	lda	wy			; the row above the window's first, class 3 - (wy & 7)/2
	sec
	sbc	#8
	sta	tmp
	lda	wy+1
	sbc	#0
	tax
	lda	MAPHI,x
	sta	tmp+1
	jsr	row_of_tmp
	lda	wy
	and	#7
	lsr	a
	eor	#3
	sta	gcls
	lda	#0
	sta	gkind
	jsr	group
	dec	vcnt
	bne	@ul
	rts

; grow <- (tmp, a map scanline) >> 3
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

; ---- a class of a look-ahead row: row grow, class gcls; gkind 0: the row above (span
; mx-14: 14 gap cells, then the window), 1: the row below (span mx: the window, then
; 14 gap cells).  Variable length: only the cells in the span are written. ------------
group:	lda	gkind
	bne	g_k1
	lda	mx
	sec
	sbc	#GAP
	sta	tmp
	lda	mx+1
	sbc	#0
	tax
	lda	MAPHI,x
	sta	tmp+1
	lda	#3+GAP			; zero: relb < 3 + GAP
	sta	gzlo
	sta	gplo			; a whole block of pattern: 3 + GAP <= relb <= 71
	lda	#72
	sta	gphi
	lda	#3			; of zeros: 3 <= relb <= GAP - 1
	sta	gz0
	lda	#GAP
	sta	gz1
	lda	#$FF			; (never >=)
	sta	gzhi
	jmp	g_s
g_k1:	lda	mx
	sta	tmp
	lda	mx+1
	sta	tmp+1
	lda	#0
	sta	gzlo
	lda	#3+WIN_W		; zero: relb >= 3 + WIN_W
	sta	gzhi
	sta	gz0			; a whole block of zeros: 3 + WIN_W <= relb <= 71
	lda	#72
	sta	gz1
	lda	#3			; of pattern: 3 <= relb <= WIN_W - 1
	sta	gplo
	lda	#WIN_W
	sta	gphi
g_s:	; bs = S0 >> 2 (low byte: the hash's index; the map's 640 blocks are 5 periods)
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
	; b = bs + ((gcls - bs) & 3); relb = 4 (b - bs) - (S0 & 3) + 3
	lda	gcls
	sec
	sbc	gb
	and	#3
	tax
	asl	a
	asl	a
	clc
	adc	#3
	sec
	sbc	tmp2
	sta	grel
	txa
	clc
	adc	gb
	sta	gb
	bcc	:+
	inc	gb+1
:	; the first cell's address: 8 x = 32 b, plus the row
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
	lda	ra+1			; mod &5000 (b can be up to 642)
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
	; the row's colour offset and its grid line (line 7 of odd rows is black)
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
	lda	#5
	sta	gbc
g_blk:	ldx	gb
	lda	PERM,x
	clc
	adc	byr
	tax
	lda	PE,x
	sta	ve
	lda	PO,x
	sta	vo
	lda	PEM,x
	sta	vem
	lda	POM,x
	sta	vom
	; a block wholly pattern or wholly zero, with its 32 bytes in one page: the fast way
	lda	grel
	cmp	gplo
	bcc	g_nz
	cmp	gphi
	bcs	g_nz
	lda	vem			; pattern: the first cell has the block's black left column
	sta	pve
	lda	vom
	sta	pvo
	and	gm
	sta	pv7
	lda	#3			; (the values change after the first cell)
	bne	g_fast
g_nz:	cmp	gz0
	bcc	g_slow
	cmp	gz1
	bcs	g_slow
	lda	#0
	sta	pve
	sta	pvo
	sta	pv7
	lda	#$FF			; (they never change)
g_fast:	sta	gsw
	lda	phi
	cmp	pd0+2
	beq	:+
	.repeat	8, i
	sta	.ident(.sprintf("pd%d", i))+2
	.endrep
:	ldx	plo
	ldy	#4
	jmp	pcl
g_slow:	lda	#4
	sta	gcc
g_chr:	lda	grel
	cmp	#3
	bcc	g_skip
	cmp	#75
	bcs	g_skip
	cmp	gzlo
	bcc	g_zero
	cmp	gzhi
	bcs	g_zero
	lda	gcc
	cmp	#4
	beq	g_first
	lda	ve
	ldy	vo
	jmp	g_put
g_first:	lda	vem
	ldy	vom
	jmp	g_put
g_zero:	lda	#0
	tay
g_put:	sta	pve
	sty	pvo
	tya
	and	gm
	sta	pv7
	jsr	putc
	inc	gch
g_skip:	lda	plo			; the next cell (the ring wraps at &8000)
	clc
	adc	#8
	sta	plo
	bcc	:+
	inc	phi
	bpl	:+
	lda	#$30
	sta	phi
:	inc	grel
	dec	gcc
	bne	g_chr
gblk_adv:
	; the class's next block: 12 columns on
	lda	plo
	clc
	adc	#96
	sta	plo
	lda	phi
	adc	#0
	bpl	:+
	sec
	sbc	#$50
:	sta	phi
gblk_ad2:
	lda	grel
	clc
	adc	#12
	sta	grel
	lda	gb
	clc
	adc	#4
	sta	gb
	dec	gbc
	beq	:+
	jmp	g_blk
:	rts

; the cell at (plo, phi): lines 0 2 4 6 <- pve, 1 3 5 <- pvo, 7 <- pv7; the page patch
; is skipped when it can be (variable time: PUTCC is the fixed one)
putc:	lda	phi
	cmp	pc0+2
	beq	pcg
pcp:	.repeat	8, i
	sta	.ident(.sprintf("pc%d", i))+2
	.endrep
pcg:	ldx	plo
	lda	pve
pc0:	sta	a:$FF00,x
pc2:	sta	a:$FF02,x
pc4:	sta	a:$FF04,x
pc6:	sta	a:$FF06,x
	lda	pvo
pc1:	sta	a:$FF01,x
pc3:	sta	a:$FF03,x
pc5:	sta	a:$FF05,x
	lda	pv7
pc7:	sta	a:$FF07,x
	rts

; the fast block: Y cells from X (the page is patched), 8 bytes apart; after the cell
; numbered gsw (counting down from 4) the values become the block's plain ones
pcl:	lda	pve
	.repeat	4, i
	sta	a:$FF00+2*i,x
	.ident(.sprintf("pd%d", 2*i)) = * - 3
	.endrep
	lda	pvo
	.repeat	3, i
	sta	a:$FF01+2*i,x
	.ident(.sprintf("pd%d", 2*i+1)) = * - 3
	.endrep
	lda	pv7
	sta	a:$FF07,x
pd7 = * - 3
	dey
	beq	pclx
	cpy	gsw
	bne	:+
	lda	ve
	sta	pve
	lda	vo
	sta	pvo
	and	gm
	sta	pv7
:	txa
	clc
	adc	#8
	tax
	bcs	:+
	jmp	pcl
:	inc	phi			; the next page (the ring wraps at &8000)
	bpl	:+
	lda	#$30
	sta	phi
:	lda	phi
	.repeat	8, i
	sta	.ident(.sprintf("pd%d", i))+2
	.endrep
	jmp	pcl
pclx:	lda	gch
	clc
	adc	#4
	sta	gch
	lda	grel
	clc
	adc	#4
	sta	grel
	txa				; the class's next block: 12 columns past the last cell + 1
	clc				; (X = the last cell's low byte; phi its page)
	adc	#8+96
	sta	plo
	lda	phi
	adc	#0
	bpl	:+
	sec
	sbc	#$50
:	sta	phi
	jmp	gblk_ad2

