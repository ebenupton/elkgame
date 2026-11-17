; cal.inc -- the frame's cycle calibration (2 MHz CPU cycles).
;
; These place the raster lock and balance the fixed-length work's paths against each
; other.  They were tuned against the emulator's I/O log: the soak (test/soak.sh)
; reports where the lock read lands ("lock read h", in 1/16 us of line 0), and
; test/fingerprint.sh with test/fpcompare.py measures the fixed work's length per
; field.  docs/DESIGN.md section 7 describes the procedure.

; ---- the top of the frame (raster.s) ----
CAL_L2    = 66      ; between the two lock reads: the second lands mid line 1
CAL_PRE   = 98      ; lock -> the first iteration (entered at S - 3 us)
CAL_PREP  = 2       ; extra, when the first iteration is the palette line's

; ---- the fixed-length work below the window (frame.s): every path the same length ----
CAL_CP    = 32      ; a commit going right: pad (the directions' edge rows differ)
CAL_CM    = 20      ; a commit going left
CAL_BP    = 11      ; the behind field going right: pad (left is the longer)
CAL_BEH   = 62      ; the behind path, after its edge rows (LDELAY)
CAL_NOC1  = 1200    ; an idle field, in place of the edge rows (four LDELAYs)
CAL_NOC2  = 1200
CAL_NOC3  = 1200
CAL_NOC   = 248
CAL_BI1   = 1000    ; an idle strip build, padded to the real one's length (strip.s)
CAL_BI2   = 1000
CAL_BI3   = 706

; ---- the delay to the next lock (frame_tail): CAL_N64 (+2 in the 313-line field)
; passes of 64 cycles and CAL_REM, after the fixed work ----
CAL_N64   = 5
CAL_REM   = 138

; ---- the bootstrap (init.s, boot_sync) ----
CAL_BTHR  = $594    ; poll count from the RTC flag to display end: fewer = the 313-line field
CAL_BN64  = 109     ; display end -> the first lock read: passes of 64 cycles ...
CAL_BREM  = 0       ; ... and the rest
