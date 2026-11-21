// elkh: a headless Acorn Electron, driven by a command script, that runs the scroll
// demo's checks.  The machine is Clock Signal's Electron from the elk-headless fork
// (machine.hpp); see emu/README.md.
//
// Usage: elkh [--rompath DIR] [--media FILE] COMMAND...
//   --rompath DIR   where the ROMs are (os.rom, basic.rom; also DIR/Electron); default "."
//   --media FILE    a disc or tape image to insert
//
// The commands run in order, left to right.  Addresses and byte values are hex without
// a prefix; counts are decimal; a LEN may also be 0x-prefixed hex.
//   boot SECS              run SECS seconds of emulated time (fractions allowed)
//   cycles N               run N CPU cycles (2 MHz)
//   fields N               run until N more fields have completed
//   type TEXT              type TEXT through the OS ("\n" is RETURN)
//   load FILE HEXADDR      copy FILE into main RAM at HEXADDR (up to &7FFF; the rest is
//                          dropped)
//   key NAME down|up       press or release a key (any word but "down" releases).  NAME:
//                          SPACE RETURN LEFT RIGHT UP DOWN COLON SLASH SHIFT CONTROL ESCAPE
//                          COPY DELETE MINUS SEMICOLON COMMA FULLSTOP BREAK, A-Z, 0-9
//   poke HEXADDR HEXVAL    write a byte of main RAM
//   peek HEXADDR LEN       print LEN bytes of main RAM
//   peekrom SLOT HEXADDR LEN
//                          print LEN bytes of ROM or sideways RAM slot SLOT (0-15, decimal)
//                          at HEXADDR (&8000-&BFFF)
//   regs                   print the CPU's registers, the field count and the paged slot
//   dump PREFIX            write the last complete field: PREFIX.ppm (1024 x 313, a pixel
//                          per 1/16 us), PREFIX.addr (313 x 128 uint16 in host order: the
//                          address fetched in each 0.5 us slot, 0xffff for none),
//                          PREFIX.mode (313 x 128 bytes: the mode value in force in each
//                          slot), PREFIX.io (every &FExx access: line, h in 1/16 us, R or
//                          W, register, value)
//   iolog N FILE           run N fields, appending every &FExx access of each to FILE, a
//                          line each ("field line h R|W FExx value", fields counted from
//                          0): the timing fingerprint (test/fingerprint.sh)
//   realula 0|1            the ULA model: 1 is the real-ULA switch (real_m5_phase): the
//                          Ferranti's 40-column address phase, half a microsecond earlier,
//                          together with the Synertek's mode-7 wrap to &3000; 0 (the
//                          default; any value but "1") is the FPGA/JamSoft phase, with mode
//                          value 7 wrapping to &5800.  Neither setting is one real chip: a
//                          Ferranti wraps mode 7 to &5800 with the early phase, so the
//                          Ferranti &7FC0 row failure (DESIGN.md, "Two ULAs: the
//                          schedules") is not reproduced
//   rowreg old|new         the start-of-row register: "new" (the default) keeps address
//                          bits 14..6, as the hardware does; anything else, every bit, as
//                          upstream CLK does
//
// The demo's checks (test/soak1.sh drives them):
//   soak N MODEL OUT WXADDR GCHADDR
//       Run N fields and check each one:
//       - the picture: every pixel of the window, lines Y0 to Y1 - 1 and characters
//         WIN_C to WIN_C + WIN_W - 1, exactly as the pattern model says (MODEL:
//         build/.../gen/model.bin, from tools/gen.py) for the position the program held
//         for that field (wx and wy, read from WXADDR, the label wx in the program's
//         sideways RAM bank), except that every slot in which the window fetches the
//         leak byte, &7E07, must be black; and nothing lit outside the window on lines
//         0-255, h 0-639;
//       - the lock: the window's exit (the first write of MODE 4, &20, to &FE07 on or
//         below line Y0) at line Y1, h 120 exactly, and the lock read on line 0 (the
//         lock read is a RAM read, so its position is taken from the status-read
//         marker frame_tail makes just before it: the last &FE00 read before the
//         field's first palette write);
//       - the variable work's end (the second &FE00 read after the exit, a marker in
//         frame.s): before line 255, display end in MODE 4, or the field is "late";
//       - the pad/blip audit: no non-zero byte fetched in a 40-column mode on a window
//         line ("pad": h < 320, the lead-in; "blip": h >= 320, the right margin).
//       Writes OUT.rec, 8 bytes a field (wx and wy, 16 bits each, low byte first; the
//       byte at GCHADDR, gch: characters the vertical step drew; flags: 1 picture wrong,
//       2 not locked; the line the variable work ended on, low 8 bits; 0), prints the
//       first 12 wrong fields and the first 12 with pad or blip bytes, dumps the first 3
//       wrong fields as OUT_badK.* (K: the field's index), and ends with a summary line.
//   audit                  from now on, log stores the demo should never make: main RAM
//                          stores outside the screen ring (&3000-&7FFF), the stack, the
//                          key bytes (&0A00-&0A02) and the dummy page (&2400-&24FF);
//                          non-zero stores to the leak byte, &7E07, on lines 29-199 (the
//                          lines on which the window's &FE07 writes can show it); and
//                          count sideways RAM stores by address (first 40 of each kind
//                          printed)
//   auditdump FILE         write the sideways RAM store counts to FILE (address, count,
//                          the first writer's PC) and print the audit's summary line
//   race N                 run N fields, comparing every screen store with the same
//                          field's display fetches of that byte on lines 30-199; prints
//                          the near misses and a histogram of fetch - store in 0.5 us
//                          (it replaces the audit's main RAM hook while it runs)
//   swatch HEXADDR N       run N fields, printing every store to that sideways RAM
//                          address (any slot; field, line, h, value): for following a
//                          variable (it replaces the audit's sideways RAM hook while it
//                          runs)

