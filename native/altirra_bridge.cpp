// altirra_bridge.cpp - see altirra_bridge.h for the design overview.
//
// Copyright (C) 2026 altirra_flutter contributors
// Licensed under the GNU General Public License v2 or later (same as Altirra).

#include "altirra_bridge.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <deque>
#include <functional>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "libretro.h"
#include "miniaudio.h"

// The AltirraSDL fork ships a trimmed libretro.h that only contains what the
// core itself needs; declare the frontend-facing pieces we use here.
#ifndef RETROK_LAST
#define RETROK_LAST 512
#endif

typedef void (*retro_keyboard_event_t)(bool down, unsigned keycode,
	uint32_t character, uint16_t key_modifiers);

extern "C" {
void retro_set_environment(retro_environment_t);
void retro_set_video_refresh(retro_video_refresh_t);
void retro_set_audio_sample(retro_audio_sample_t);
void retro_set_audio_sample_batch(retro_audio_sample_batch_t);
void retro_set_input_poll(retro_input_poll_t);
void retro_set_input_state(retro_input_state_t);
void retro_init(void);
void retro_deinit(void);
void retro_get_system_info(struct retro_system_info *info);
void retro_get_system_av_info(struct retro_system_av_info *info);
void retro_set_controller_port_device(unsigned port, unsigned device);
void retro_reset(void);
void retro_run(void);
size_t retro_serialize_size(void);
bool retro_serialize(void *data, size_t size);
bool retro_unserialize(const void *data, size_t size);
bool retro_load_game(const struct retro_game_info *game);
void retro_unload_game(void);
}

#if defined(__ANDROID__)
#include <android/log.h>
#endif

