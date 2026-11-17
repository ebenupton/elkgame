; ---------------------------------------------------------------------------------
	.segment "VARS"
	.align	256
RTCLOG:	.res	256
VBUF:	.res	8*NSNIP			; each snippet's eight bytes (the entering column's)
sptr:	.res	2			; the snippet of the row the next window line is in
VVEC1:	.res	2			; the lead-in variant, for each part of the loop
VVECP:	.res	2
VVEC2:	.res	2
bank:	.res	1
wx:	.res	2			; the window shown next field
wy:	.res	2
mx:	.res	2			; the window the memory holds
gch:	.res	1			; characters the vertical step drew this field
smode:	.res	1			; the strip: 0 idle, 1 ahead (a commit), 2 behind
cnext:	.res	1			; columns committed next field
cnext2:	.res	1			; and the field after
hnew:	.res	1
dy:	.res	1
fpar:	.res	1
ladj:	.res	1
kprev:	.res	1
sched:	.res	1
segl:	.res	1
sdx:	.res	1
sdy:	.res	1
sgap:	.res	1
svd:	.res	1
vdiv:	.res	1
scrp:	.res	1
hcnt:	.res	1
a0h:	.res	1
kspp:	.res	1
autob:	.res	1
kprv2:	.res	1
kpend:	.res	1
lfsr:	.res	2
vcnt:	.res	1
k0:	.res	1
n1:	.res	1
cnt1:	.res	1
vcv:	.res	1
tv:	.res	1
cb8:	.res	2
band_n:	.res	1
topmode: .res	1
fe02v:	.res	1
fe03v:	.res	1
tmp:	.res	2
tmp2:	.res	1
ra:	.res	2
yt:	.res	1
yt_hi:	.res	1
byr:	.res	1
gm:	.res	1
permbx:	.res	1
pmask:	.res	1
pin:	.res	2			; (pin, pout, grow: swapped with upin.. as a block)
pout:	.res	2
grow:	.res	2
crun2:	.res	1
cskip:	.res	1
ctb:	.res	1
ctbe:	.res	1
mtop:	.res	1
mbot:	.res	1
mrow:	.res	1
msel:	.res	2
ctop:	.res	1
cbot:	.res	1
fdn:	.res	1
bcount:	.res	2
gcls:	.res	1
gkind:	.res	1
gb:	.res	2
grel:	.res	1
gzlo:	.res	1
gzhi:	.res	1
gplo:	.res	1
gphi:	.res	1
gz0:	.res	1
gz1:	.res	1
gsw:	.res	1
gbc:	.res	1
gcc:	.res	1
ve:	.res	1
vo:	.res	1
vem:	.res	1
vom:	.res	1
plo:	.res	1
phi:	.res	1
pve:	.res	1
pvo:	.res	1
pv7:	.res	1
cdir:	.res	1
cen:	.res	1
cdx:	.res	1
crow:	.res	1
sxin:	.res	2
sxout:	.res	2
xin8:	.res	2
xout8:	.res	2
ceu:	.res	1
ced:	.res	1
cin:	.res	5
clvt:	.res	5

; ---------------------------------------------------------------------------------
