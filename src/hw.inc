; hw.inc -- the ULA's registers and the fixed main-RAM addresses the demo uses.
; (docs/ULA-NOTES.md has the detail of every register.)

; ---- ULA registers ------------------------------------------------------------------
ULA_STAT	= $FE00		; read: interrupt status (bit 2 display end, bit 3 RTC)
ULA_IRQEN	= $FE00		; write: interrupt enables (all off here)
ULA_SA_L	= $FE02		; screen start, address bits 6..8 (in bits 5..7)
ULA_SA_H	= $FE03		; screen start, address bits 9..14 (in bits 0..5)
ULA_PAGE	= $FE05		; ROM paging (bits 0..3), interrupt clears (bits 4..6)
ULA_MODE	= $FE07		; display mode (bits 3..5): takes effect mid-line
; The leak byte.  On a real ULA a CPU write to a ULA register while the ULA is fetching
; for the display takes that video slot, which shows RAM[&7E00 + the register's low
; byte], painted in the new mode, in place of its own byte.  For ULA_MODE that is &7E07:
; every window line's switch to the window's mode (the variant) and its blip show it,
; so the engine keeps it zero: build (strip.s) stores 0 there every field, and when
; gadget A's entering cell is LEAKCELL its line 7 comes from ZB, not VO (vars.s, the
; B5 block in gen_loop2.s).  docs/DESIGN.md, "The leak byte".
LEAK		= ULA_MODE & $7FFF	; &7E07: RAM[&7E07], shown by a mode write's slot
LEAKCELL	= LEAK & $FFF8	; &7E00: its cell, whose line 7 it is
ULA_PAL8	= $FE08		; palette (MODE 1: logical colours 0..3, two registers;
ULA_PAL9	= $FE09		; MODE 2 uses &FE08-&FE0F)

DE_BIT		= $04		; ULA_STAT: display end (line 255 in a graphics mode, 249 in a text one)
RTC_BIT		= $08		; ULA_STAT: the "real-time clock" event (line 99, once a field)

; ---- main RAM -------------------------------------------------------------------------
; The program and its data live in a sideways RAM bank (&8000-&BFFF), whose accesses
; run at 2 MHz; main RAM is touched only where noted.  The screen ring is &3000-&7FFF.
SYNCB		= $0200		; any main-RAM byte: read while the ULA fetches a 20K-mode
				; line, it stalls to S, the end of the fetches (frame_top)
KBD		= $0900		; the keyboard routine (kbd.s: reading the keyboard pages ROM 8
				; over the sideways bank, so it must run from main RAM)
KEYS		= $0A00		; its result: bit 0 left, 1 right, 2 up, 3 down, 4 comma, 5 full stop
KTMP		= $0A01		; (its scratch)
KSPC		= $0A02		; SPACE: non-zero while held
DUMMY		= $2400		; the page an unwanted store goes to: main RAM like the screen,
				; so it takes the same time as a wanted one
