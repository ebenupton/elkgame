// elkview: an Acorn Electron in a window (SDL2), on the same Clock Signal core as elkh
// (machine.hpp), running in real time.
//
// Usage: elkview [--rompath DIR] [--realula] [--ssd FILE] [--media FILE] [--type TEXT]
//                [--record DIR]
//   --rompath  where the ROMs are (os.rom, basic.rom; also DIR/Electron); default "."
//   --realula  the real-ULA switch (real_m5_phase): the Ferranti's 40-column address
//              phase together with the Synertek's mode-7 wrap to &3000 (so the Ferranti
//              &7FC0 row failure is not reproduced; emu/README.md).  The demo boots into
//              the real ULA's lead-in schedule either way: without --realula, press comma
//              in the demo to select the FPGA ULA's (full stop selects the real one's)
//   --ssd      a quickload from a DFS disc image: finds the file that !BOOT runs (the
//              name after "RUN "), or else the first file other than !BOOT; 2.5 s (host
//              time) after start, copies it to its load address and types CALL &<execution
//              address>.  It replaces --type.  (CLK boots a DFS disc only with an
//              Electron DFS ROM, which this way is not needed.)
//   --media    a tape (.uef) or disc image to insert; e.g. with --type '*RUN\n' for a tape
//   --type     text to type 2.5 s (host time) after start ("\n" is RETURN)
//   --record   write each field shown as DIR/fNNNNN.ppm (768 x 288, as in the window);
//              fields that complete between two redraws are not written
// The window shows h 0-767 of each 1024 and lines 0-287.  Keys: the host's map onto the
// Electron's: cursor keys, letters, digits, RETURN, SPACE, SHIFT, CTRL, ESC, BACKSPACE
// (DELETE), TAB (FUNC), - ; , . /, ' or : for COLON, F12 for BREAK.  Close the window to
// quit.

#include <chrono>

#include "machine.hpp"

#include <SDL.h>

