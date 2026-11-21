# Acorn Electron ULA: behaviour notes for the raster-timed scroll engine

> **About this document.** These notes were compiled while the engine was being
> developed, from the HDL, captures, emulators, manuals and forum threads listed in
> section 0, before any program ran on a real Electron. They are reproduced as
> written. "Local copy" paths, `refs/...` and `../...` references are to the original
> research workspace and are not part of this repository. Section 11 refers to earlier
> versions of the scroll test: a 40-character window, then 50 and 58 characters at
> other screen positions. Section 13 lists the patches made to Clock Signal; they are
> on the fork's `elk-headless` branch (`emu/clk`). Section 15, added afterwards,
> records what hardware probes later showed about the real ULA.

Compiled 2026-11-12. Everything here is cited. Where a statement is my own inference
it is marked **[inference]**; where the sources disagree, or none of them pins a point down,
it is marked **[uncertain]**.

## 0. Sources and conventions

| Tag | Source | Revision read | Local copy |
|---|---|---|---|
| FPGA | hoglet67/ElectronFpga, `src/common/ElectronULA.vhd` (David Banks). The only ULA HDL in the repo; it has no Verilog ULA (`expansion_rom.v` and `qpi_flash*.v` are ROM and flash glue) | `db09714` (2025-05-12); the ULA file was last changed in `af6c24e` (2020-07-23) | `refs/ElectronFpga/` |
| CAP | Real-ULA logic-analyser captures in the same repo, `timings/{ferranti,synertek}_ula/run_mode{4,6}[_i].{bin,log}`: 16 MHz samples, bit0=csync, bit1=IRQ, bit2=blue (`timings/analyze.c`) | `db09714` | same |
| JAM | moogway82/JamSoftElectronULA, `Software/JamSoftElectronULA.vhd`: an iCE40 plug-in replacement for the real chip that drives the real 4164 DRAMs | `db32c85` (2026-11-06) | `refs/JamSoftElectronULA/` |
| CLK | Clock Signal: `Machines/Acorn/Electron/{Video.cpp,Video.hpp,Electron.cpp}` | `096de57` (2026-07-28) | `emu/clk` (the fork; upstream at this commit) |
| MAME | mamedev/mame `src/mame/acorn/electron_ula.{cpp,h}`, `electron.cpp` | master, 2026-11-12 | `refs/mame/` |
| AUG | *Acorn Electron Advanced User Guide*, chs 14–15 (scan; text pulled out with PDFKit) | rigpix.com PDF | `refs/electron_aug/` (`aug_extracted_text.txt`) |
| SD | StarDot threads t=20004 (both pages), t=16962 (all 3 pages), t=12608, t=11198 | fetched 2026-11-12 | `refs/stardot/*.txt` |
| BOD | David Boddie, "The Acorn Electron ULA" (design notes for a re-implementation; not authoritative). The live hg server now returns 401; this is the 2021 Wayback copy | rev `89b5767d944d` | `refs/boddie_ULA/` |

Not obtained:
- Hicks' (Gary's) 2019 ULA model, which hoglet calls "likely to be more faithful" (SD p279838). I couldn't find it.
- An Acorn ULA specification document. None found.
- The Electron Service Manual. The download came back empty.
- acorn.huininga.nl. The site is a JavaScript-only index, so I used BOD (search hits for "The Acorn Electron ULA" all point there).

**Coordinates used throughout.**
- `h` = FPGA/JAM `h_count`, in 16 MHz ticks, 0..1023 per 64 µs line. h=0 is the first pixel of the active line: FPGA outputs pixel data from `h_count1`, which is `h_count` delayed one tick to match the RAM register, so FPGA pixel output lags `h` by about 1–2 ticks.
- `v` = `v_count`. v=0 is the first displayed line of the field.
- A 2 MHz CPU cycle is 8 ticks; a 1 MHz cycle is 16 ticks.
- **S** = the instant a CPU RAM access that was stalled by MODE 0–3 video fetch completes (the end of its stretched φ2). Section 6 shows S always falls on a 1 MHz "slot" boundary. Every CPU-side window in this document is given relative to S, because that is the only reference the program can observe, and because expressing it that way removes the main model difference (the CPU/video clock phase).

---

## 1. Horizontal and vertical timing, sync positions

**Behaviour (FPGA)**
- Line = 1024 ticks (`h_total`=1023).
- Active pixels: h=0..639 (`h_active`=640).
- hsync: from h_count1=768 to 832 (64 ticks = 4 µs).
- Field: `v_total`=311 when `field`='0' (312 lines) and 312 when `field`='1' (313 lines).
- vsync starts at v=274: at h=0 in field 0, at h=512 in field 1.

Citation: ElectronULA.vhd L402–454 (constants), L924–940 (counters), L1135–1157 (vsync/hsync). The comment at L416–420 says the real ULA puts vsync at lines 281→283/4 and that the FPGA moved it 7 lines earlier, "transparent to software".

**Real chip (CAP), Ferranti MODE 4**
- Blue is active for exactly 640 ticks.
- csync falls 766 ticks after the first blue pixel and stays low for 64 ticks.
- The next line's pixels start 258 ticks after the csync falling edge.
- Line = 1024 ticks; frame = 640 000 ticks = 625 lines.
- vsync is 312.5 lines apart. It starts on line 281: at about h=−16 in one field, about h=496 in the other.

(Measured with a script over `timings/ferranti_ula/run_mode4.bin`; the vsync figures are from `run_mode4.log`.) So real hsync begins at h≈766 relative to visible pixels. The FPGA has 768 (with its 1-tick pixel pipeline, ≈767). This is a 1–2 tick difference, irrelevant to software.

| | FPGA | JAM | CLK | MAME |
|---|---|---|---|---|
| line / active / hsync | 1024 / 0..639 / 768–832 | same constants, L124–128 | same, Video.hpp L153–157, at 8-tick granularity | 1024 / 640 (`set_raw(16MHz,1024,0,640,312,0,256)`, electron.cpp L634); no hsync modelled |
| vsync line | 274 (real: 281) | 274 | 274 | n/a |

---

## 2. Field alternation (interlace), field lengths

**Behaviour.** The real ULA is always interlaced:
- Fields alternate between 312 and 313 lines.
- The RTC event is 312.5 lines apart from field to field.
- The display-end event is 312 then 313 lines apart.

