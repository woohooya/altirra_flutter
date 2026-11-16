// altirra_bridge.h - C ABI between the Flutter/Dart UI and the Altirra
// libretro core.
//
// Copyright (C) 2026 altirra_flutter contributors
// Licensed under the GNU General Public License v2 or later (same as Altirra).
//
// Design notes
// ------------
// The libretro core is single-threaded and expects every retro_* call to come
// from the same thread. The bridge therefore owns a dedicated emulation thread
// which:
//   * runs retro_run() paced to the emulated video rate,
//   * steers that pacing slightly using the audio ring-buffer fill level so
//     audio neither underruns nor accumulates latency,
//   * executes "commands" (load, reset, save state, option changes...) that
//     Dart posts through this API, between frames.
//
// Dart never receives callbacks. It polls for new video frames once per
// Flutter vsync (ab_frame_copy) and pushes input state (ab_set_joypad,
// ab_key_event). Every function in this header is safe to call from any one
// Dart isolate.

#ifndef ALTIRRA_BRIDGE_H
#define ALTIRRA_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define AB_API __declspec(dllexport)
#else
#define AB_API __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// ---- lifecycle -----------------------------------------------------------

// Initialise the core and start the emulation thread. `system_dir` holds
// optional firmware (the core ships its own replacement ROMs, so it may be
// empty); `save_dir` receives disk sidecars/NVRAM. Returns 1 on success.
AB_API int32_t ab_init(const char *system_dir, const char *save_dir);
AB_API void ab_shutdown(void);
AB_API const char *ab_core_version(void);

// Load content (ATR/XEX/CAR/CAS/...). Pass NULL or "" to boot with no media
// (AltirraOS + optional BASIC). Blocks until the core has loaded the content.
// Returns 1 on success.
AB_API int32_t ab_load(const char *path);
AB_API void ab_unload(void);
AB_API int32_t ab_is_loaded(void);

AB_API void ab_set_paused(int32_t paused);
AB_API int32_t ab_is_paused(void);
// Fast forward: run up to `multiplier` emulated frames per host frame.
// 1 = normal speed.
AB_API void ab_set_speed(int32_t multiplier);

AB_API void ab_cold_reset(void);
// Warm reset is implemented with the core's RetroPad "Select+Start" combo.
AB_API void ab_warm_reset(void);

// ---- video ---------------------------------------------------------------

// Copies the most recent frame as tightly packed RGBA8888 into `dst` if it is
// newer than `last_seq`. Returns the frame sequence number (> 0) when a new
// frame was copied, 0 otherwise. Fails (returns 0) if `capacity` is too small;
// in that case *w / *h still receive the required dimensions.
AB_API uint64_t ab_frame_copy(uint8_t *dst, int32_t capacity, int32_t *w,
	int32_t *h, uint64_t last_seq);
AB_API double ab_get_fps(void);
AB_API double ab_get_aspect(void);
// Measured emulation speed in frames/s (useful for an on-screen FPS meter).
AB_API double ab_get_measured_fps(void);

// ---- audio ---------------------------------------------------------------

AB_API void ab_set_volume(float volume);  // 0..1
AB_API int32_t ab_audio_ok(void);         // 1 if the output device opened

// ---- input ---------------------------------------------------------------

// RetroPad bitmask: bit N == RETRO_DEVICE_ID_JOYPAD_N.
AB_API void ab_set_joypad(int32_t port, uint32_t mask);
// libretro keyboard event (RETROK_* keycode, UTF-32 character, RETROKMOD_*).
AB_API void ab_key_event(int32_t down, uint32_t keycode, uint32_t character,
	uint32_t modifiers);
// Analog stick (RETRO_DEVICE_ANALOG index/id), -32768..32767.
AB_API void ab_set_analog(int32_t port, int32_t index, int32_t id,
	int32_t value);
// Pointer/lightpen/mouse position normalized to -0x7fff..0x7fff plus pressed.
AB_API void ab_set_pointer(int32_t x, int32_t y, int32_t pressed);
AB_API void ab_set_port_device(int32_t port, uint32_t device);

// ---- core options --------------------------------------------------------

AB_API int32_t ab_option_count(void);
AB_API const char *ab_option_key(int32_t index);
AB_API const char *ab_option_desc(int32_t index);
AB_API const char *ab_option_info(int32_t index);
AB_API const char *ab_option_category(int32_t index);
AB_API const char *ab_option_default(int32_t index);
AB_API int32_t ab_option_value_count(int32_t index);
AB_API const char *ab_option_value(int32_t index, int32_t value_index);
AB_API const char *ab_option_value_label(int32_t index, int32_t value_index);
AB_API int32_t ab_option_visible(int32_t index);
AB_API const char *ab_get_option(const char *key);
AB_API int32_t ab_set_option(const char *key, const char *value);

// ---- save states ---------------------------------------------------------

AB_API int32_t ab_save_state(const char *path);
AB_API int32_t ab_load_state(const char *path);

// ---- disks ---------------------------------------------------------------

AB_API int32_t ab_disk_count(void);
AB_API int32_t ab_disk_index(void);
AB_API int32_t ab_disk_select(int32_t index);
// Adds `path` to the disk list and inserts it into D1:.
AB_API int32_t ab_disk_insert(const char *path);

// ---- diagnostics ---------------------------------------------------------

// Pops one buffered core log line into `buf`. Returns the log level (0..3) or
// -1 when the queue is empty.
AB_API int32_t ab_poll_log(char *buf, int32_t capacity);

#ifdef __cplusplus
}
#endif

#endif
