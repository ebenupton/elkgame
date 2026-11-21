; elkscroll.s -- a 224 x 170-pixel MODE 1 playfield that scrolls smoothly in both
; directions at 50 Hz on an Acorn Electron with one bank of sideways RAM.
;
; This file is the assembly's root: it pulls in the configuration and every module in
; the order that fixes the binary's layout.  docs/DESIGN.md is the full account; in
; brief:
;
; The window is 56 MODE 1 characters x 170 scanlines at screen character 16 and line
; 30, single-buffered, in the ULA's 20K screen ring (&3000-&7FFF) laid out as rows of
; 72 characters (576 bytes) -- not the 80 the ULA displays -- so that a coarse scroll
; is a change of screen start by 8 bytes and a vertical one by 576.
;
;   Horizontal fine scroll (one character, 4 pixels): every window scanline starts in
;   a 40-column mode for t us, then switches to MODE 1 (raster.s, the "lead-in"); the
;   line's address counter falls t characters behind.  The column that enters on a
;   coarse step is drawn into the ring by the beam-raced "strip" (strip.s): one byte of
;   the entering column and one zero of the leaving column on every window line, in
;   that line's horizontal blanking.
;
;   Vertical fine scroll (two scanlines): 0-3 rows of 10-line text mode (MODE 6) at
;   the top of the frame push the rows below down.  The row about to come into view is drawn a
;   quarter at a time, one quarter per 2-line step (notch.s), so every step costs the
;   same.
;
; Interrupts are off.  A field is: the raster lock (two stalled main-RAM reads on lines
; 0 and 1, MODE 1 or MODE 3); the lines above the window, MODE 4 or MODE 6 (40-column
; modes: the CPU uncontended), with the strip build and free fixed-length time; the
; palette line; the 169 window iterations of 128 cycles each; then, below the window
; (MODE 4), variable-length work (keyboard, trajectory, the vertical step's plan) that
; must finish before display end (line 255), and fixed-length work (the vertical step's
; stores, the column step's edge rows, the next field's display parameters) and a
; counted delay back to the lock (frame.s).
;
; Build: make (see the Makefile for the options).  Generated files (tools/gen.py):
; config.inc, gen_tables.s, gen_variants.s, gen_loop2.s.

	.setcpu	"6502"
	.include "config.inc"		; geometry, mode values, palette (generated)
	.include "cal.inc"		; the cycle calibration of the frame
	.include "hw.inc"		; ULA registers, fixed main-RAM addresses
	.include "macros.inc"		; cycle-exact delays and the cell writers

	.include "raster.s"		; the frame top, the scanline loop (with the generated window code)
	.include "init.s"		; start-up, the first picture, the bootstrap raster sync
	.include "logic.s"		; the trajectory: script, random walk, keys
	.include "notch.s"		; the vertical step: a quarter of a look-ahead row
	.include "colop.s"		; a column step's edge rows
	.include "strip.s"		; building the beam-raced strip for the next field
	.include "frame.s"		; the work below the window and the delay to the next lock
	.include "display.s"		; the next field's screen start, lead-in and band
	.include "tables.s"		; generated and hand-written tables
	.include "vars.s"		; variables (in the sideways RAM bank)
	.include "kbd.s"		; the keyboard scan (main RAM)