CAP: every log shows `frame length: 640000 (625 lines)`, Odd/Even vsync exactly 320 000 ticks apart, display-end interrupts 319 488 ticks (312 lines) then 320 512 (313 lines) apart, and RTC interrupts exactly 320 000 apart. This holds for both Ferranti and Synertek parts, in MODE 4 and MODE 6. The `_i` and non-`_i` runs are identical, so software has no non-interlaced option.

**FPGA model.**
- `field` toggles at the end of each field only when the board video mode is `"01"` (L942–951).
- `field=0`: 312 lines (`v_total`=311); RTC at the start of line 99; vsync starts at the start of the line.
- `field=1`: 313 lines; RTC at mid-line; vsync starts at mid-line (L428–434, L1135–1151, L1168).

**Divergence in the FPGA as shipped.** Its default video mode is `"00"`: the ULA comment at L326–329 says "mode 00 – RGB/s @ 50Hz non-interlaced", and `ElectronULA_max10.vhd` L642 and `ElectronUla_duo.vhd` L210 have `mode_init => "00"`. In that mode every field is 312 lines and the RTC always fires at h=0. To match a real Electron, select Ctrl+Caps+2 ("RGB interlaced", L758–761). Note that `ElectronFpga_core.vhd` L77–78 contradicts the ULA (it says 00=interlaced); the ULA file is what actually controls this.

| | FPGA | JAM | CLK | MAME |
|---|---|---|---|---|
| alternation | only in video mode 01 (default 00 = always 312) | always toggles (L942–943), 311/312 (L883–884) | always toggles (`field_ = !field_`, Video.cpp L232); `v_total()` 311/312 (hpp L178–180) | **none**: 312 lines every field (electron.cpp L634; electron_ula.cpp L9 TODO "interlaced video with 312.5 lines") |

---

## 3. Interrupt events: display end and RTC

**Behaviour (FPGA)**
- **Display end:** at h_count1 = `hsync_start` (768) on v=255 if the mode is graphics *at that tick*, or on v=249 if it is text (L1161–1165).
- **RTC:** on v=99, at h_count1=0 in field 0 or 512 in field 1 (L1168–1172).

Both are synchronised into the 16 MHz domain with two flops and an edge detect before setting `isr(2)`/`isr(3)` (L573–601), so the flags are visible about 3–4 ticks after the event.

The flags in `isr` are set whatever `ier` says. A read of &FE00 returns `'1' & isr(6..2) & power_on_reset & master_irq` (L537), so polling works with the interrupt enables all zero. The flags are cleared only by writing &FE05 with bit 4 (display end), bit 5 (RTC) or bit 6 (high tone) set (L815–822).

**Real chip (CAP), relative to the first blue pixel of the line**

