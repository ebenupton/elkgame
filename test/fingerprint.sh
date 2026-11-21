#!/bin/sh
# fingerprint.sh OUT WX WY SEED TRAJ MODEL FIELDS
#
# A timing fingerprint.  Builds the program as soak1.sh does (into build/fp/<basename
# of OUT>), but moving from the start (MOTION=1) and booting into the model's
# schedule (SCHED=8 for MODEL real, 0 for fpga), so that no key press -- whose timing
# relative to the program's fields could vary between builds -- steers it.  Runs it
# in elkh for FIELDS fields and writes every &FExx access of every field to OUT, one
# a line: field, line, h (1/16 us), R or W, register, value.  Every mode and palette
# write the engine makes is at a cycle-exact raster position, so two builds with
# identical fingerprints over a range of trajectories place every write identically:
# use it to check that a change is timing-neutral (diff the two files, or compare
# them with test/fpcompare.py).  SCRMODE=2 in the environment fingerprints the MODE 2
# window.  Needs build-emu/elkh and the ROMs (ELK_ROMS, default ./roms).
set -u
OUT=$1 WX=$2 WY=$3 SEED=$4 TRAJ=$5 MODEL=$6 FIELDS=$7
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ROMS=${ELK_ROMS:-$ROOT/roms}
B=$ROOT/build/fp/$(basename "$OUT")
if [ "$MODEL" = real ]; then PRE="realula 1" S=8; else PRE="" S=0; fi
make -s -C "$ROOT" BUILD="$B" START_WX="$WX" START_WY="$WY" SEED="$SEED" TRAJ="$TRAJ" MOTION=1 SCHED=$S SCRMODE="${SCRMODE:-1}" "$B/elkscroll" >/dev/null 2>&1 \
	|| { echo "fingerprint: build failed" >&2; exit 1; }
rm -f "$OUT"
"$ROOT/build-emu/elkh" --rompath "$ROMS" $PRE boot 2.5 load "$B/elkscroll" 2000 type 'CALL &2000\n' boot 2 \
	iolog "$FIELDS" "$OUT" >/dev/null