namespace {

using Clock = std::chrono::steady_clock;

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

std::mutex g_logMutex;
std::deque<std::pair<int, std::string>> g_logQueue;

void PushLog(int level, const char *msg) {
#if defined(__ANDROID__)
	static const int kPrio[] = { ANDROID_LOG_DEBUG, ANDROID_LOG_INFO,
		ANDROID_LOG_WARN, ANDROID_LOG_ERROR };
	__android_log_write(kPrio[level & 3], "Altirra", msg);
#else
	if (level >= RETRO_LOG_WARN)
		std::fprintf(stderr, "[altirra] %s", msg);
#endif
	if (level < RETRO_LOG_INFO)
		return;

	std::lock_guard<std::mutex> lock(g_logMutex);
	g_logQueue.emplace_back(level, msg);
	while (g_logQueue.size() > 256)
		g_logQueue.pop_front();
}

void RETRO_CALLCONV CoreLog(enum retro_log_level level, const char *fmt, ...) {
	char buf[1024];
	va_list ap;
	va_start(ap, fmt);
	std::vsnprintf(buf, sizeof buf, fmt, ap);
	va_end(ap);
	PushLog((int)level, buf);
}

void BridgeLog(int level, const char *fmt, ...) {
	char buf[1024];
	va_list ap;
	va_start(ap, fmt);
	std::vsnprintf(buf, sizeof buf, fmt, ap);
	va_end(ap);
	std::string s = std::string("[bridge] ") + buf + "\n";
	PushLog(level, s.c_str());
}

// ---------------------------------------------------------------------------
// Core options
// ---------------------------------------------------------------------------

struct OptionDef {
	std::string key;
	std::string desc;
	std::string info;
	std::string category;
	std::string defaultValue;
	std::vector<std::pair<std::string, std::string>> values; // value, label
	bool visible = true;
};

std::mutex g_optMutex;
std::vector<OptionDef> g_optDefs;
std::map<std::string, std::string> g_optValues;
// Values requested by the frontend before the core declared its options.
std::map<std::string, std::string> g_optOverrides;
std::atomic<bool> g_optUpdated { false };
// Stable storage for strings returned to the core via GET_VARIABLE.
std::map<std::string, std::string> g_optReturned;

const char *Str(const char *s) { return s ? s : ""; }

void RegisterOptionsV2(const retro_core_options_v2 *opts) {
	if (!opts || !opts->definitions)
		return;

	std::map<std::string, std::string> catNames;
	if (opts->categories) {
		for (auto *c = opts->categories; c->key; ++c)
			catNames[c->key] = Str(c->desc);
	}

	std::lock_guard<std::mutex> lock(g_optMutex);
	g_optDefs.clear();
	for (auto *d = opts->definitions; d->key; ++d) {
		OptionDef def;
		def.key = d->key;
		def.desc = Str(d->desc_categorized && *d->desc_categorized
			? d->desc_categorized : d->desc);
		def.info = Str(d->info);
		def.category = d->category_key && catNames.count(d->category_key)
			? catNames[d->category_key] : Str(d->category_key);
		for (int i = 0; i < RETRO_NUM_CORE_OPTION_VALUES_MAX
			&& d->values[i].value; ++i)
		{
			def.values.emplace_back(d->values[i].value,
				d->values[i].label ? d->values[i].label : d->values[i].value);
		}
		def.defaultValue = d->default_value ? d->default_value
			: (def.values.empty() ? "" : def.values[0].first);

		auto ov = g_optOverrides.find(def.key);
		if (ov != g_optOverrides.end())
			g_optValues[def.key] = ov->second;
		else if (!g_optValues.count(def.key))
			g_optValues[def.key] = def.defaultValue;

		g_optDefs.push_back(std::move(def));
	}
}

// Legacy "Description; a|b|c" variables (fallback path).
void RegisterVariables(const retro_variable *vars) {
	if (!vars)
		return;
	std::lock_guard<std::mutex> lock(g_optMutex);
	g_optDefs.clear();
	for (auto *v = vars; v->key; ++v) {
		OptionDef def;
		def.key = v->key;
		std::string s = Str(v->value);
		size_t semi = s.find("; ");
		def.desc = s.substr(0, semi);
		if (semi != std::string::npos) {
			std::string rest = s.substr(semi + 2);
			size_t pos = 0;
			while (pos <= rest.size()) {
				size_t bar = rest.find('|', pos);
				std::string val = rest.substr(pos,
					bar == std::string::npos ? std::string::npos : bar - pos);
				def.values.emplace_back(val, val);
				if (bar == std::string::npos)
					break;
				pos = bar + 1;
			}
		}
		def.defaultValue = def.values.empty() ? "" : def.values[0].first;
		auto ov = g_optOverrides.find(def.key);
		if (ov != g_optOverrides.end())
			g_optValues[def.key] = ov->second;
		else if (!g_optValues.count(def.key))
			g_optValues[def.key] = def.defaultValue;
		g_optDefs.push_back(std::move(def));
	}
}

// ---------------------------------------------------------------------------
// Audio: SPSC ring buffer of interleaved stereo int16 frames + miniaudio
// ---------------------------------------------------------------------------

constexpr uint32_t kSampleRate = 48000;
constexpr uint32_t kRingFrames = 1 << 14; // ~341 ms
constexpr double kTargetLatency = 0.070;   // seconds of buffered audio

int16_t g_ring[kRingFrames * 2];
std::atomic<uint32_t> g_ringRead { 0 };
std::atomic<uint32_t> g_ringWrite { 0 };
std::atomic<float> g_volume { 1.0f };
std::atomic<bool> g_audioMuted { false };
ma_device g_device;
bool g_deviceOk = false;
int16_t g_lastL = 0, g_lastR = 0;

uint32_t RingFill() {
	return g_ringWrite.load(std::memory_order_acquire)
		- g_ringRead.load(std::memory_order_acquire);
}

void RingPush(const int16_t *data, size_t frames) {
	uint32_t w = g_ringWrite.load(std::memory_order_relaxed);
	const uint32_t r = g_ringRead.load(std::memory_order_acquire);
	const uint32_t space = kRingFrames - (w - r);
	if (frames > space)
		frames = space; // overflow (e.g. fast forward): drop the excess
	for (size_t i = 0; i < frames; ++i) {
		const uint32_t idx = (w + (uint32_t)i) & (kRingFrames - 1);
		g_ring[idx * 2] = data[i * 2];
		g_ring[idx * 2 + 1] = data[i * 2 + 1];
	}
	g_ringWrite.store(w + (uint32_t)frames, std::memory_order_release);
}

void AudioCallback(ma_device *, void *out, const void *, ma_uint32 frameCount) {
	int16_t *dst = static_cast<int16_t *>(out);
	const uint32_t r = g_ringRead.load(std::memory_order_relaxed);
	const uint32_t w = g_ringWrite.load(std::memory_order_acquire);
	const uint32_t avail = w - r;
	const uint32_t n = avail < frameCount ? avail : frameCount;
	const float vol = g_audioMuted.load() ? 0.0f : g_volume.load();
	const int32_t volQ = (int32_t)(vol * 256.0f);

	for (uint32_t i = 0; i < n; ++i) {
		const uint32_t idx = (r + i) & (kRingFrames - 1);
		g_lastL = g_ring[idx * 2];
		g_lastR = g_ring[idx * 2 + 1];
		dst[i * 2] = (int16_t)((g_lastL * volQ) >> 8);
		dst[i * 2 + 1] = (int16_t)((g_lastR * volQ) >> 8);
	}
	// Underrun: hold the last sample (avoids clicks better than silence).
	for (uint32_t i = n; i < frameCount; ++i) {
		dst[i * 2] = (int16_t)((g_lastL * volQ) >> 8);
		dst[i * 2 + 1] = (int16_t)((g_lastR * volQ) >> 8);
	}
	g_ringRead.store(r + n, std::memory_order_release);
}

bool OpenAudio() {
	ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
	cfg.playback.format = ma_format_s16;
	cfg.playback.channels = 2;
	cfg.sampleRate = kSampleRate;
	cfg.dataCallback = AudioCallback;
	cfg.performanceProfile = ma_performance_profile_low_latency;
	if (ma_device_init(nullptr, &cfg, &g_device) != MA_SUCCESS) {
		BridgeLog(RETRO_LOG_WARN, "audio device unavailable; running silent");
		return false;
	}
	if (ma_device_start(&g_device) != MA_SUCCESS) {
		ma_device_uninit(&g_device);
		BridgeLog(RETRO_LOG_WARN, "audio device failed to start");
		return false;
	}
	return true;
}

// ---------------------------------------------------------------------------
// Video: double buffer, emu thread writes back buffer and swaps under lock
// ---------------------------------------------------------------------------

struct Frame {
	std::vector<uint8_t> rgba;
	int w = 0, h = 0;
};

std::mutex g_frameMutex;
Frame g_frames[2];
int g_backIndex = 0;   // only touched by the emu thread (and swap)
uint64_t g_frameSeq = 0;

void RETRO_CALLCONV VideoRefresh(const void *data, unsigned w, unsigned h,
	size_t pitch)
{
	if (!data || !w || !h)
		return; // dupe frame

	Frame &f = g_frames[g_backIndex];
	f.w = (int)w;
	f.h = (int)h;
	f.rgba.resize((size_t)w * h * 4);

	// XRGB8888 (native endian uint32) -> RGBA8888 bytes, alpha forced to 255.
	const uint8_t *src = static_cast<const uint8_t *>(data);
	uint8_t *dst = f.rgba.data();
	for (unsigned y = 0; y < h; ++y) {
		const uint32_t *row = reinterpret_cast<const uint32_t *>(src + y * pitch);
		for (unsigned x = 0; x < w; ++x) {
			const uint32_t px = row[x];
			dst[0] = (uint8_t)(px >> 16);
			dst[1] = (uint8_t)(px >> 8);
			dst[2] = (uint8_t)px;
			dst[3] = 0xFF;
			dst += 4;
		}
	}

	std::lock_guard<std::mutex> lock(g_frameMutex);
	g_backIndex ^= 1;
	++g_frameSeq;
}

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------

std::atomic<uint32_t> g_pad[4];
std::atomic<uint32_t> g_padPulse { 0 };  // extra bits OR'd into port 0
std::atomic<int16_t> g_analog[4][2][2];
std::atomic<int16_t> g_ptrX { 0 }, g_ptrY { 0 };
std::atomic<bool> g_ptrDown { false };

struct KeyEvent {
	bool down;
	unsigned keycode;
	uint32_t character;
	uint16_t mods;
};
std::mutex g_keyMutex;
std::deque<KeyEvent> g_keyQueue;
bool g_keyHeld[RETROK_LAST];
retro_keyboard_event_t g_keyboardCb = nullptr;

void RETRO_CALLCONV InputPoll() {}

int16_t RETRO_CALLCONV InputState(unsigned port, unsigned device,
	unsigned index, unsigned id)
{
	if (port >= 4)
		return 0;
	switch (device & RETRO_DEVICE_MASK) {
		case RETRO_DEVICE_JOYPAD: {
			uint32_t mask = g_pad[port].load();
			if (port == 0)
				mask |= g_padPulse.load();
			if (id == RETRO_DEVICE_ID_JOYPAD_MASK)
				return (int16_t)mask;
			return (mask >> id) & 1 ? 1 : 0;
		}
		case RETRO_DEVICE_ANALOG:
			if (index < 2 && id < 2)
				return g_analog[port][index][id].load();
			return 0;
		case RETRO_DEVICE_KEYBOARD:
			return (port == 0 && id < RETROK_LAST && g_keyHeld[id]) ? 1 : 0;
		case RETRO_DEVICE_POINTER:
			if (id == RETRO_DEVICE_ID_POINTER_X) return g_ptrX.load();
			if (id == RETRO_DEVICE_ID_POINTER_Y) return g_ptrY.load();
			if (id == RETRO_DEVICE_ID_POINTER_PRESSED) return g_ptrDown.load();
			return 0;
		case RETRO_DEVICE_LIGHTGUN:
			if (id == RETRO_DEVICE_ID_LIGHTGUN_SCREEN_X) return g_ptrX.load();
			if (id == RETRO_DEVICE_ID_LIGHTGUN_SCREEN_Y) return g_ptrY.load();
			if (id == RETRO_DEVICE_ID_LIGHTGUN_TRIGGER) return g_ptrDown.load();
			if (id == RETRO_DEVICE_ID_LIGHTGUN_IS_OFFSCREEN) return 0;
			return 0;
		default:
			return 0;
	}
}

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------

std::string g_systemDir, g_saveDir;
retro_frame_time_callback g_frameTimeCb {};
retro_audio_buffer_status_callback_t g_audioStatusCb = nullptr;
retro_disk_control_ext_callback g_disk {};
bool g_haveDisk = false;
std::atomic<double> g_fps { 59.9227 };
std::atomic<double> g_aspect { 4.0 / 3.0 };

void ApplyAvInfo(const retro_system_av_info &av) {
	if (av.timing.fps > 1.0)
		g_fps = av.timing.fps;
	if (av.geometry.aspect_ratio > 0.0f)
		g_aspect = av.geometry.aspect_ratio;
	else if (av.geometry.base_height)
		g_aspect = (double)av.geometry.base_width / av.geometry.base_height;
}

bool RETRO_CALLCONV Environment(unsigned cmd, void *data) {
	switch (cmd) {
		case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
			static_cast<retro_log_callback *>(data)->log = CoreLog;
			return true;
		case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
			*static_cast<const char **>(data) = g_systemDir.c_str();
			return true;
		case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
			*static_cast<const char **>(data) = g_saveDir.c_str();
			return true;
		case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
			return *static_cast<const retro_pixel_format *>(data)
				== RETRO_PIXEL_FORMAT_XRGB8888;
		case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
			*static_cast<unsigned *>(data) = 2;
			return true;
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:
			RegisterOptionsV2(static_cast<const retro_core_options_v2 *>(data));
			return true;
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL:
			RegisterOptionsV2(
				static_cast<const retro_core_options_v2_intl *>(data)->us);
			return true;
		case RETRO_ENVIRONMENT_SET_VARIABLES:
			{
				std::lock_guard<std::mutex> lock(g_optMutex);
				if (!g_optDefs.empty())
					return true; // already have richer v2 definitions
			}
			RegisterVariables(static_cast<const retro_variable *>(data));
			return true;
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY: {
			auto *d = static_cast<const retro_core_option_display *>(data);
			std::lock_guard<std::mutex> lock(g_optMutex);
			for (auto &def : g_optDefs)
				if (d && d->key && def.key == d->key)
					def.visible = d->visible;
			return true;
		}
		case RETRO_ENVIRONMENT_GET_VARIABLE: {
			auto *var = static_cast<retro_variable *>(data);
			std::lock_guard<std::mutex> lock(g_optMutex);
			auto it = g_optValues.find(Str(var->key));
			if (it == g_optValues.end()) {
				var->value = nullptr;
				return false;
			}
			std::string &stable = g_optReturned[it->first];
			stable = it->second;
			var->value = stable.c_str();
			return true;
		}
		case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
			*static_cast<bool *>(data) = g_optUpdated.exchange(false);
			return true;
		case RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK:
			g_keyboardCb = static_cast<const retro_keyboard_callback *>(data)
				->callback;
			return true;
		case RETRO_ENVIRONMENT_SET_FRAME_TIME_CALLBACK:
			g_frameTimeCb = *static_cast<const retro_frame_time_callback *>(data);
			return true;
		case RETRO_ENVIRONMENT_SET_AUDIO_BUFFER_STATUS_CALLBACK: {
			auto *cb = static_cast<const retro_audio_buffer_status_callback *>(data);
			g_audioStatusCb = cb ? cb->callback : nullptr;
			return true;
		}
		case RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE:
			g_disk = *static_cast<const retro_disk_control_ext_callback *>(data);
			g_haveDisk = true;
			return true;
		case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
			ApplyAvInfo(*static_cast<const retro_system_av_info *>(data));
			return true;
		case RETRO_ENVIRONMENT_SET_GEOMETRY: {
			auto *g = static_cast<const retro_game_geometry *>(data);
			if (g->aspect_ratio > 0.0f)
				g_aspect = g->aspect_ratio;
			return true;
		}
		case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
			if (data)
				*static_cast<bool *>(data) = true;
			return true;
		case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
		case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
		case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
		case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO:
		case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
		case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
		case RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS:
			return true;
		default:
			return false;
	}
}

size_t RETRO_CALLCONV AudioBatch(const int16_t *data, size_t frames) {
	if (data && frames)
		RingPush(data, frames);
	return frames;
}

void RETRO_CALLCONV AudioSample(int16_t l, int16_t r) {
	const int16_t s[2] = { l, r };
	RingPush(s, 1);
}

// ---------------------------------------------------------------------------
// Emulation thread + command queue
// ---------------------------------------------------------------------------

std::thread g_thread;
std::mutex g_cmdMutex;
std::condition_variable g_cmdCv;
std::deque<std::function<void()>> g_cmds;
std::atomic<bool> g_quit { false };
std::atomic<bool> g_paused { false };
std::atomic<bool> g_loaded { false };
std::atomic<int> g_speed { 1 };
std::atomic<double> g_measuredFps { 0.0 };
bool g_initialized = false;
std::string g_versionString;

// Runs `fn` on the emulation thread and waits for it to finish.
void RunSync(std::function<void()> fn) {
	if (!g_initialized)
		return;
	if (std::this_thread::get_id() == g_thread.get_id()) {
		fn();
		return;
	}
	std::mutex doneMutex;
	std::condition_variable doneCv;
	bool done = false;
	{
		std::lock_guard<std::mutex> lock(g_cmdMutex);
		g_cmds.push_back([&] {
			fn();
			std::lock_guard<std::mutex> l2(doneMutex);
			done = true;
			doneCv.notify_one();
		});
	}
	g_cmdCv.notify_one();
	std::unique_lock<std::mutex> l(doneMutex);
	doneCv.wait(l, [&] { return done; });
}

void RunAsync(std::function<void()> fn) {
	if (!g_initialized)
		return;
	{
		std::lock_guard<std::mutex> lock(g_cmdMutex);
		g_cmds.push_back(std::move(fn));
	}
	g_cmdCv.notify_one();
}

void DrainCommands() {
	for (;;) {
		std::function<void()> fn;
		{
			std::lock_guard<std::mutex> lock(g_cmdMutex);
			if (g_cmds.empty())
				return;
			fn = std::move(g_cmds.front());
			g_cmds.pop_front();
		}
		fn();
	}
}

void DeliverKeys() {
	std::deque<KeyEvent> events;
	{
		std::lock_guard<std::mutex> lock(g_keyMutex);
		events.swap(g_keyQueue);
	}
	for (const KeyEvent &e : events) {
		if (e.keycode < RETROK_LAST)
			g_keyHeld[e.keycode] = e.down;
		if (g_keyboardCb)
			g_keyboardCb(e.down, e.keycode, e.character, e.mods);
	}
}

// Countdown used to hold the warm-reset pad combo for a few frames.
int g_pulseFrames = 0;

void RunOneFrame(retro_usec_t usec) {
	DeliverKeys();
	if (g_frameTimeCb.callback)
		g_frameTimeCb.callback(usec);
	if (g_audioStatusCb) {
		const unsigned occ = (unsigned)(RingFill() * 100u / kRingFrames);
		g_audioStatusCb(true, occ, occ < 10);
	}
	retro_run();
	if (g_pulseFrames > 0 && --g_pulseFrames == 0)
		g_padPulse = 0;
}

void EmuThread() {
	auto next = Clock::now();
	auto fpsWindowStart = next;
	int fpsFrames = 0;

	while (!g_quit.load()) {
		DrainCommands();

		if (!g_loaded.load() || g_paused.load()) {
			std::unique_lock<std::mutex> lock(g_cmdMutex);
			g_cmdCv.wait_for(lock, std::chrono::milliseconds(20),
				[] { return !g_cmds.empty() || g_quit.load(); });
			next = Clock::now();
			g_measuredFps = 0.0;
			continue;
		}

		const double fps = g_fps.load();
		const double basePeriod = 1.0 / fps;
		const int speed = g_speed.load() < 1 ? 1 : g_speed.load();

		for (int i = 0; i < speed; ++i) {
			RunOneFrame((retro_usec_t)(basePeriod * 1e6));
			++fpsFrames;
		}

		// Dynamic rate control: nudge the frame period by up to +/-0.5% so
		// the audio buffer converges on kTargetLatency. This is far below the
		// threshold where the pitch change would be audible.
		double period = basePeriod;
		if (g_deviceOk && speed == 1) {
			const double fill = (double)RingFill() / kSampleRate;
			double err = (fill - kTargetLatency) / kTargetLatency;
			if (err > 1.0) err = 1.0;
			if (err < -1.0) err = -1.0;
			period *= 1.0 + 0.005 * err;
		}

		next += std::chrono::duration_cast<Clock::duration>(
			std::chrono::duration<double>(period));
		const auto now = Clock::now();
		if (now > next + std::chrono::milliseconds(100))
			next = now; // we fell far behind (debugger, app suspended): resync
		else
			std::this_thread::sleep_until(next);

		const auto t = Clock::now();
		const double elapsed = std::chrono::duration<double>(t - fpsWindowStart).count();
		if (elapsed >= 1.0) {
			g_measuredFps = fpsFrames / elapsed;
			fpsFrames = 0;
			fpsWindowStart = t;
		}
	}
}

void RefreshAvInfo() {
	retro_system_av_info av {};
	retro_get_system_av_info(&av);
	ApplyAvInfo(av);
}

bool WriteFile(const char *path, const void *data, size_t size) {
	FILE *f = std::fopen(path, "wb");
	if (!f)
		return false;
	const bool ok = std::fwrite(data, 1, size, f) == size;
	return std::fclose(f) == 0 && ok;
}

bool ReadFile(const char *path, std::vector<uint8_t> &out) {
	FILE *f = std::fopen(path, "rb");
	if (!f)
		return false;
	std::fseek(f, 0, SEEK_END);
	long len = std::ftell(f);
	std::fseek(f, 0, SEEK_SET);
	if (len < 0) {
		std::fclose(f);
		return false;
	}
	out.resize((size_t)len);
	const bool ok = std::fread(out.data(), 1, out.size(), f) == out.size();
	std::fclose(f);
	return ok;
}

// Strings returned to Dart must outlive the call; keep one per thread slot.
thread_local std::string t_ret;

const char *Ret(const std::string &s) {
	t_ret = s;
	return t_ret.c_str();
}

const OptionDef *OptAt(int32_t index) {
	if (index < 0 || (size_t)index >= g_optDefs.size())
		return nullptr;
	return &g_optDefs[(size_t)index];
}

} // namespace