| ULA | Display end | RTC, 312-line field | RTC, 313-line field |
|---|---|---|---|
| Ferranti | line 255, h=767 (1 tick after csync falls) | line 98, h=1009 (i.e. 15 ticks *before* line 99's first pixel) | line 99, h=497 |
| Synertek | same ±1 tick | 1–2 ticks earlier than Ferranti | 1–2 ticks earlier than Ferranti |

The RTC field is identified by `run_mode4.log`, where the even-field RTC is 312.5 lines after the odd one. MODE 6 runs show display end at line 249, h=767 (`run_mode6.log`: `irq at 255743 line 250`).

So relative to the FPGA, the real RTC fires about 14 ticks (≈0.9 µs) earlier with respect to display end: real DE−RTC = 156 lines + 782 ticks, FPGA = 156 lines + 768. **[uncertain which edge moves; for software only the ~1 µs matters.]**

| | FPGA | JAM | CLK | MAME |
|---|---|---|---|---|
| DE line/position | 255 or 249 by current mode, h=768 | same (L1218–1222) | same (Video.cpp L211), seen at the end of the 2 MHz cycle containing h=768 | **line 256 or 250 at h=0** (≈16 µs late), using the mode at that moment (electron_ula.cpp L640–651) |
| RTC | v=99, h=0 or 512 | same (L1225–1230) | same (L208) | **line 100, h=0, every field** (L640) |
| flag set regardless of enable | yes | yes | yes (`interrupt_status_`) | yes |
| clear via &FE05 bits 4–6 | yes, and the same write also pages (§10) | yes, and pages | yes, but **does not page** (Electron.cpp L317–324) | yes, and pages |

---

## 4. Screen start, row (QSTART) register, line address counter

**Behaviour (FPGA).** The registers hold A14..A6 only:
- `screen_base(14 downto 6)` (L123); &FE02 bits 7..5 → A8..A6 (L801–802); &FE03 bits 5..0 → A14..A9 (L803–804).
- `row_addr` is `(14 downto 6)` (L917). The byte counter `byte_addr` is `(14 downto 3)`, one unit per 8-byte character cell (L919). The final RAM address is `byte_addr & char_row(2..0)` (L1020).

The sequence through a field:
1. **Field start** (h=1023 on the last line): `row_addr := screen_base`, `byte_addr := screen_base & "000"` (L986–989). Screen start is consulted only here (also SD p279969: "loaded once at the start of each field (… ADDINT …). This seems pretty definitive").
2. **During hsync** (hsync_int='0'), if `last_line`='1': `row_addr := byte_addr(14 downto 6)`. This is a transparent latch, so it is the value at the end of hsync that counts (L993–995; commit `af6c24e` "row_addr (qstart on schematics) is a transparent latch").
3. **During hsync**, if `last_line`='0': `byte_addr := row_addr & "000"` (L999–1001).
4. So on the *last line of a row*, `byte_addr` is **not** reloaded. The next line (line 0 of the next row) continues from the counter, keeping its A5..A3 bits. Lines 1..7 of that row reload from `row_addr`, whose A5..A3 are zero.

This is exactly hoglet's description (SD p280080, 2020-07-23):

> "When the ends of lines 0..6 are reached, the video address counter is re-loaded from the internal "start of row" register (QSTART on the Schematics)… The start of row register only implements bits 14..6, so bits 3..5 of the video address are re-initialzed with zero … When the end of line 7 is reached, the video address counter would normally point to the start of the next row. So it's value is retained as the video address for line 8, and it is also writen back to the "start of row" register as the start of the next row. But again, only bits 14..6 are used. So only line 8 is affected in any way by eating extra bytes, and the effect only lasts for that one line."

**Real-hardware evidence.** 0xC0DE's experiment that "ate" extra bytes at the end of lines produced, on a real Electron, "1 in every 8 scanlines … displaced" (SD p280011). The FPGA/hoglet model predicts exactly that. JAM's model (no line displaced) and CLK's model (every following row displaced) do not.

| | FPGA | JAM | CLK | MAME |
|---|---|---|---|---|
| row register width | A14..A6 | A14..A6 (`row_addr := byte_addr(14 downto 6)`, L999–1001) | **all bits**: `row_addr_ = byte_addr_` (Video.cpp L103) | no row register; adds a fixed 0x278 or 0x138 at the end of each row (electron_ula.cpp L620–627) |
| when captured | during hsync on the last line | **at h=640** on the last line (L999) | during hsync on the last line (L101–107), i.e. FPGA structure | n/a |
| byte counter on the last line | kept, so line 0 of the next row starts **untruncated** | **reset at h=1016 on every line** (L1006–1022) to the just-truncated `row_addr`, so line 0 starts **truncated** | kept, and `row_addr_` is untruncated too, so the next row (all 8 lines) starts untruncated | n/a |
| screen_base register | A14..A6 | stores &FE02 b7..2 → A8..A3 (L725–726) but uses only A14..A6 outside Jafa MODE 7 (L987) | A14..A6 (L283–291) | A14..A6 |

---

## 5. Character-row counter, last line, graphics vs text

**Behaviour (FPGA).**
- `char_row` (4 bits) increments on the *trailing* edge of hsync, at h_count1=832, seen about 2 ticks later.
- It resets to 0 at that edge if `last_line`, or on the field's last line (L953–965).
- `last_line` is a registered signal: (graphics and `char_row`=7) or (text and `char_row`=9) (L974–979).
- In any graphics mode, bit 3 is held reset immediately, at any time, not only at hsync (L966–972, commit `a6ce79a`; from the Ferranti schematic sheet 7, SD p279969).
- Lines with `char_row`≥8 (the 2 spacer lines of MODE 3/6) are forced to black and carry no contention (L1024–1029).

hoglet's two-point summary (SD p279832/p279969): the start of hsync decides the row-address advance; the end of hsync decides the row counter reset.

| | FPGA | JAM | CLK | MAME |
|---|---|---|---|---|
| increment edge | hsync end | hsync end (L949–959) | h==832 (L82–88) | per scanline, from the mode at render time |
| bit-3 reset in graphics | immediate (except on the edge tick) | same (L960–966) | `char_row_ &= 7` every cycle (L91–93) | no |
| last_line | registered | registered (L970–974) | combinational (`last_line()`, hpp L182) | `mode_max_ra` per line |

---

## 6. CPU clock: 2 MHz / 1 MHz slots, contention, stall release

**Behaviour (FPGA, "turbo" 01 = stock Electron, L1245–1262)**
- `clken_counter` is a free-running 4-bit counter at 16 MHz. CPU cycles end (`cpu_clken`) when `clken_counter(2..0)="111"` and the clock is not stopped, i.e. every 8 ticks.
- RAM (A15=0) and I/O accesses stop the clock: at `clken_counter(2..0)="110"`, which is 6 ticks into the CPU cycle, `clk_stopped` is set.
- The clock is released only at `clken_counter="1110"` and only if not (RAM access and `contention2`).
- `contention` is '1' on active pixels (h_count1<640, v<256 graphics or v<250 text, `char_row`<8) **when not a 40-column mode** (L1024–1033). It passes through two sync flops (L1222–1223).

Consequences:
- Every RAM/I/O access ends on the same phase of a 1 MHz period: a **slot**.
- It takes 16 or 24 ticks (2 or 3 CPU half-µs cycles), depending on whether the cycle began in the first or second half of the period.
- In MODE 0–3 an access whose release check falls inside the fetch window waits until the first release check after h≈643, then ends on the next slot.

AUG §15.3.2 agrees: "a PHI OUT low time of 250ns followed by a high time of 750ns, or a low of 250ns followed by a high of 1250ns … depend[ing] upon the relative phases of the 2MHz and 1MHz clocks", and in MODE 0–3 "the ULA will hold it's clock high for up to 40μs".

**Which addresses run at which speed (FPGA L1201–1211)**
- `kbd_access` = &8000–&BFFF with ROM 8/9 paged.
- `io_access` = &FC00–&FEFF or `kbd_access` → 1 MHz.
- `rom_access` = A15 and not `io_access` → **2 MHz, never contended**. This covers &8000–&BFFF for any bank other than 8/9 (sideways RAM/ROM on the expansion bus), and the OS ROM.
- RAM → 1 MHz plus contention.

hoglet (SD p280085): "IO accesses (FCxx, FDxx, FExx); keyboard accesses (i.e. ROM slots 8/9)" are the only things still slowed to 1 MHz when code runs from sideways RAM.

**Video/CPU phase**
- **FPGA:** `clken_counter` and `h_count` are separate counters that both start at 0 at configuration. `h_count` is not reset by RST. So the phase is not pinned by design **[uncertain]**. If they are aligned (h(3:0) = `clken_counter`), slots end at h≡0 (mod 16) and the stalled access ends at S≈656.
- **JAM:** forces the phase on every reset (`resync_h_count` L920–931 releases h_count when `clken_counter`=7). So slots end at h≡8 (mod 16): `cpu_clken` is high at counter 0, and counter = h+8. Its DRAM controller interleaves CPU (counter 8–15) and video (counter 0–7) slots (L1396). The release check at counter 14 (h≡6) uses combinational `contention` (L1314). So the stalled read ends at **S = h 648**.

| | FPGA | JAM | CLK | MAME |
|---|---|---|---|---|
| 1 MHz access length | 2 or 3 half-cycles, ending on a slot | same (L1312–1316) | I/O: 2 or 3 (`run_until_io_slot`, Video.cpp L271–277), ending at h≡8 = JAM phase. **RAM in MODE 0–3 outside active fetch: 1 or 2** (L257–266), one half-cycle short | `set_clock_scale(0.5)` per access (approximate) |
| stalled read ends at | ≈h 656 (phase-dependent) | h 648 | h 648 (L259–262) | `adjust_icount(-(640-hpos)/16)`, only for lines strictly inside 1..254, rounded to even (L557–570) |
| access just before the line starts (e.g. starting at h=1008) | waits for the whole line (release check falls in the fetch) | waits for the whole line | **completes at 1016** (sees `in_blank()` at the start) | no |
| &FC00–&FDFF | 1 MHz | 1 MHz | **2 MHz** (Electron.cpp L227–231) | 1 MHz |
| keyboard (ROM 8/9) reads | 1 MHz | 1 MHz | **2 MHz** | 1 MHz |
| &8000–&BFFF other banks, OS ROM | 2 MHz | 2 MHz | 2 MHz | 2 MHz |

Note: in all models the *number of slots* between the stall release and any later 1 MHz access is phase-independent, because both derive from the same counter. That is why everything below is expressed relative to S.

---

## 7. Mode register (&FE07), when a change takes effect, address increment

**Decode (FPGA L836–890)** — &FE07 bits 5..3:

| Value | Modes | Wrap base | Columns | Text |
|---|---|---|---|---|
| 000/001/010 | 0/1/2 | &3000 | 80 | no |
| 011 | 3 | &4000 | 80 | yes |
| 100/101 | 4/5 | &5800 | 40 | no |
| 110 | 6 | &6000 | 40 | yes |
| 111 | behaves as 4 | &5800 | 40 | no |

The other bits of &FE07:
- bit 7 = CAPS LED.
- bit 6 = cassette motor relay.
- bits 2..1 = comms mode: 00 cassette in, 01 sound, 10 cassette out. Writing 10 also *sets the RxFull flag* (L883–890).

AUG p.215 agrees on the bit layout.

**When it takes effect**
- **FPGA:** the register updates at the 16 MHz edge where `cpu_clken`=1 (L742), which is the end of the write cycle. The video process uses the new `mode_40/mode_bpp/mode_text/mode_base` from the next tick. Both clocks are 16 MHz in RGB mode; `clk_video` is regenerated with XOR flops (L343–398).
- **JAM:** one extra tick, because `mode_no` is decoded in a separate registered process (L790–865). So the change is effective 2 ticks after the end of the write cycle.

So a mode change takes effect **mid-character**:
- The counter increment rate changes from that tick.
- The pixel decode changes from that tick (it is combinational on `screen_data` and the h bits, L1034–1063). The character in progress is shown partly in the old format and partly in the new.

**Increment timing**
- FPGA: 80-column modes increment at h(2:0)="111"; 40-column at h(3:0)="1111"; only while h<640 (L1004–1009).
- JAM: 80-column at h≡0 (mod 8), 40-column at h≡8 (mod 16), running on through the blanking. It reloads at h=1016 (L1006–1022) and captures the row at h=640.

Characters consumed by a line with MODE 5 until the switch and MODE 1 after it:
- FPGA: switch effective at h=16t+1 → t + (80−2t) = **80−t**.
- JAM/CLK: write landing at the slot h=16t−8 → **80−t**.

Expressed relative to the previous line's S, both are "the write completes at S + (23+t) µs" (§11.1).

| | FPGA | JAM | CLK | MAME |
|---|---|---|---|---|
| mid-line mode change | yes, 16 MHz granularity | yes (+2 ticks) | yes, at 2 MHz granularity: the write is applied when the I/O slot is reached (Electron.cpp L298–304 → Video.cpp L293–313) | **no**: whole scanline drawn with the mode current at render time (L578–632) |
| increment points | h≡7 / h≡15 | h≡0 / h≡8 | h≡0 / h≡8 (`perform`, L194–205) | n/a |
| split character pixels | mixed decode | mixed decode | the MODE 5 character whose output slot is taken by MODE 1 is never emitted; the CRT run is short by one character (cosmetic) **[inference from Video.cpp L125–151]** | n/a |

---

## 8. Screen wrap at &8000

**Behaviour (FPGA L1011–1014).** Every tick, if `byte_addr(14..11)="0000"` (i.e. the counter has rolled past &7FFF to below &0800), then `byte_addr := mode_base & byte_addr(10..3)`.

The base used is the one for the mode in force *at the tick the counter rolls over*. So if the first t characters of a line (in MODE 5) cross &8000, the wrap goes to &5800, not &3000. The MODE 6 base is &6000 (`"1100"`, L870–874), which confirms the user's note.

| | FPGA | JAM | CLK | MAME |
|---|---|---|---|---|
| wrap rule | OR the base into A14..A11, every tick | same (L1036–1038) | on increment only (L201–203), and the mask literal is wrong: `0x0000'0111'1111'1111` is a **hex** literal, i.e. `& 0x1111`. This only bites when the counter is not exactly &8000 at the wrap (e.g. screen_base < &0800) | subtract the mode size (`read_vram`, L572–576), per scanline |

---

## 9. Palette (&FE08–&FE0F)

**Behaviour (FPGA).**
- `palette(addr(2..0)) <= data xor FF` (L891–894). Logic '1' in the register = colour component off (AUG p.216).
- Applied per pixel in the output pipeline (L1064–1131), so a write takes effect on the next pixel after the end of the write cycle, even mid-character.

For MODE 1/5 (pixel indices 0,2,8,10) only &FE08 and &FE09 matter (FPGA L1066–1081 and L1098–1113):

| Colour | Red | Green | Blue |
|---|---|---|---|
| 0 | FE09 b0 | FE09 b4 | FE08 b4 |
| 1 | FE09 b1 | FE09 b5 | FE08 b5 |
| 2 | FE09 b2 | FE08 b2 | FE08 b6 |
| 3 | FE09 b3 | FE08 b3 | FE08 b7 |

This matches AUG fig 14.7b. Blanking with &FF in both registers makes all four colours black. Spacer lines (`char_row`≥8) and the border are black whatever the palette says (L1024–1028).

| | FPGA | JAM | CLK | MAME |
|---|---|---|---|---|
| mapping | as above | identical (L1121–1187) | identical (`set_palette_group`, hpp L115–124; checked bit by bit) | identical (L533–540) |
| timing | per pixel | per pixel | latched when the character's pixels are emitted (2 MHz granularity) | per scanline render |

---

## 10. ROM paging (&FE05) and keyboard

**Behaviour (FPGA L810–833)**
- If the current selection is 8–11 (`page_enable`='1' and `page(2)`='0'), the write is honoured only if bit 3=1.
- Otherwise any value is accepted: `page_enable` ← bit 3, `page` ← bits 2..0.
- The paging bits are latched on **every** &FE05 write, including ones whose purpose is to clear interrupts with bits 4–6.

Other details:
- `ROM_n` (internal BASIC) is enabled for 10/11 only (L500–502).
- With 8/9 selected, a read of &8000–&BFFF returns `"0000" & not kbd` (L507–508).
- Keyboard columns are selected by A0..A13 low (AUG §14.1).

AUG §15.4: "It is not possible to select these ROMs [0–7] directly, because BASIC will still be paged in. The only way of paging BASIC and the keyboard out is to select one of the ROMs 12 to 15 first."

OS 1.00 does exactly this in its ROM-select routine at &E39F: `TXA; STA &F4; JSR &E3A9 (PHA; LDA #&0C; STA &FE05; PLA; RTS); STA &FE05; RTS`. I disassembled this myself from `refs/ElectronFpga/roms/os100.rom`.

The OS also writes clear-only values with the paging bits zero:
- `LDY #&10 : STY &FE05` at &DBC3 (display end).
- `LDA #&40 : STA &FE05` at &F502.
- `LDA #&F8 : STA &FE05` at reset (&D8E3).

Whether a real ULA (or an external ROM-select latch) really re-pages on such writes is **[uncertain]**. All three HDL/emulator models other than CLK say it does.

| | FPGA | JAM | CLK | MAME |
|---|---|---|---|---|
| 8–11 → 0–7 blocked | yes | yes (L747–757) | **no**: `active_rom_` always takes the value, and the keyboard/BASIC flags are only updated when bit 3 is set, so 8→4 leaves the keyboard "active" over bank 4 (Electron.cpp L325–338) | yes (L468–479) |
| clear write also pages | yes | yes | **no**: the paging branch is skipped if any of bits 4–7 are set | yes |
| keyboard read speed | 1 MHz | 1 MHz | 2 MHz | 1 MHz |
| keyboard data high nibble | 0000 | 0000 | upper nibble of whatever is in slot 8 | 0000 |

---

## 11. Consequences for the test

Numbers are relative to **S** (end of the stalled RAM read on an active MODE 1 line), in µs; 1 µs = one 1 MHz slot = 2 CPU cycles. A 1 MHz write "lands" at the end of its (stretched) cycle. I/O writes snap to the next slot, so a write instruction may start one 2 MHz cycle earlier or later with no effect.

From SWRAM, `STA &FE07` takes 5 or 6 CPU cycles: three 2 MHz fetches, then a 2- or 3-half-cycle I/O write ending on a slot.

### 11.1 Horizontal fine scroll (MODE 5 for t µs, then MODE 1) — **confirmed, with one refuted sub-assumption (11.2)**

- **5→1 write:** must complete at **S + (23 + t) µs**. S is the stalled read on the *previous* line; the slot sits inside the t-th µs of the new line's active part.
  - FPGA (aligned phase): S=656, line start = S+368 ticks, effective at h=16t+1.
  - JAM/CLK: S=648, line start = S+376, slot h=16t−8.
  - Every model gives 80−t characters consumed. Landing one slot early or late gives t∓1.
  - With an empty instruction stream between them, consecutive lines' S are exactly 64 µs apart.
- **1→5 write:** after the MODE 1 part of the line has ended and before the next line starts: **S+1 µs … S+22 µs**.
  - Too early truncates the current line.
  - The last slot before h=0 is S+23 (JAM) / S+22 (FPGA aligned). Use ≤ S+22 for margin in both.
- **The write takes effect at the end of the STA's last (write) cycle**, +1 tick (FPGA) or +2 ticks (JAM). This is mid-character in JAM/CLK phase and at the character boundary in FPGA-aligned phase.
- **Visible result:**
  - The left t µs shows characters 0..t−1 decoded as MODE 5 (double-width, same palette registers).
  - The MODE 1 part shows character c (c≥t) at (c+t)/2 µs, i.e. shifted right by t MODE 1 characters.
  - The last (8−t)/2 µs of every line shows the next row's first 8−t characters, because the row stride is 72 characters. That needs hiding.
- **The sync read must be issued after the 5→1 switch.** During the MODE 5 part there is no contention, so a RAM read there completes on the next slot instead of stalling.
- **Wrap hazard:** if &8000 is crossed during a line's MODE 5 part, the wrap goes to &5800 (§8). Avoid row starts (and line-0 starts, see 11.2) within 8t bytes below &8000, or keep the playfield from crossing &8000 inside a MODE 5 lead-in.
  - **Which lines it can hit (../wide):** with 64-byte-aligned rows, only a row starting at &7FC0 has &8000 inside a lead-in, at the step from its character 7 to 8. Lines 1–7 (starting at the row's first character) reach that step only for t = 8. Line 0 of a later row starts 8−t in and takes 8 MODE 5 steps, so it always reaches it — but only that one row's line 0, at most one line a frame. So the 3 µs MODE 1 hole is needed on every t = 8 line and on that one line 0 only; every other line 0 can be unsplit (one write at +8 µs). The hole schedules then end by +11 µs, not +16 (`../wide/gen.py`, checked at every phase S 648..659), and the window can start at character 22. The scroll test's original rule (no MODE 5 step across *any* 8-character boundary, on every line 0) was stricter than needed.
  - (A MODE 6 lead-in, wrapping to &6000, was considered as an alternative alias and not needed; its effect on the 10-line row count was not checked.)

### 11.2 Row stride 576 / start-of-row register A14..A6 — **row stride confirmed; "all lines of a row align" refuted for line 0**

- FPGA and hoglet agree (§4): after a line 7 that consumed 80−t characters, `row_addr` = floor((R+640−8t)/64)·64 = R+576 for t=1..8. **Confirmed.**
- But line 0 of the *next* row starts from the untruncated counter, R′ + 8(8−t), i.e. (8−t) characters to the right in memory. Line 0 would show (8−t) characters left of lines 1–7, for t=1..7. Real hardware shows this one-line-in-eight effect (SD p280011).
- **Zero-cost fix [inference, from the FPGA model]:** on line 0 of every row that follows a scrolled MODE 1 row, use an **8 µs** MODE 5 lead-in, i.e. the 5→1 write at S+31 µs. Lines 1–7 keep t µs. Line 0 then shows character c at (c+t)/2 µs, aligned with the rest.
  - Proof: line 0 starts at index s=8−t; with lead-in L, index c lands at (c−s+L)/2, which equals (c+t)/2 iff L=8.
  - The first MODE 1 row of the frame needs *t*, not 8. Its line 0 comes aligned from screen_base, or from the MODE 6 band, which consumes 320 = 5·64 bytes per row.
  - The left strip on those lines is 8 µs wide instead of t. Hiding the left 8 µs is needed anyway for a steady left edge, since t varies.
- **Model split:**
  - JAM: all lines truncated, so the fix above would mis-shift line 0 by 8−t.
  - CLK as shipped: every row after the first drifts, because the stride becomes 640−8t.
  - This makes a good discriminating calibration pattern; real hardware should match the FPGA.

### 11.3 Vertical fine scroll (f rows of MODE 6, then MODE 1) — **confirmed, with a tighter window than stated**

- **6→1 write window:** after `char_row` has been reset at the end of hsync on the band's last line (h ≳ 834), and before the next line's first fetch: **S\* + 12 µs … S\* + 22 µs**.
  - S\* is the virtual stall instant on that line (from an earlier sync plus n·64 µs), because MODE 6 lines do not stall.
  - Ticks: JAM slots 840..1016; FPGA-aligned 848..1008.
- **Too early** (anywhere from h=640 through hsync): `char_row`=9 has bit 3 forced to 0, so `char_row`=1, `last_line` never fires and the row runs 2..7.
  - In JAM the row capture happens at h=640, so a switch between h=640 and the end of hsync also corrupts the counter.
  - Never switch before the band line's hsync has ended.
- **Too late** (after the next line's h=0): the first characters are fetched at MODE 6 rate.
- **Switching into MODE 6:**
  - Do it after the display-end point (v=255, h=768) and before v=0.
  - Display end compares v=255 only in a graphics mode and v=249 only in a text mode. Being in MODE 6 at line 255 h=768 (or in MODE 1 at line 249) means **no display-end flag that field**.
- **Other notes:**
  - MODE 6 wraps to &6000 — confirmed.
  - The band rows are 10 lines; lines 8–9 are forced black.
  - MODE 1 still ends at v=255 whatever f is, so the window's bottom stays put and the content shifts down by 10f lines.
  - Screen start below &3000 is fine as long as it is ≥ &0800 (below that the wrap rule fires immediately).
- **[suggestion]** A MODE 3 band (also 10-line rows, wrap at &4000, 640 bytes per row) would contend on band lines 0–7 and so give real syncs inside the band.

### 11.4 Palette writes at fixed lines — **confirmed**

- Effective at the end of the write cycle (next pixel).
- Place them in **S+1 … S+22 µs** to land in that line's blanking. &FE08/&FE09 = &FF blanks all MODE 1 colours.
- Mid-line writes work per pixel in FPGA/JAM; in CLK they apply per character.

### 11.5 Raster sync by stalled RAM read; SWRAM at 2 MHz; I/O at 1 MHz — **confirmed**

- **Stall completion:** S = h 648 in JAM/CLK, ≈ h 656 in FPGA-aligned phase. That is 0.5–1 µs after the last pixel fetch (h=640), on a 1 MHz slot.
  - The absolute position relative to pixels is ±0.5 µs **[uncertain; real phase unmeasured]**.
  - Relative timing to later I/O slots is model-independent.
- **Where the sync works:** only on active MODE 0–3 lines (v<256), lines 0–7 of a row (not MODE 3 spacers), and after the MODE 1 switch on that line. The bottom 56 lines and the MODE 6 band need cycle counting.
- **Speeds:**
  - &8000–&BFFF in banks other than 8/9 is 2 MHz uncontended in every model (and AUG §15.3.1 for ROM).
  - &FC00–&FEFF and keyboard reads are 1 MHz, 2 or 3 half-cycles, ending on a slot (CLK wrongly runs FC/FD and keyboard at 2 MHz).
  - In MODE 1 outside the active fetch, a RAM access is also 2 or 3 half-cycles (CLK gives 1 or 2 — patch below).
  - An uncontended RAM access that starts in the last 1.5 µs before a line's active part (release check would fall at h≥0) waits for the whole line in FPGA/JAM.

### 11.6 Field parity via RTC at line 99 — **confirmed**

**Field 0** — 312 lines; RTC flag set:
- FPGA: v=99, h≈+4
- CLK: h=8
- real: line 98, h=1009 (−15 ticks)

**Field 1** — 313 lines; RTC flag set:
- FPGA: v=99, h≈516
- CLK: h=520
- real: h=497

**Procedure:**
1. Clear the RTC flag earlier in the field (&FE05 bit 5, see 11.8).
2. Read &FE00 with the read completing between about h=16 and h=490 of line 99: about **S₉₈ + 24.5 … S₉₈ + 54 µs**, where S₉₈ is the stall on line 98. Recommended: the slot at **S₉₈ + 39 µs** (h≈232/248).
3. Bit 3 set ⇒ this field is 312 lines (RTC at line start); clear ⇒ 313 lines.

**Other notes:**
- The next field starts 312 or 313 lines after v=0 of this one.
- MAME cannot do this (no interlace).
- On FPGA hardware, select interlaced mode with Ctrl+Caps+2.

### 11.7 Display-end poll — **confirmed**

- **Event:** v=255 (graphics) at h=768. Real: h=767 relative to the first pixel.
- **Polling:** the first `LDA &FE00` whose read completes on or after the event sees bit 2 at the slot **S₂₅₅ + 8 µs** (JAM h=776, FPGA-aligned 784, CLK 776). The read at S₂₅₅ + 7 µs does not.
- **Gives:** a sync to 1 µs at the bottom of the frame. It is identical in both fields; parity comes only from 11.6.

### 11.8 Keyboard via ROM 8 and back — **confirmed, with caveats**

- **Paging rule:**
  - From a bank in 0–7 or 12–15, write 8. To return, write 12–15 directly; for a bank in 0–7, write 12 first, then the bank. This is the OS 1.00 sequence.
  - CLK accepts 8→0–7 directly; FPGA/JAM/MAME ignore it.
- **The paging and keyboard-read code cannot run from &8000–&BFFF.** The SWRAM bank is unmapped while 8 is selected. Run it from main RAM, which is contended at 1 MHz and stalls on active MODE 1 lines, so do it on lines ≥256. Or use a ROM-resident `STA &FE05 / LDA &xxxx / …` sequence if one exists.
- Keyboard reads are 1 MHz. Mask with &0F (CLK leaves junk in the high nibble).
- **Every &FE05 write you make to clear a flag should carry the paging bits of the bank you want to stay paged** (e.g. `&20 OR bank` with bank 12–15, or `&20 OR bank` with bank 0–7 when that is current). FPGA/JAM/MAME re-page on every write; a bare `&20` from bank 12–15 pages to ROM 0 with `page_enable`=0, unmapping your code.
- **&FE07 writes:** keep bits 7, 6, 2, 1 constant. Suggested: MODE 1 = &08, MODE 5 = &28, MODE 6 = &30 — comms 00 (silent), LED off, motor off. Toggling bit 6 clicks the relay; bits 2..1 = 10 sets RxFull.

---

## 12. MAME as a second emulator

Not usable for this test:
- Per-scanline rendering with the mode current at render time.
- No row register.
- No interlace or field alternation.
- RTC at line 100 and display end at line 256, h=0.
- Contention approximated with clock scaling.
- `waitforramsync` excludes lines 0 and 255.

(electron_ula.cpp L7–11 TODO list, L174–214, L557–570, L578–657.) Its paging and palette mapping do match the FPGA.

---

## 13. Recommended CLK patches (to match the FPGA for everything the test relies on)

### 13.1 Start-of-row register holds A14..A6 only (Video.cpp L101–107)

```diff
 	if(hsync_int_) {
 		if(last_line()) {
-			row_addr_ = byte_addr_;
+			row_addr_ = byte_addr_ & 0x7fc0;	// QSTART is A14..A6 (FPGA row_addr(14 downto 6));
+												// byte_addr_ itself is kept, so line 0 of the next
+												// row starts from the untruncated counter.
 		} else {
 			byte_addr_ = row_addr_;
 		}
 	}
```

### 13.2 Wrap mask literal (Video.cpp L201–203)

```diff
 			if(!(byte_addr_ & 0b0111'1000'0000'0000)) {
-				byte_addr_ = mode_base_ | (byte_addr_ & 0x0000'0111'1111'1111);
+				byte_addr_ = mode_base_ | (byte_addr_ & 0b0000'0111'1111'1111);
 			}
```

Optional, for screen_base < &0800, to match the FPGA's per-tick wrap: apply the same test after the field-start latch at L96–98.

### 13.3 RAM accesses: always 2 or 3 half-cycles, contended only if the release check falls in the fetch (Video.cpp L242–269)

```diff
 std::pair<Cycles, uint8_t> VideoOutput::run_until_ram_slot() {
-	if(mode_40_) {
-		return run_until_io_slot();
-	}
-
-	Cycles duration{};
-	uint8_t interrupts{};
-
-	// If currently in the back half of a cycle,
-	// advance to the start of the next 1Mhz window.
-	if(h_count_ & 8) {
-		duration += Cycles(1);
-		interrupts |= run_for(Cycles(1));
-	}
-
-	// If now in blank, just finish out the half window.
-	// Otherwise let the pixel run end.
-	if(!in_blank()) {
-		const auto additional = Cycles(1 + ((h_active - h_count_) >> 3));
-		duration += additional;
-		interrupts |= run_for(additional);
-	} else {
-		duration += Cycles(1);
-		interrupts |= run_for(Cycles(1));
-	}
-
-	return std::make_pair(duration, interrupts);
+	// Every RAM access is a 1MHz access, stopped and released exactly like IO
+	// (FPGA/JamSoft clk_stopped: stop at clken_counter(2..0)=110, release at 1110).
+	auto result = run_until_io_slot();		// now h_count_ & 15 == 8
+
+	// In modes 0-3 the release is refused while the line's fetch is active; the
+	// release test 2 ticks before this slot lies in the same 8-tick block as
+	// h_count_ - 8, which is in the fetch iff !in_blank() at h_count_ (<= 632).
+	if(!mode_40_ && !in_blank()) {
+		const auto additional = Cycles((h_active + 8 - h_count_) >> 3);	// to h = 648
+		result.first += additional;
+		result.second |= run_for(additional);
+	}
+	return result;
 }
```

This keeps the stalled-read end at h=648, as CLK has it now. It fixes border-region RAM accesses (1–2 → 2–3 half-cycles, per AUG §15.3.2), and accesses that start just before a line's active part.

### 13.4 &FC00–&FDFF and keyboard reads are 1 MHz (Electron.cpp L222–232)

```diff
 	std::pair<Cycles, uint8_t> run_for_access(const uint16_t address) {
 		if(address < 0x8000) {
 			return video_.run_until_ram_slot();
 		}
-
-		if((address & 0xff00) == 0xfe00) {
+		// FRED, JIM, SHEILA, and the keyboard (ROM 8/9 paged) run at 1MHz (FPGA io_access).
+		if((address >= 0xfc00 && address < 0xff00) || (address < 0xc000 && keyboard_is_active_)) {
 			return video_.run_until_io_slot();
 		}
```

### 13.5 &FE05: page on every write, with the 8–11 rule (Electron.cpp L315–340)

```diff
 				case 0xfe05:
 					if(!is_read(operation)) {
 						const uint8_t interruptDisable = (*value)&0xf0;
 						if( interruptDisable ) {
 							if( interruptDisable&0x10 ) interrupt_status_ &= ~Interrupt::DisplayEnd;
 							if( interruptDisable&0x20 ) interrupt_status_ &= ~Interrupt::RealTimeClock;
 							if( interruptDisable&0x40 ) interrupt_status_ &= ~Interrupt::HighToneDetect;
 							evaluate_interrupts();
-
-							// TODO: NMI
-						} else {
-							// Latch the paged ROM in case external hardware is being emulated.
-							active_rom_ = *value & 0xf;
-
-							// apply the ULA's test
-							if(*value & 0x08) {
-								if(*value & 0x04) {
-									keyboard_is_active_ = false;
-									basic_is_active_ = false;
-								} else {
-									keyboard_is_active_ = !(*value & 0x02);
-									basic_is_active_ = !keyboard_is_active_;
-								}
-							}
 						}
+						// The ULA latches the paging bits on every write (FPGA ElectronULA.vhd
+						// L823-833); while 8-11 is selected only values with bit 3 set are honoured.
+						if((active_rom_ & 0xc) != 0x8 || (*value & 0x08)) {
+							active_rom_ = *value & 0xf;
+							keyboard_is_active_ = (active_rom_ & 0xe) == 0x8;
+							basic_is_active_ = (active_rom_ & 0xe) == 0xa;
+						}
 					}
 				break;
```

### 13.6 Keyboard read high nibble (Electron.cpp L491–494) — cosmetic

```diff
 							if(keyboard_is_active_) {
-								*value &= 0xf0;
+								*value = 0x00;			// FPGA: "0000" & (kbd xor "1111")
```

### 13.7 Optional, to match the real-chip captures rather than the FPGA

- RTC about 15 ticks early: field 0 at v=98, h=1008; field 1 at v=99, h=496 (Video.cpp L208).
- Nothing else in CAP differs from the FPGA by more than 2 ticks.

Not patched, because it is cosmetic: the dropped MODE 5 character at a mid-line 40→80 split (§7).

---

## 14. ROM images found (listed only; nothing copied)

In `refs/ElectronFpga/`:

| Path | Size | Contents (from header/strings) |
|---|---|---|
| `roms/os100.rom` | 16384 | Electron OS 1.00 (MD5 4ff171eca1cc7fd17333fc0b8d1a3e75) |
| `roms/Basic2.rom` | 16384 | BBC BASIC II |
| `roms/mmfs_swram.rom` | 16384 | "Electron MMFS SWRAM" |
| `roms/smelk3006.rom` | 16384 | "SPI" (MMC filing system, Smart SPI) |
| `roms/pres_ap2_v1_23.rom` | 16384 | "PRES Plus 1" / "PRES AP2 1.23 (ADC/Printer/RS423)". A PRES replacement for the Plus 1 ROM, **not** Acorn's |
| `roms/M7_191.rom` | 16384 | "Mode 7 OS. v1.91" (Jafa) |
| `roms/blank.rom` | 16384 | empty |
| `altera/release/rom_image.bin` | 262144 | the above concatenated per `roms/make_rom_image.sh` |
| `src/common/ROM/RomOS100.vhd`, `RomBasic2.vhd`, `RomSmelk3006.vhd` | ~803 KB each | the same ROMs as VHDL constants |
| `src/common/ROM/expansion_rom_mmfs.dat`, `expansion_rom_mmfs_jafa.dat` | 49152, 73728 | MMFS(+Jafa) expansion images |

Elsewhere: budgie's ULA (github EquasysIT/ElectronULA, now adbsolutions/ElectronULA, not cloned) has `VHDL/MAX 10 Board/ROM/PLUS1_EMMFS_JAFFA_SAA5050.HEX` (180252 bytes of Intel HEX). The name suggests a Plus 1 ROM image is inside; I have not checked which one. It also has `saa5050.hex` (11276 bytes).

Not present anywhere I looked (ElectronFpga, JamSoft, adbsolutions/ElectronULA tree listing): Plus 3 ADFS, any 1770 DFS. JamSoft contains only bitstreams.

---

## 15. Later findings: the real (Ferranti) ULA

Added after probe programs ran on an issue 6 Electron (November 2026). The probes
moved a window's lead-in through every schedule and photographed the result.

### 15.1 The 40-column address steps half a microsecond earlier

- **The difference.** In the 40-column modes (4, 5, 6 and 7) the real chip steps its
  address counter in the first half of each microsecond; the FPGA model (and
  JamSoft's) step it in the second half (section 7).
- **Effect on a mode switch.** A mode write lands between the two, so on switching
  from a 40-column mode to MODE 1 the real chip has made one step fewer. A lead-in of
  t characters needs the MODE 1 write at t + 1 µs on the real chip, against t µs on
  the FPGA.
- **The engine** carries both schedules and switches between them at run time
  (DESIGN.md 4.3).
- **The emulator.** The CLK fork models the real chip when
  `Electron::VideoOutput::real_m5_phase` is set (elkh `realula 1`, elkview
  `--realula`). It reproduced probes 6, 7 and 8 as photographed.

### 15.2 Mode value 7 wraps to &3000

- **What it is.** Mode value 7 (&FE07 bits 3..5 = 7) is undocumented. It displays
  like MODE 4 (40 columns, 1 bit per pixel) but wraps the address at &8000 to &3000,
  where MODE 4 and MODE 5 wrap to &5800 (pastraiser.com's Electron hardware notes).
- **Why it matters.** With the real schedule's 8 µs lead-in, the row starting at
  &7FC0 takes its eighth 40-column step across &8000. MODE 5 would send it to &5800,
  but in mode 7 it stays in the 20K ring.
- **Status.** This build relies on it. The probes that confirmed the half-microsecond
  difference predate the mode 7 lead-in, so the wrap itself is still to be seen on
  hardware.
- **The emulator.** The CLK fork models it with the real-ULA switch on.

### 15.3 The raster lock

- **The failure.** The probes from 5 on showed occasional corrupt pixels and vertical
  bars in the lead-in area, on both kinds of ULA. In the emulator exactly this appears
  when a field's lock read misses line 0's fetches: it returns without stalling, and
  every mode write of that field is mistimed.
- **The fix.** The engine now locks with two stalled reads (DESIGN.md 3.1) and pads its
  fixed work so that the lock read lands in the same place whatever the field did.
  This is the likely cause of what was seen, but not proven on hardware.

### 15.4 A CPU write to the ULA takes the video slot (21 November 2026)

- **What it is.** On a real Electron, a CPU write to a ULA register while the ULA is
  fetching for the display takes that video slot: the byte shown there is the RAM byte
  at the CPU's address with A15 dropped, **RAM[&7E00 + the address's low byte]** (for
  &FE07, RAM[&7E07]), painted in the mode the write sets. The ULA decodes A0–A3 in
  page &FE, so &FE07's mirrors &FE17 … &FEF7 show &7E17 … &7EF7.
- **Reads.** Apparently not: every window line reads &FE00 in mid-window (character
  ~44), and nothing shows there.
- **Found with** the scroll demo on a real Electron, on the lead-in's last write
  (the window's mode, DESIGN.md 4.5):
  - at 57 wide on character 15, the window's first character went black at one
    position in eight (t = 7, whose write lands on character 15);
  - at 56 wide on character 16, a thin bar the height of the window, in the left
    margin, at the lead-in's end: it moved two characters a column step (the end
    moves 1 µs), went with t = 0, and its colour depended on the scroll's path and
    position, not on the window's bytes;
  - a debug build's keys: zeroing what the band above the window fetches cured it only
    when &7E00 was in that area; writing &0F to &7E00–&7E07 turned the bar cyan, and
    zeroing them removed it. The colours seen matched &7E07's contents in nine
    emulated states, and nothing else.
- **Not yet tested:** the bar should move to &7EF7 with the write at &FEF7
  (`ELKALIAS56`); whether &FE01 or page &FF also reach the mode register; whether
  writes to the expansion pages (&FC, &FD), which the ULA also stretches to 1 MHz,
  take a slot (they would show &7Cxx, &7Dxx).
- **The models.** The FPGA keeps CPU and video on separate ports of a dual-port RAM,
  so it cannot show this, though its clock stretching treats &FC–&FE accesses exactly
  like RAM accesses (`ram_access = '1' or io_access = '1'`, ElectronULA.vhd L1258).
  CLK does not model it either; the demo keeps &7E07 zero and the soak checks it.
- **It may bear on 15.1.** The probes' "real chip steps in the first half" was read
  from where a mode write's switch showed; a write that takes its own slot would show
  one character differently. The engine's schedules work either way.
