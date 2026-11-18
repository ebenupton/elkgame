#!/bin/sh
# soak.sh [-n FIELDS] [-r RUNS] [-j JOBS] [-o FIRST]
#
# The demo's regression test: RUNS soak runs (test/soak1.sh) of FIELDS fields each,
# JOBS at a time.  Run i (counting from FIRST) starts from a position and seed derived
# from i; odd runs use the real ULA model, even runs the FPGA model; runs 1, 2, 5, 6, ...
# have a MODE 1 window and 3, 4, 7, 8, ... a MODE 2 one (-s 1 or -s 2: that mode only);
# every seventh follows the demo script, the rest random walks.  So a given -o/-r covers the same
# cases every time, and disjoint ranges cover new ones.
#
# Defaults: -n 20000 -r 8 -j (the number of CPUs) -o 1, both window modes.  Prints a line a run and a
# total; exit status 0 only if every run is clean: every field pixel-exact against the
# model, locked, its variable work done before line 249, no non-zero byte fetched in
# a lead-in or the blip, and no stray store.
set -u
N=20000 R=8 J=$(sysctl -n hw.ncpu 2>/dev/null || nproc) O=1 SM=
while getopts n:r:j:o:s: opt; do
	case $opt in
		n) N=$OPTARG ;; r) R=$OPTARG ;; j) J=$OPTARG ;; o) O=$OPTARG ;; s) SM=$OPTARG ;;
		*) sed -n '2,15p' "$0"; exit 2 ;;
	esac
done
HERE=$(cd "$(dirname "$0")" && pwd)
LOG=$(mktemp)
i=$O
while [ "$i" -lt $((O + R)) ]; do
	SEED=$(( (i * 104729) % 65535 + 1 ))
	WX=$(( (i * 977 + 331) % 2560 ))
	WY=$(( ((i * 1409 + 613) % 1280) * 2 ))
	if [ $((i % 2)) = 1 ]; then M=real; else M=fpga; fi
	if [ $((i % 7)) = 0 ]; then T=0; else T=1; fi
	if [ -n "$SM" ]; then S=$SM; else S=$(( (((i - 1) >> 1) & 1) + 1 )); fi
	echo "r$i $WX $WY $SEED $T $M $N $S"
	i=$((i + 1))
done | xargs -P "$J" -L 1 "$HERE/soak1.sh" | tee "$LOG"
RUNS=$(grep -c . "$LOG")
CLEAN=$(grep -c ' 0 bad, 0 unlocked, 0 late, 0 pad, 0 blip;.*| audit: 0 stray' "$LOG")
rm -f "$LOG"
echo "soak: $CLEAN of $RUNS runs clean ($N fields each)"
[ "$RUNS" = "$R" ] && [ "$CLEAN" = "$R" ]
