// machine.hpp: an Acorn Electron on Clock Signal's core, for elkh and elkview.
//
// Clock Signal's Electron (Machines/Acorn/Electron) is compiled into the including
// file with CLK_HEADLESS defined, so the harness can reach the machine's state: RAM,
// the paged ROM slots, the ULA's per-field capture (pixels, fetch addresses, modes and
// every &FExx access with its raster position) and the bus hooks.  The CLK fork in
// emu/clk (branch elk-headless) adds those, and the ULA fixes the demo depends on
// (docs/ULA-NOTES.md section 13, and the real-ULA switch): stock CLK draws the demo
// wrongly.
//
// Include this from exactly one translation unit per executable.

#pragma once

#include <cstdint>
#include <cstdio>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#define CLK_HEADLESS
#include "Machines/Acorn/Electron/Electron.cpp"
#include "Analyser/Static/StaticAnalyser.hpp"

namespace elk {

using Machine = Electron::ConcreteMachine<false>;

// ROM images are looked up by CLK's catalogue names (os.rom: the Electron MOS 1.00;
// basic.rom: BASIC II) in DIR and DIR/Electron.
inline ROM::Map fetch_roms(const std::string &dir, const ROM::Request &request, const char *who) {
	ROM::Map results;
	for(const auto &description : request.all_descriptions()) {
		for(const auto &name : description.file_names) {
			for(const auto &path : {dir + "/" + name, dir + "/" + description.machine_name + "/" + name}) {
				FILE *f = std::fopen(path.c_str(), "rb");
				if(!f) continue;
				std::vector<uint8_t> data(65536);
				data.resize(std::fread(data.data(), 1, data.size(), f));
				std::fclose(f);
				results[description.name] = std::move(data);
				break;
			}
			if(results.count(description.name)) break;
		}
		if(!results.count(description.name)) {
			std::fprintf(stderr, "%s: missing ROM %s (%s)\n", who, description.descriptive_name.c_str(),
				description.file_names.empty() ? "?" : description.file_names[0].c_str());
		}
	}
	return results;
}

// A machine with sideways RAM in every free slot and, optionally, a disc or tape
// inserted; quick-loading on.  Throws std::runtime_error with a message on failure.
inline std::unique_ptr<Machine> make_machine(const std::string &romdir, const std::string &media, const char *who) {
	Analyser::Static::Acorn::ElectronTarget target;
	target.has_sideways_ram = true;
	if(!media.empty()) {
		for(auto &t : Analyser::Static::GetTargets(media)) {
			if(t->machine != Analyser::Machine::Electron) continue;
			auto *et = static_cast<Analyser::Static::Acorn::ElectronTarget *>(t.get());
			target.media = et->media;
			target.has_dfs = et->has_dfs;
			target.has_acorn_adfs = et->has_acorn_adfs;
		}
		if(target.media.empty()) throw std::runtime_error("no Electron media in " + media);
	}
	std::unique_ptr<Machine> m;
	try {
		m = std::make_unique<Machine>(target, [&](const ROM::Request &r) { return fetch_roms(romdir, r, who); });
	} catch(...) {
		throw std::runtime_error("could not build the machine (ROMs? see --rompath)");
	}
	auto opts = m->get_options();
	dynamic_cast<Electron::Machine::Options *>(opts.get())->quick_load = true;
	m->set_options(opts);
	return m;
}

// "\n" in a command-line string -> RETURN, for type_string.
inline std::wstring typed(const std::string &t) {
	std::wstring w;
	for(size_t k = 0; k < t.size(); k++) {
		if(t[k] == '\\' && k + 1 < t.size() && t[k + 1] == 'n') { w += L'\n'; k++; }
		else w += wchar_t(t[k]);
	}
	return w;
}

// The Electron's keys by name, for scripts.
inline const std::map<std::string, uint16_t> &key_names() {
	static const std::map<std::string, uint16_t> names = {
		{"SPACE", Electron::KeySpace}, {"RETURN", Electron::KeyReturn}, {"LEFT", Electron::KeyLeft},
		{"RIGHT", Electron::KeyRight}, {"UP", Electron::KeyUp}, {"DOWN", Electron::KeyDown},
		{"COLON", Electron::KeyColon}, {"SLASH", Electron::KeySlash}, {"SHIFT", Electron::KeyShift},
		{"CONTROL", Electron::KeyControl}, {"ESCAPE", Electron::KeyEscape}, {"COPY", Electron::KeyCopy},
		{"DELETE", Electron::KeyDelete}, {"MINUS", Electron::KeyMinus}, {"SEMICOLON", Electron::KeySemiColon},
		{"COMMA", Electron::KeyComma}, {"FULLSTOP", Electron::KeyFullStop}, {"BREAK", Electron::KeyBreak},
		{"A", Electron::KeyA}, {"B", Electron::KeyB}, {"C", Electron::KeyC}, {"D", Electron::KeyD},
		{"E", Electron::KeyE}, {"F", Electron::KeyF}, {"G", Electron::KeyG}, {"H", Electron::KeyH},
		{"I", Electron::KeyI}, {"J", Electron::KeyJ}, {"K", Electron::KeyK}, {"L", Electron::KeyL},
		{"M", Electron::KeyM}, {"N", Electron::KeyN}, {"O", Electron::KeyO}, {"P", Electron::KeyP},
		{"Q", Electron::KeyQ}, {"R", Electron::KeyR}, {"S", Electron::KeyS}, {"T", Electron::KeyT},
		{"U", Electron::KeyU}, {"V", Electron::KeyV}, {"W", Electron::KeyW}, {"X", Electron::KeyX},
		{"Y", Electron::KeyY}, {"Z", Electron::KeyZ},
		{"0", Electron::Key0}, {"1", Electron::Key1}, {"2", Electron::Key2}, {"3", Electron::Key3},
		{"4", Electron::Key4}, {"5", Electron::Key5}, {"6", Electron::Key6}, {"7", Electron::Key7},
		{"8", Electron::Key8}, {"9", Electron::Key9},
	};
	return names;
}

// Run until n more fields have completed.
inline void run_fields(Machine &m, int n) {
	const int target = m.video_.fields_completed + n;
	while(m.video_.fields_completed < target) m.run_for(Cycles(64));
}

}	// namespace elk