#include <algorithm>
#include <cstdlib>
#include <functional>
#include <unordered_map>

#include "machine.hpp"

namespace {

void write_file(const std::string &path, const void *data, size_t size) {
	if(FILE *f = std::fopen(path.c_str(), "wb")) { std::fwrite(data, size, 1, f); std::fclose(f); }
}

void dump(elk::Machine &m, const std::string &prefix) {
	const auto &c = *m.video_.completed;
	if(FILE *f = std::fopen((prefix + ".ppm").c_str(), "wb")) {
		std::fprintf(f, "P6\n1024 313\n255\n");
		for(int y = 0; y < 313; y++) {
			for(int x = 0; x < 1024; x++) {
				const uint8_t v = c.pix[y][x];
				const uint8_t p[3] = {uint8_t((v & 4) ? 255 : 0), uint8_t((v & 2) ? 255 : 0), uint8_t((v & 1) ? 255 : 0)};
				std::fwrite(p, 1, 3, f);
			}
		}
		std::fclose(f);
	}
	write_file(prefix + ".addr", c.addr, sizeof(c.addr));
	write_file(prefix + ".mode", c.mode, sizeof(c.mode));
	if(FILE *f = std::fopen((prefix + ".io").c_str(), "w")) {
		for(const auto &a : c.io) std::fprintf(f, "%3d %4d %c FE%02X %02X\n", a.v, a.h, a.write ? 'W' : 'R', a.reg, a.value);
		std::fclose(f);
	}
}

void hexdump(const uint8_t *base, unsigned addr, unsigned len) {
	for(unsigned i = 0; i < len; i += 16) {
		std::printf("%04x:", addr + i);
		for(unsigned j = i; j < len && j < i + 16; j++) std::printf(" %02x", base[j]);
		std::printf("\n");
	}
}

unsigned hex(const std::string &s) { return unsigned(std::strtoul(s.c_str(), nullptr, 16)); }

// The demo's test pattern, as tools/gen.py's pixel() computes it, but as the colour the
// emulator draws (3-bit RGB: red 4, green 2, blue 1) for map pixel (mx in the window
// mode's pixels, my in lines).  model.bin, 789 bytes, is written by gen.py: Y0, H,
// WIN_C, WIN_W (a byte each), PERM, PE, PO (256 bytes each), the window's mode (1 or 2)
// and the MODE 2 palette (16 logical colours as the emulator's pixels).
struct Model {
	int y0 = 0, h = 0, win_c = 0, win_w = 0, mode = 1;
	uint8_t perm[256], pe[256], po[256], pal[16];
	bool load(const std::string &path) {
		std::vector<uint8_t> b(4 + 3 * 256 + 17);
		FILE *f = std::fopen(path.c_str(), "rb");
		if(!f) return false;
		const bool ok = std::fread(b.data(), 1, b.size(), f) == b.size();
		std::fclose(f);
		if(!ok) return false;
		y0 = b[0]; h = b[1]; win_c = b[2]; win_w = b[3];
		std::copy_n(&b[4], 256, perm); std::copy_n(&b[260], 256, pe); std::copy_n(&b[516], 256, po);
		mode = b[772];
		std::copy_n(&b[773], 16, pal);
		return mode == 1 || mode == 2;
	}
	int ppc() const { return mode == 2 ? 2 : 4; }		// pixels a character (a byte)
	int colour(int mx, int my) const {
		static const uint8_t rgb[4] = {0, 3, 5, 6};		// MODE 1's logical colours 0-3: black, cyan, magenta, yellow
		const int bw = 4 * ppc();				// a block: four characters across
		if((mx % bw) == 0 || (my & 15) == 15) return 0;
		const int v = (perm[(mx / bw) & 255] + ((my >> 4) & 255)) & 255;
		const uint8_t b = (my & 1) ? po[v] : pe[v];
		if(mode == 2) {
			const int s = (mx & 1) ? 0 : 1;
			int l = 0;
			for(int k = 0; k < 4; k++) l |= ((b >> (2 * k + s)) & 1) << k;
			return pal[l];
		}
		const int p = mx & 3;
		return rgb[((b >> (7 - p)) & 1) << 1 | ((b >> (3 - p)) & 1)];
	}
};

// The leak byte (DESIGN.md, "The leak byte: what a mid-line ULA write shows"): on a real
// ULA a CPU write to &FE07 during the display takes that video slot, which shows
// RAM[&7E07] instead of its own byte.  The fork does not model this, so the emulated
// picture cannot show it; instead the soak expects black wherever the window fetches
// &7E07, which holds only if the demo keeps the byte zero, and the audit catches any
// non-zero store to it while the window is up.
constexpr uint16_t kLeak = 0x7e07;

int soak(elk::Machine &m, int nf, const std::string &model_path, const std::string &outp, unsigned wxa, unsigned gca) {
	Model model;
	if(!model.load(model_path)) { std::fprintf(stderr, "soak: cannot read the model %s\n", model_path.c_str()); return 1; }
	while((m.active_rom_ & 0x0c) == 0x08) m.run_for(Cycles(64));	// wait while slot 8-11 (the keyboard, BASIC) is paged: the slot then paged is the program's bank
	const int slot = m.active_rom_;
	auto r16 = [&](unsigned a) { return int(m.roms_[slot][a & 0x3fff] | (m.roms_[slot][(a + 1) & 0x3fff] << 8)); };
	FILE *fo = std::fopen((outp + ".rec").c_str(), "wb");
	int pwx = r16(wxa), pwy = r16(wxa + 2);	// wx, wy as the next field starts: the position it shows
	long badf = 0, unlocked = 0, late = 0, padf = 0, blipf = 0, shown = 0, pshown = 0;
	int maxvar = 0, minlock = 9999, maxlock = -1;
	const int Y0 = model.y0, Y1 = model.y0 + model.h;
	for(int k = 0; k < nf; k++) {
		elk::run_fields(m, 1);
		const auto &c = *m.video_.completed;

		// The picture: the window against the model, nothing lit outside it (lines 0-255,
		// h 0-639).  x is in 1/16 us; a character is 8 of them.
		long bad = 0, outside = 0;
		const int x0 = model.win_c * 8, x1 = x0 + model.win_w * 8;
		for(int y = 0; y < 256; y++) {
			const bool in_rows = y >= Y0 && y < Y1;
			for(int x = 0; x < 640; x++) {
				if(in_rows && x >= x0 && x < x1) {
					const int ppc = model.ppc(), sh = ppc == 2 ? 2 : 1;	// a pixel is 2 capture units in MODE 1, 4 in MODE 2
					// a slot that fetches the leak byte (&7E07) must be black: the demo keeps it zero
					const int want = c.addr[y][x >> 3] == kLeak ? 0
						: model.colour((pwx * ppc + ((x - x0) >> sh)) % (2560 * ppc), (pwy + y - Y0) % 2560);
					if(c.pix[y][x] != want) bad++;
				} else if(c.pix[y][x]) outside++;
			}
		}

		// The lock.  The window's exit, the first write of MODE 4 (&20) to &FE07 on or below
		// line Y0 (the lines above the window are MODE 4 too), must land at line Y1, h 120
		// exactly.  The lock read itself is a main-RAM read, which the I/O log does not
		// see; frame_tail makes a status read (lda ULA_STAT) a few cycles before it as a
		// marker, the last &FE00 read before the field's first palette write (&FE08 on line
		// 29; the exit's write of &FF at line 200 does not count).  The marker must be on
		// line 0, and its h is what the summary reports as the lock read's.
		// The variable work's end: the second &FE00 read after the exit, the marker after
		// vstep in frame.s (the first marks the start of the bottom of the frame).
		bool exit_ok = false, lock_ok = false, pal = false;
		int lockh = -1, varend = -1, nrd = -1, lastv = -1, lasth = -1;
		for(const auto &a : c.io) {
			if(!a.write && a.reg == 0x00) {
				if(!pal) { lastv = a.v; lasth = a.h; }
				if(nrd >= 0 && ++nrd == 2) varend = a.v;
			}
			if(a.write && a.reg == 0x08 && a.value != 0xff && !pal) { pal = true; lock_ok = lastv == 0; lockh = lasth; }
			if(a.write && a.reg == 0x07 && a.value == 0x20 && a.v >= Y0 && nrd < 0) { exit_ok = a.v == Y1 && a.h == 120; nrd = 0; }
		}
		const bool locked = exit_ok && lock_ok;
		if(!locked) unlocked++;
		if(varend >= 255 || varend < 0) late++;
		maxvar = std::max(maxvar, varend);
		if(lock_ok) { minlock = std::min(minlock, lockh); maxlock = std::max(maxlock, lockh); }

		// The pad audit (the fork's capture): non-zero bytes fetched in a 40-column mode
		// on a window line, in the lead-in (padl, "pad") or the right margin (padr, "blip").
		long pad = 0, blip = 0; int padline = -1;
		for(int y = Y0; y < Y1; y++) {
			if(c.padl[y] && padline < 0) padline = y;
			pad += c.padl[y]; blip += c.padr[y];
		}
		if(pad) padf++;
		if(blip) blipf++;
		if(bad || outside) badf++;
		if((pad || blip) && pshown < 12) {
			pshown++;
			int y = padline;
			if(y < 0) for(y = Y0; y < Y1 && !c.padr[y]; y++) {}
			std::printf("field %d wx %d wy %d: pad %ld blip %ld; first line %d h %d addr %04x data %02x\n",
				k, pwx, pwy, pad, blip, y, int(c.pad_h[y]), unsigned(c.pad_a[y]), unsigned(c.pad_d[y]));
		}
		if((bad || outside || !locked || varend >= 255) && shown < 12) {
			shown++;
			std::printf("field %d wx %d wy %d: bad %ld outside %ld locked %d (exit %d, lock read line %d h %d) var end line %d\n",
				k, pwx, pwy, bad, outside, int(locked), int(exit_ok), lastv, lockh, varend);
			if(shown <= 3) dump(m, outp + "_bad" + std::to_string(k));
		}

		const uint8_t rec[8] = {uint8_t(pwx), uint8_t(pwx >> 8), uint8_t(pwy), uint8_t(pwy >> 8),
			m.roms_[slot][gca & 0x3fff], uint8_t((bad || outside ? 1 : 0) | (locked ? 0 : 2)), uint8_t(varend), 0};
		if(fo) std::fwrite(rec, 1, 8, fo);
		pwx = r16(wxa); pwy = r16(wxa + 2);
	}
	if(fo) std::fclose(fo);
	std::printf("soak: %d fields, %ld bad, %ld unlocked, %ld late, %ld pad, %ld blip; variable work ended by line %d; lock read h %d..%d\n",
		nf, badf, unlocked, late, padf, blipf, maxvar, minlock, maxlock);
	return 0;
}

// The audit: stores the demo should never make, and the sideways RAM it writes.
struct Audit {
	unsigned last_pc = 0;
	long strays = 0, leaks = 0;
	std::map<unsigned, std::pair<long, unsigned>> swram;	// address -> (count, first writer's PC)
	bool on = false;
	void start(elk::Machine &m) {
		on = true;
		elk::Machine *mp = &m;
		m.opcode_hook = [this](uint16_t pc, uint8_t, uint8_t) { last_pc = pc; };
		m.ram_write_hook = [this, mp](uint16_t a, uint8_t v) {
			// the leak byte must stay zero while the window's &FE07 writes can show it: from
			// the palette line, 29, to the last window line, 199
			const int line = int(mp->video_.v_count_);
			if(a == kLeak && v && line >= 29 && line < 200) {
				if(leaks++ < 40) std::printf("leak byte store %04x=%02x pc=%04x line=%d\n", unsigned(a), unsigned(v), last_pc, line);
			}
			// allowed: the screen ring, the stack, the key bytes (&0A00-&0A02), the dummy page (&2400-&24FF)
			if((a >= 0x3000 && a < 0x8000) || (a >= 0x100 && a < 0x200) || (a >= 0xa00 && a <= 0xa02) || (a >= 0x2400 && a <= 0x24ff)) return;
			if(strays++ < 40) std::printf("stray main RAM store %04x=%02x pc=%04x line=%d\n", unsigned(a), unsigned(v), last_pc, int(mp->video_.v_count_));
		};
		m.swram_write_hook = [this](uint8_t, uint16_t a, uint8_t) {
			auto &e = swram[a];
			if(!e.first) e.second = last_pc;
			e.first++;
		};
	}
	void report(const std::string &path) const {
		if(FILE *f = std::fopen(path.c_str(), "w")) {
			for(const auto &e : swram) std::fprintf(f, "%04x %ld %04x\n", e.first, e.second.first, e.second.second);
			std::fclose(f);
		}
		std::printf("audit: %ld stray main RAM stores, %ld non-zero leak byte stores in the window; %zu sideways RAM addresses written\n",
			strays, leaks, swram.size());
	}
};

void race(elk::Machine &m, int nf) {
	struct Store { int v, h; uint16_t a; uint8_t d, old; };
	std::vector<Store> ws;
	elk::Machine *mp = &m;
	auto previous = m.ram_write_hook;
	m.ram_write_hook = [&ws, mp](uint16_t a, uint8_t v) {
		if(a >= 0x3000 && a < 0x8000) ws.push_back({int(mp->video_.v_count_), int(mp->video_.h_count_), a, v, mp->ram_[a]});
	};
	std::map<int, long> hist;		// fetch - store, in 0.5 us slots, clamped to +-40
	long shown = 0, total = 0, changed = 0;
	std::unordered_map<uint16_t, std::vector<int>> fetches;
	for(int k = 0; k < nf; k++) {
		ws.clear();
		elk::run_fields(m, 1);
		const auto &c = *m.video_.completed;
		fetches.clear();
		for(int v = 0; v < 313; v++)
			for(int sl = 0; sl < 80; sl++)
				if(c.addr[v][sl] != 0xffff) fetches[c.addr[v][sl]].push_back(v * 128 + sl);
		for(const auto &w : ws) {
			total++;
			if(w.d == w.old) continue;	// a store that changes nothing cannot show
			changed++;
			auto it = fetches.find(w.a);
			if(it == fetches.end()) continue;
			const int tw = w.v * 128 + (w.h >> 3);
			for(int tf : it->second) {
				if(tf / 128 < 30 || tf / 128 >= 200) continue;	// only the window's lines, 30-199, are lit
				const int d = std::clamp(tf - tw, -40, 40);
				hist[d]++;
				if(d > -12 && d < 12 && shown < 30) {
					shown++;
					std::printf("race: field %d store %04x %02x->%02x at line %d h %d, fetched at line %d h %d (%+d half us) mode %u\n",
						k, unsigned(w.a), unsigned(w.old), unsigned(w.d), w.v, w.h, tf / 128, (tf % 128) * 8, tf - tw, unsigned(c.mode[tf / 128][tf % 128]));
				}
			}
		}
	}
	m.ram_write_hook = previous;
	std::printf("race: %d fields, %ld screen stores, %ld changing; fetch - store (half us):", nf, total, changed);
	for(const auto &e : hist) std::printf(" %+d:%ld", e.first, e.second);
	std::printf("\n");
}

void iolog(elk::Machine &m, int nf, const std::string &path) {
	FILE *f = std::fopen(path.c_str(), "a");
	for(int k = 0; k < nf; k++) {
		elk::run_fields(m, 1);
		if(!f) continue;
		for(const auto &a : m.video_.completed->io)
			std::fprintf(f, "%d %d %d %c FE%02X %02X\n", k, a.v, a.h, a.write ? 'W' : 'R', a.reg, a.value);
	}
	if(f) std::fclose(f);
}

}	// namespace

