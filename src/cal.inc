; cal.inc -- the frame's cycle calibration (2 MHz CPU cycles).
;
; These place the raster lock and balance the fixed-length work's paths against each
; other.  They were tuned against the emulator's I/O log: the soak (test/soak.sh)
; reports where the lock read lands ("lock read h", in 1/16 us of line 0), and
; test/fingerprint.sh with test/fpcompare.py measures the fixed work's length per
; field.  docs/DESIGN.md section 7 describes the procedure.

; ---- the top of the frame (raster.s) ----
	.ifndef	LOCK1
LOCK1 = 0           ; 1 (make LOCK1=1): lock with one read, in line 0 (DESIGN.md 3.1); 0: two
	.endif
CAL_L2    = 72      ; between the two lock reads: the second lands mid line 1
CAL_L1S   = 24      ; LOCK1: the single read this much sooner, inside line 0's fetches
CAL_TA    = 1042    ; free time above the window (LDELAYs), from line 1 to the write on
CAL_TB    = 280     ; line 9; after the strip build (998 cycles, with the leak byte's 38) to the write on line 19;
CAL_TC    = 1235    ; and to the palette line: 2,557 in all, for fixed-length work

; ---- the fixed-length work below the window (frame.s): every path the same length ----
CAL_CP    = 31      ; a commit going right: pad (the directions' edge rows differ)
CAL_CM    = 19      ; a commit going left
CAL_BP    = 11      ; the behind field going right: pad (left is the longer)
CAL_BEH   = 60      ; the behind path, after its edge rows (LDELAY)
CAL_NOC1  = 1200    ; an idle field, in place of the edge rows (four LDELAYs)
CAL_NOC2  = 1200
CAL_NOC3  = 1200
CAL_NOC   = 246
CAL_SPARE = 700     ; frame.s: the fixed work's spare time, as delay (at most 1,296)

; ---- the delay to the next lock (frame_tail): CAL_N64 (+2 in the 313-line field)
; passes of 64 cycles and CAL_REM, after the fixed work ----
CAL_N64   = 1
CAL_REM   = 10

; ---- the bootstrap (init.s, boot_sync) ----
CAL_BTHR  = $594    ; poll count from the RTC flag to display end: fewer = the 313-line field
CAL_BN64  = 109     ; display end -> the first lock read: passes of 64 cycles ...
CAL_BREM  = 0       ; ... and the rest

; ---- loop 2 (gen_loop2.s): the window's gadgets and line blocks ----
; The gadget's writes, from its first store (just after S): MODE 3 at +9 us, the
; lead-in mode at +15, the variant entered at cycle 41 after S (its MODE 1 write at
; +23+u); each line block takes BLK_LEN cycles, so that an iteration is 128.
PAD_W1    = 0       ; after the 8-byte block, to the MODE 3 write
PAD_W2    = 4       ; to the lead-in mode write
PAD_W3    = 3       ; to the variant
BLK_LEN   = 45      ; a line block, from its entry (VRET) to its tail
CAL_ENT   = 41      ; the palette line's handover -> the first window line's tail (the phase)
CAL_V20   = 23      ; the window's variant 0 (no lead-in): as long as the others, given
                    ; this loop's 1 MHz alignment of their MODE 1 write
BLD_IDLE  = 28      ; strip.s: pads the real path's column setup to the idle one's