// ===========================================================================
// Public API
// ===========================================================================

extern "C" {

AB_API int32_t ab_init(const char *system_dir, const char *save_dir) {
	if (g_initialized)
		return 1;

	g_systemDir = Str(system_dir);
	g_saveDir = Str(save_dir);
	for (auto &p : g_pad) p = 0;

	retro_set_environment(Environment);
	retro_set_video_refresh(VideoRefresh);
	retro_set_audio_sample(AudioSample);
	retro_set_audio_sample_batch(AudioBatch);
	retro_set_input_poll(InputPoll);
	retro_set_input_state(InputState);

	retro_system_info info {};
	retro_get_system_info(&info);
	g_versionString = std::string(Str(info.library_name)) + " "
		+ Str(info.library_version);

	g_deviceOk = OpenAudio();

	g_quit = false;
	g_initialized = true;
	g_thread = std::thread(EmuThread);
	RunSync([] { retro_init(); });
	return 1;
}

AB_API void ab_shutdown(void) {
	if (!g_initialized)
		return;
	RunSync([] {
		if (g_loaded.exchange(false))
			retro_unload_game();
		retro_deinit();
	});
	g_quit = true;
	g_cmdCv.notify_all();
	if (g_thread.joinable())
		g_thread.join();
	if (g_deviceOk) {
		ma_device_uninit(&g_device);
		g_deviceOk = false;
	}
	g_initialized = false;
}

AB_API const char *ab_core_version(void) { return g_versionString.c_str(); }

AB_API int32_t ab_load(const char *path) {
	std::string p = Str(path);
	bool ok = false;
	RunSync([&] {
		if (g_loaded.exchange(false))
			retro_unload_game();
		g_keyboardCb = nullptr; // the core re-registers it on load
		std::memset(g_keyHeld, 0, sizeof g_keyHeld);
		g_haveDisk = false;
		retro_set_environment(Environment);

		if (p.empty()) {
			ok = retro_load_game(nullptr);
		} else {
			retro_game_info gi {};
			gi.path = p.c_str();
			ok = retro_load_game(&gi);
		}
		if (ok) {
			RefreshAvInfo();
			g_loaded = true;
		} else {
			BridgeLog(RETRO_LOG_ERROR, "failed to load '%s'", p.c_str());
		}
	});
	g_ringRead.store(g_ringWrite.load());
	return ok ? 1 : 0;
}

AB_API void ab_unload(void) {
	RunSync([] {
		if (g_loaded.exchange(false))
			retro_unload_game();
	});
}

AB_API int32_t ab_is_loaded(void) { return g_loaded.load() ? 1 : 0; }

AB_API void ab_set_paused(int32_t paused) {
	g_paused = paused != 0;
	g_audioMuted = paused != 0;
	g_cmdCv.notify_all();
}

AB_API int32_t ab_is_paused(void) { return g_paused.load() ? 1 : 0; }

AB_API void ab_set_speed(int32_t multiplier) {
	g_speed = multiplier < 1 ? 1 : (multiplier > 16 ? 16 : multiplier);
}

AB_API void ab_cold_reset(void) {
	RunAsync([] {
		if (g_loaded.load())
			retro_reset();
	});
}

AB_API void ab_warm_reset(void) {
	RunAsync([] {
		g_padPulse = (1u << RETRO_DEVICE_ID_JOYPAD_SELECT)
			| (1u << RETRO_DEVICE_ID_JOYPAD_START);
		g_pulseFrames = 3;
	});
}

AB_API uint64_t ab_frame_copy(uint8_t *dst, int32_t capacity, int32_t *w,
	int32_t *h, uint64_t last_seq)
{
	std::lock_guard<std::mutex> lock(g_frameMutex);
	if (g_frameSeq == 0 || g_frameSeq == last_seq)
		return 0;
	const Frame &f = g_frames[g_backIndex ^ 1];
	if (w) *w = f.w;
	if (h) *h = f.h;
	if (!dst || capacity < (int32_t)f.rgba.size())
		return 0;
	std::memcpy(dst, f.rgba.data(), f.rgba.size());
	return g_frameSeq;
}

AB_API double ab_get_fps(void) { return g_fps.load(); }
AB_API double ab_get_aspect(void) { return g_aspect.load(); }
AB_API double ab_get_measured_fps(void) { return g_measuredFps.load(); }

AB_API void ab_set_volume(float volume) {
	g_volume = volume < 0.0f ? 0.0f : (volume > 1.0f ? 1.0f : volume);
}

AB_API int32_t ab_audio_ok(void) { return g_deviceOk ? 1 : 0; }

AB_API void ab_set_joypad(int32_t port, uint32_t mask) {
	if (port >= 0 && port < 4)
		g_pad[port] = mask;
}

AB_API void ab_key_event(int32_t down, uint32_t keycode, uint32_t character,
	uint32_t modifiers)
{
	std::lock_guard<std::mutex> lock(g_keyMutex);
	g_keyQueue.push_back({ down != 0, keycode, character, (uint16_t)modifiers });
}

AB_API void ab_set_analog(int32_t port, int32_t index, int32_t id,
	int32_t value)
{
	if (port < 0 || port >= 4 || index < 0 || index >= 2 || id < 0 || id >= 2)
		return;
	if (value > 32767) value = 32767;
	if (value < -32768) value = -32768;
	g_analog[port][index][id] = (int16_t)value;
}

AB_API void ab_set_pointer(int32_t x, int32_t y, int32_t pressed) {
	g_ptrX = (int16_t)x;
	g_ptrY = (int16_t)y;
	g_ptrDown = pressed != 0;
}

AB_API void ab_set_port_device(int32_t port, uint32_t device) {
	RunAsync([=] { retro_set_controller_port_device((unsigned)port, device); });
}

AB_API int32_t ab_option_count(void) {
	std::lock_guard<std::mutex> lock(g_optMutex);
	return (int32_t)g_optDefs.size();
}

#define AB_OPT_STR(name, expr) \
	AB_API const char *name(int32_t index) { \
		std::lock_guard<std::mutex> lock(g_optMutex); \
		const OptionDef *d = OptAt(index); \
		return d ? Ret(expr) : nullptr; \
	}

AB_OPT_STR(ab_option_key, d->key)
AB_OPT_STR(ab_option_desc, d->desc)
AB_OPT_STR(ab_option_info, d->info)
AB_OPT_STR(ab_option_category, d->category)
AB_OPT_STR(ab_option_default, d->defaultValue)

AB_API int32_t ab_option_value_count(int32_t index) {
	std::lock_guard<std::mutex> lock(g_optMutex);
	const OptionDef *d = OptAt(index);
	return d ? (int32_t)d->values.size() : 0;
}

AB_API const char *ab_option_value(int32_t index, int32_t vi) {
	std::lock_guard<std::mutex> lock(g_optMutex);
	const OptionDef *d = OptAt(index);
	if (!d || vi < 0 || (size_t)vi >= d->values.size())
		return nullptr;
	return Ret(d->values[(size_t)vi].first);
}

AB_API const char *ab_option_value_label(int32_t index, int32_t vi) {
	std::lock_guard<std::mutex> lock(g_optMutex);
	const OptionDef *d = OptAt(index);
	if (!d || vi < 0 || (size_t)vi >= d->values.size())
		return nullptr;
	return Ret(d->values[(size_t)vi].second);
}

AB_API int32_t ab_option_visible(int32_t index) {
	std::lock_guard<std::mutex> lock(g_optMutex);
	const OptionDef *d = OptAt(index);
	return d && d->visible ? 1 : 0;
}

AB_API const char *ab_get_option(const char *key) {
	std::lock_guard<std::mutex> lock(g_optMutex);
	auto it = g_optValues.find(Str(key));
	return it == g_optValues.end() ? nullptr : Ret(it->second);
}

AB_API int32_t ab_set_option(const char *key, const char *value) {
	if (!key || !value)
		return 0;
	{
		std::lock_guard<std::mutex> lock(g_optMutex);
		g_optOverrides[key] = value;
		g_optValues[key] = value;
	}
	g_optUpdated = true;
	return 1;
}

AB_API int32_t ab_save_state(const char *path) {
	std::string p = Str(path);
	bool ok = false;
	RunSync([&] {
		if (!g_loaded.load())
			return;
		const size_t size = retro_serialize_size();
		if (!size)
			return;
		std::vector<uint8_t> buf(size);
		if (retro_serialize(buf.data(), size))
			ok = WriteFile(p.c_str(), buf.data(), size);
	});
	return ok ? 1 : 0;
}

AB_API int32_t ab_load_state(const char *path) {
	std::string p = Str(path);
	bool ok = false;
	RunSync([&] {
		if (!g_loaded.load())
			return;
		std::vector<uint8_t> buf;
		if (ReadFile(p.c_str(), buf) && !buf.empty())
			ok = retro_unserialize(buf.data(), buf.size());
	});
	return ok ? 1 : 0;
}

AB_API int32_t ab_disk_count(void) {
	int32_t n = 0;
	RunSync([&] {
		if (g_haveDisk && g_disk.get_num_images)
			n = (int32_t)g_disk.get_num_images();
	});
	return n;
}

AB_API int32_t ab_disk_index(void) {
	int32_t n = -1;
	RunSync([&] {
		if (g_haveDisk && g_disk.get_image_index)
			n = (int32_t)g_disk.get_image_index();
	});
	return n;
}

AB_API int32_t ab_disk_select(int32_t index) {
	bool ok = false;
	RunSync([&] {
		if (!g_haveDisk || !g_disk.set_eject_state || !g_disk.set_image_index)
			return;
		g_disk.set_eject_state(true);
		ok = g_disk.set_image_index((unsigned)index);
		g_disk.set_eject_state(false);
	});
	return ok ? 1 : 0;
}

AB_API int32_t ab_disk_insert(const char *path) {
	std::string p = Str(path);
	bool ok = false;
	RunSync([&] {
		if (!g_haveDisk || !g_disk.add_image_index || !g_disk.replace_image_index
			|| !g_disk.get_num_images)
			return;
		g_disk.set_eject_state(true);
		if (g_disk.add_image_index()) {
			const unsigned idx = g_disk.get_num_images() - 1;
			retro_game_info gi {};
			gi.path = p.c_str();
			if (g_disk.replace_image_index(idx, &gi))
				ok = g_disk.set_image_index(idx);
		}
		g_disk.set_eject_state(false);
	});
	return ok ? 1 : 0;
}

AB_API int32_t ab_poll_log(char *buf, int32_t capacity) {
	std::lock_guard<std::mutex> lock(g_logMutex);
	if (g_logQueue.empty() || !buf || capacity <= 0)
		return -1;
	auto entry = std::move(g_logQueue.front());
	g_logQueue.pop_front();
	std::snprintf(buf, (size_t)capacity, "%s", entry.second.c_str());
	return entry.first;
}

} // extern "C"