int main(int argc, char **argv) {
	std::vector<std::string> args(argv + 1, argv + argc);
	std::string romdir = ".", media;
	size_t i = 0;
	while(i < args.size() && args[i].rfind("--", 0) == 0) {
		if(args[i] == "--rompath" && i + 1 < args.size()) { romdir = args[i + 1]; i += 2; }
		else if(args[i] == "--media" && i + 1 < args.size()) { media = args[i + 1]; i += 2; }
		else { std::fprintf(stderr, "elkh: unknown option %s\n", args[i].c_str()); return 1; }
	}
	std::unique_ptr<elk::Machine> mp;
	try { mp = elk::make_machine(romdir, media, "elkh"); }
	catch(const std::exception &e) { std::fprintf(stderr, "elkh: %s\n", e.what()); return 1; }
	elk::Machine &m = *mp;
	auto cap = std::make_unique<Electron::VideoOutput::Capture>();
	auto done = std::make_unique<Electron::VideoOutput::Capture>();
	m.video_.capture = cap.get();
	m.video_.completed = done.get();
	Audit audit;

	auto need = [&](size_t n) {
		if(i + n >= args.size()) { std::fprintf(stderr, "elkh: %s needs %zu argument(s)\n", args[i].c_str(), n); std::exit(1); }
	};
	for(; i < args.size(); i++) {
		const std::string &cmd = args[i];
		if(cmd == "boot") { need(1); const long n = long(std::atof(args[++i].c_str()) * 2000000); for(long k = 0; k < n; k += 2000) m.run_for(Cycles(int(std::min(2000L, n - k)))); }
		else if(cmd == "cycles") { need(1); const long n = std::atol(args[++i].c_str()); for(long k = 0; k < n; k += 2000) m.run_for(Cycles(int(std::min(2000L, n - k)))); }
		else if(cmd == "fields") { need(1); elk::run_fields(m, std::atoi(args[++i].c_str())); }
		else if(cmd == "type") { need(1); m.type_string(elk::typed(args[++i])); }
		else if(cmd == "load") {
			need(2);
			const std::string file = args[++i];
			const unsigned addr = hex(args[++i]) & 0x7fff;
			FILE *f = std::fopen(file.c_str(), "rb");
			if(!f) { std::fprintf(stderr, "elkh: cannot open %s\n", file.c_str()); return 1; }
			const size_t n = std::fread(&m.ram_[addr], 1, 32768 - addr, f);
			std::fclose(f);
			std::printf("loaded %zu bytes at %04x\n", n, addr);
		}
		else if(cmd == "key") {
			need(2);
			const std::string name = args[++i];
			const bool down = args[++i] == "down";
			const auto k = elk::key_names().find(name);
			if(k == elk::key_names().end()) { std::fprintf(stderr, "elkh: unknown key %s\n", name.c_str()); return 1; }
			m.set_key_state(k->second, down);
		}
		else if(cmd == "poke") { need(2); const unsigned a = hex(args[++i]); m.ram_[a & 0x7fff] = uint8_t(hex(args[++i])); }
		else if(cmd == "peek") { need(2); const unsigned a = hex(args[++i]) & 0x7fff; hexdump(&m.ram_[a], a, std::min(unsigned(std::strtoul(args[++i].c_str(), nullptr, 0)), 0x8000 - a)); }
		else if(cmd == "peekrom") {
			need(3);
			const int slot = std::atoi(args[++i].c_str()) & 15;
			const unsigned a = hex(args[++i]) & 0x3fff;
			hexdump(&m.roms_[slot][a], a | 0x8000, std::min(unsigned(std::strtoul(args[++i].c_str(), nullptr, 0)), 0x4000 - a));
		}
		else if(cmd == "regs") {
			using R = CPU::MOS6502::Register;
			std::printf("PC=%04x A=%02x X=%02x Y=%02x S=%02x P=%02x fields=%d rom=%d\n",
				m.m6502_.value_of(R::ProgramCounter), m.m6502_.value_of(R::A), m.m6502_.value_of(R::X),
				m.m6502_.value_of(R::Y), m.m6502_.value_of(R::StackPointer), m.m6502_.value_of(R::Flags),
				m.video_.fields_completed, m.active_rom_);
		}
		else if(cmd == "dump") { need(1); dump(m, args[++i]); }
		else if(cmd == "iolog") { need(2); const int n = std::atoi(args[++i].c_str()); iolog(m, n, args[++i]); }
		else if(cmd == "realula") { need(1); Electron::VideoOutput::real_m5_phase = args[++i] == "1"; }
		else if(cmd == "rowreg") { need(1); Electron::VideoOutput::row_register_14_6 = args[++i] == "new"; }
		else if(cmd == "soak") {
			need(5);
			const int n = std::atoi(args[i + 1].c_str());
			const std::string model = args[i + 2], out = args[i + 3];
			const unsigned wxa = hex(args[i + 4]), gca = hex(args[i + 5]);
			i += 5;
			if(soak(m, n, model, out, wxa, gca)) return 1;
		}
		else if(cmd == "audit") { audit.start(m); }
		else if(cmd == "auditdump") { need(1); audit.report(args[++i]); }
		else if(cmd == "race") { need(1); race(m, std::atoi(args[++i].c_str())); }
		else if(cmd == "swatch") {
			need(2);
			const unsigned wa = hex(args[++i]) & 0x3fff;
			const int n = std::atoi(args[++i].c_str());
			elk::Machine *mp = &m;
			const int f0 = m.video_.fields_completed;
			auto previous = m.swram_write_hook;
			m.swram_write_hook = [mp, wa, f0](uint8_t, uint16_t a, uint8_t v) {
				if((a & 0x3fff) == wa) std::printf("swatch field %d line %d h %d: %02x\n", mp->video_.fields_completed - f0, int(mp->video_.v_count_), int(mp->video_.h_count_), unsigned(v));
			};
			elk::run_fields(m, n);
			m.swram_write_hook = previous;
		}
		else { std::fprintf(stderr, "elkh: unknown command %s\n", cmd.c_str()); return 1; }
	}
	return 0;
}
