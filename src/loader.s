; loader.s -- the program file, loaded and run at &2000 (*RUN from disc or tape).
;
; Finds a sideways RAM bank: slots 0-7 and 12-15 in turn, skipping any that holds a ROM
; image (a copyright string at (&8007)) and any that does not hold a written byte.
; Copies the 16K image to &8000 in that bank and the keyboard routine to &0900, and
; enters the image at &8000 with the bank's number in A.  If none is found, it says
; so and returns to the OS.  The image never returns: BREAK to leave.
	.setcpu "6502"
OSWRCH	= $FFEE
ROMSEL	= $FE05
ROMCPY	= $F4
ZP	= $70

	.segment "LOADER"
start:	sei
	lda	ROMCPY
	sta	oldrom
	ldx	#0
@next:	lda	BANKS,x
	bmi	@none
	sta	cand
	jsr	page
	; a ROM image (copyright string at (&8007)) is left alone
	ldy	$8007
	lda	$8000,y
	bne	@try
	lda	$8001,y
	cmp	#'('
	bne	@try
	lda	$8002,y
	cmp	#'C'
	bne	@try
	beq	@skip
@try:	lda	$BFFF
	eor	#$FF
	sta	$BFFF
	cmp	$BFFF
	php
	eor	#$FF
	sta	$BFFF
	plp
	beq	@found
@skip:	inx
	bne	@next
@none:	lda	oldrom
	jsr	page
	cli
	ldx	#0
@msg:	lda	nomsg,x
	beq	@ret
	jsr	OSWRCH
	inx
	bne	@msg
@ret:	rts

@found:	; copy the image to &8000 and the keyboard routine to &0900
	lda	#<IMG
	sta	ZP
	lda	#>IMG
	sta	ZP+1
	lda	#0
	sta	ZP+2
	lda	#$80
	sta	ZP+3
	ldx	#>(IMGLEN+255)
	ldy	#0
@cp:	lda	(ZP),y
	sta	(ZP+2),y
	iny
	bne	@cp
	inc	ZP+1
	inc	ZP+3
	dex
	bne	@cp
	ldy	#0
@ck:	lda	KIMG,y
	sta	$0900,y
	iny
	bne	@ck
	lda	cand
	jmp	$8000

; page bank A in (by way of 12, in case the current slot is one of 8-11), keeping the
; OS's copy of the paged slot (&F4) up to date
page:	pha
	lda	#$0C
	sta	ROMSEL
	pla
	sta	ROMCPY
	sta	ROMSEL
	rts

BANKS:	.byte	0, 1, 2, 3, 4, 5, 6, 7, 12, 13, 14, 15, $FF
oldrom:	.byte	0
cand:	.byte	0
nomsg:	.byte	13, 10, "No free sideways RAM bank found.", 13, 10, 0

	.align	256
IMG:	.incbin	"elk.bin"
IMGLEN	= * - IMG
	.align	256
KIMG:	.incbin	"kbd.bin"
