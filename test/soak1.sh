#!/bin/sh
# soak1.sh NAME WX WY SEED TRAJ MODEL FIELDS [SCRMODE]
#
# One soak run: builds the demo starting at (WX, WY) with trajectory TRAJ (0 the
# script, 1 a random walk from SEED) into build/soak/NAME, runs it for FIELDS fields in
# elkh on ULA model MODEL (real: the Ferranti ULA with the real schedule; fpga: the
# FPGA model with the FPGA schedule, selected by pressing comma), with SPACE pressed to
# start the motion, under the store audit; SCRMODE 1 (the default) or 2 is the window's
# screen mode.  Prints one summary line; the details are in
# build/soak/NAME/soak.txt.  Exit status 0 if the run is clean.
#
# Needs build-emu/elkh (make emu) and the ROMs (ELK_ROMS, default ./roms).
set -u
NAME=$1 WX=$2 WY=$3 SEED=$4 TRAJ=$5 MODEL=$6 FIELDS=$7 SCRMODE=${8:-1}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ROMS=${ELK_ROMS:-$ROOT/roms}
B=$ROOT/build/soak/$NAME
make -s -C "$ROOT" BUILD="$B" START_WX="$WX" START_WY="$WY" SEED="$SEED" TRAJ="$TRAJ" SCRMODE="$SCRMODE" "$B/elkscroll" >/dev/null 2>&1 \
	|| { echo "$NAME: build failed"; exit 1; }
WXA=$(awk '$3==".wx"{print substr($2,3)}' "$B/elk.lbl")
GCA=$(awk '$3==".gch"{print substr($2,3)}' "$B/elk.lbl")
if [ "$MODEL" = real ]; then PRE="realula 1"; SCH=""
else PRE=""; SCH="key COMMA down fields 4 key COMMA up fields 4"; fi
"$ROOT/build-emu/elkh" --rompath "$ROMS" $PRE boot 2.5 load "$B/elkscroll" 2000 type 'CALL &2000\n' boot 2 \
	$SCH audit key SPACE down fields 4 key SPACE up fields 4 \
	soak "$FIELDS" "$B/gen/model.bin" "$B/soak" "$WXA" "$GCA" auditdump "$B/audit.txt" > "$B/soak.txt" 2>&1
S=$(grep '^soak:' "$B/soak.txt" | tail -1)
A=$(grep '^audit:' "$B/soak.txt" | tail -1)
echo "$NAME mode $SCRMODE $MODEL start $WX,$WY seed $SEED traj $TRAJ: ${S:-no result} | ${A:-no audit}"
case "$S|$A" in
	*" 0 bad, 0 unlocked, 0 late, 0 pad, 0 blip;"*"| audit: 0 stray"*) exit 0 ;;
	*) exit 1 ;;
esac
