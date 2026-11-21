; cal.inc -- the frame's cycle calibration, in 2 MHz CPU cycles.
;
; These constants place the raster lock and make the fixed-length work's paths equal in
; length.  They were tuned against the emulator's I/O log: the soak (test/soak.sh)
; reports where the lock read is issued ("lock read h", in 1/16 us of line 0; today
; h 152-488), and test/fingerprint.sh with test/fpcompare.py measures the fixed work's
; length field by field.  docs/DESIGN.md, "Timing discipline and calibration",
; describes the procedure.

; ---- the top of the frame (raster.s): delays a game can replace with its own work ----
CAL_TA    = 1170    ; from the switch on line 0 (S + 3 us) to the write on line 9 (S + 17 us)
CAL_TB    = 280     ; after the strip build (998 cycles, about 38 of them the leak byte's) to line 19's write
CAL_TC    = 1235    ; from line 19 to the palette line: 2,685 cycles in all

; ---- the fixed-length work below the window (frame.s): every path the same length ----
CAL_CP    = 31      ; a commit going right: pad (the two directions' edge rows differ)
CAL_CM    = 19      ; a commit going left: pad
CAL_BP    = 11      ; the behind field going right: pad (going left is the longer)
CAL_BEH   = 60      ; the behind path, after its edge rows (LDELAY)
CAL_NOC1  = 1200    ; an idle field, in place of the edge rows: four LDELAYs
CAL_NOC2  = 1200
CAL_NOC3  = 1200
CAL_NOC   = 246
CAL_SPARE = 676     ; frame.s: the fixed work's spare time, as an LDELAY (at most 1,300)

; ---- the delay to the next lock (frame_tail): CAL_N64 passes of 64 cycles (two more
; in the 313-line field) and CAL_REM, after the fixed work ----
CAL_N64   = 1
CAL_REM   = 10

; ---- the bootstrap (init.s, boot_sync) ----
CAL_BTHR  = $594    ; polls from the RTC flag to display end: fewer means the 313-line field
CAL_BN64  = 109     ; from display end to the first lock read: passes of 64 cycles ...
CAL_BREM  = 0       ; ... and the rest

; ---- loop 2 (gen_loop2.s): the window's gadgets and line blocks ----
; A gadget's writes, in us after S: its two stores just after S, MODE 3 at +9, the
; lead-in mode at +15; the variant is entered at cycle 41 after S (its MODE 1 write at
; +23+u).  Each line block takes BLK_LEN cycles, so that an iteration is 128.
PAD_W1    = 0       ; after the 8-byte block, to the MODE 3 write
PAD_W2    = 4       ; to the lead-in mode write
PAD_W3    = 3       ; to the variant
BLK_LEN   = 45      ; a line block, from its entry (through VRET) to its tail
CAL_ENT   = 41      ; the palette line's return (backP) -> the first window line's tail: the phase
CAL_V20   = 23      ; the window's variant 0 (no write): as long as the others, given
                    ; this loop's 1 MHz alignment of their MODE 1 write
BLD_IDLE  = 28      ; strip.s: pads the real path's column setup to the idle one's