namespace {

const std::map<SDL_Keycode, uint16_t> keymap = {
	{SDLK_SPACE, Electron::KeySpace}, {SDLK_RETURN, Electron::KeyReturn}, {SDLK_LEFT, Electron::KeyLeft},
	{SDLK_RIGHT, Electron::KeyRight}, {SDLK_UP, Electron::KeyUp}, {SDLK_DOWN, Electron::KeyDown},
	{SDLK_COLON, Electron::KeyColon}, {SDLK_QUOTE, Electron::KeyColon}, {SDLK_SLASH, Electron::KeySlash},
	{SDLK_LSHIFT, Electron::KeyShift}, {SDLK_RSHIFT, Electron::KeyShift}, {SDLK_LCTRL, Electron::KeyControl},
	{SDLK_RCTRL, Electron::KeyControl}, {SDLK_ESCAPE, Electron::KeyEscape}, {SDLK_BACKSPACE, Electron::KeyDelete},
	{SDLK_MINUS, Electron::KeyMinus}, {SDLK_SEMICOLON, Electron::KeySemiColon}, {SDLK_COMMA, Electron::KeyComma},
	{SDLK_PERIOD, Electron::KeyFullStop}, {SDLK_TAB, Electron::KeyFunc}, {SDLK_F12, Electron::KeyBreak},
	{SDLK_a, Electron::KeyA}, {SDLK_b, Electron::KeyB}, {SDLK_c, Electron::KeyC}, {SDLK_d, Electron::KeyD},
	{SDLK_e, Electron::KeyE}, {SDLK_f, Electron::KeyF}, {SDLK_g, Electron::KeyG}, {SDLK_h, Electron::KeyH},
	{SDLK_i, Electron::KeyI}, {SDLK_j, Electron::KeyJ}, {SDLK_k, Electron::KeyK}, {SDLK_l, Electron::KeyL},
	{SDLK_m, Electron::KeyM}, {SDLK_n, Electron::KeyN}, {SDLK_o, Electron::KeyO}, {SDLK_p, Electron::KeyP},
	{SDLK_q, Electron::KeyQ}, {SDLK_r, Electron::KeyR}, {SDLK_s, Electron::KeyS}, {SDLK_t, Electron::KeyT},
	{SDLK_u, Electron::KeyU}, {SDLK_v, Electron::KeyV}, {SDLK_w, Electron::KeyW}, {SDLK_x, Electron::KeyX},
	{SDLK_y, Electron::KeyY}, {SDLK_z, Electron::KeyZ},
	{SDLK_0, Electron::Key0}, {SDLK_1, Electron::Key1}, {SDLK_2, Electron::Key2}, {SDLK_3, Electron::Key3},
	{SDLK_4, Electron::Key4}, {SDLK_5, Electron::Key5}, {SDLK_6, Electron::Key6}, {SDLK_7, Electron::Key7},
	{SDLK_8, Electron::Key8}, {SDLK_9, Electron::Key9},
};

// The file to quickload from a DFS disc image (first catalogue only): the one whose name
// follows "RUN " in !BOOT, or else the first file other than !BOOT.  Returns its data and
// its load and execution addresses (16 bits).  Names are matched without a directory.
bool ssd_boot_file(const std::string &path, std::vector<uint8_t> &data, unsigned &load, unsigned &exec) {
	FILE *f = std::fopen(path.c_str(), "rb");
	if(!f) return false;
	std::vector<uint8_t> img(204800 * 2);
	img.resize(std::fread(img.data(), 1, img.size(), f));
	std::fclose(f);
	if(img.size() < 512) return false;
	const int n = img[0x105] / 8;
	auto name_of = [&](int i) {
		std::string s;
		for(int k = 0; k < 7; k++) if(img[8 + 8 * i + k] != ' ') s += char(img[8 + 8 * i + k] & 0x7f);
		return s;
	};
	auto file = [&](int i, std::vector<uint8_t> &out, unsigned &ld, unsigned &ex) {
		const uint8_t *e = &img[0x108 + 8 * i];
		const unsigned len = e[4] | (e[5] << 8) | (((e[6] >> 4) & 3) << 16);
		const unsigned start = e[7] | ((e[6] & 3) << 8);
		ld = e[0] | (e[1] << 8);
		ex = e[2] | (e[3] << 8);
		if(start * 256 + len > img.size()) return false;
		out.assign(img.begin() + start * 256, img.begin() + start * 256 + len);
		return true;
	};
	std::string target;
	for(int i = 0; i < n; i++) {
		if(name_of(i) != "!BOOT") continue;
		std::vector<uint8_t> b; unsigned l, x;
		if(!file(i, b, l, x)) continue;
		const std::string t(b.begin(), b.end());
		const auto p = t.find("RUN ");
		if(p != std::string::npos)
			for(size_t k = p + 4; k < t.size() && t[k] > ' '; k++) target += char(toupper(t[k]));
	}
	for(int i = 0; i < n; i++) {
		const std::string nm = name_of(i);
		if((target.empty() && nm != "!BOOT") || nm == target) return file(i, data, load, exec);
	}
	return false;
}

}	// namespace

int main(int argc, char **argv) {
	std::string romdir = ".", media, text, record, ssd;
	for(int i = 1; i < argc; i++) {
		const std::string a = argv[i];
		if(a == "--rompath" && i + 1 < argc) romdir = argv[++i];
		else if(a == "--media" && i + 1 < argc) media = argv[++i];
		else if(a == "--type" && i + 1 < argc) text = argv[++i];
		else if(a == "--record" && i + 1 < argc) record = argv[++i];
		else if(a == "--ssd" && i + 1 < argc) ssd = argv[++i];
		else if(a == "--realula") Electron::VideoOutput::real_m5_phase = true;
		else {
			std::fprintf(stderr, "usage: elkview --rompath DIR [--realula] [--ssd FILE] [--media FILE] [--type TEXT] [--record DIR]\n");
			return 1;
		}
	}

	std::unique_ptr<elk::Machine> m;
	try { m = elk::make_machine(romdir, media, "elkview"); }
	catch(const std::exception &e) { std::fprintf(stderr, "elkview: %s\n", e.what()); return 1; }
	auto cap = std::make_unique<Electron::VideoOutput::Capture>();
	auto done = std::make_unique<Electron::VideoOutput::Capture>();
	m->video_.capture = cap.get();
	m->video_.completed = done.get();

	std::vector<uint8_t> qdata;
	unsigned qload = 0, qexec = 0;
	if(!ssd.empty()) {
		if(!ssd_boot_file(ssd, qdata, qload, qexec)) { std::fprintf(stderr, "elkview: no runnable file in %s\n", ssd.c_str()); return 1; }
		char buf[64];
		std::snprintf(buf, sizeof buf, "CALL &%X\\n", qexec);
		text = buf;
	}

	if(SDL_Init(SDL_INIT_VIDEO) != 0) { std::fprintf(stderr, "SDL: %s\n", SDL_GetError()); return 1; }
	SDL_Window *win = SDL_CreateWindow(Electron::VideoOutput::real_m5_phase ? "Electron (CLK core, real ULA)" : "Electron (CLK core, FPGA ULA)",
		SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 960, 768, SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
	SDL_Renderer *ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
	SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0");
	SDL_RenderSetLogicalSize(ren, 960, 768);
	// the texture: h 0-767 of each 1024 (a pixel per 1/16 us) and lines 0-287
	const int TW = 768, TH = 288;
	SDL_Texture *tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, TW, TH);
	std::vector<uint32_t> pix(TW * TH);
	static const uint32_t pal[8] = {0xff000000, 0xff0000ff, 0xff00ff00, 0xff00ffff,
		0xffff0000, 0xffff00ff, 0xffffff00, 0xffffffff};

	bool typed = text.empty();
	int shown = -1, nrec = 0;
	const auto t0 = std::chrono::steady_clock::now();
	long long cycles = 0;
	bool quit = false;
	while(!quit) {
		SDL_Event e;
		while(SDL_PollEvent(&e)) {
			if(e.type == SDL_QUIT) quit = true;
			if((e.type == SDL_KEYDOWN || e.type == SDL_KEYUP) && !e.key.repeat) {
				const auto k = keymap.find(e.key.keysym.sym);
				if(k != keymap.end()) m->set_key_state(k->second, e.type == SDL_KEYDOWN);
			}
		}
		// real time: 2 MHz cycles, never more than a second behind (any more is dropped)
		const double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
		const long long target = (long long)(secs * 2000000.0);
		if(target - cycles > 2000000) cycles = target - 2000000;
		while(cycles < target) { m->run_for(Cycles(1000)); cycles += 1000; }
		if(!typed && secs > 2.5) {
			for(size_t k = 0; k < qdata.size() && qload + k < 0x8000; k++) m->ram_[qload + k] = qdata[k];
			m->type_string(elk::typed(text));
			typed = true;
		}
		if(m->video_.fields_completed != shown) {
			shown = m->video_.fields_completed;
			for(int y = 0; y < TH; y++)
				for(int x = 0; x < TW; x++)
					pix[y * TW + x] = pal[done->pix[y][x] & 7];
			SDL_UpdateTexture(tex, nullptr, pix.data(), TW * 4);
			if(!record.empty()) {
				char name[512];
				std::snprintf(name, sizeof name, "%s/f%05d.ppm", record.c_str(), nrec++);
				if(FILE *f = std::fopen(name, "wb")) {
					std::fprintf(f, "P6\n%d %d\n255\n", TW, TH);
					for(uint32_t p : pix) { const uint8_t c[3] = {uint8_t(p >> 16), uint8_t(p >> 8), uint8_t(p)}; std::fwrite(c, 1, 3, f); }
					std::fclose(f);
				}
			}
		}
		SDL_RenderClear(ren);
		SDL_RenderCopy(ren, tex, nullptr, nullptr);
		SDL_RenderPresent(ren);
	}
	SDL_Quit();
	return 0;
}
