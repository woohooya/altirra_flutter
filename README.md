# Altirra Flutter

A cross-platform Flutter/Dart frontend for the [Altirra](https://www.virtualdub.org/altirra.html) Atari 8-bit & 5200 emulator, built on top of the [AltirraSDL](https://github.com/ilmenit/AltirraSDL) libretro core via `dart:ffi`.

## Architecture

- **Upstream core (`third_party/AltirraSDL`)**: Unmodified submodule providing the cycle-accurate Altirra emulation engine (`AltirraLibretro`).
- **Native bridge (`native/altirra_bridge.cpp`, `native/bridge.cmake`)**:
  - Runs `retro_run()` on a dedicated emulation thread paced to the emulated video rate with audio-buffer-steered dynamic rate control.
  - Plays audio via `miniaudio` (AAudio/OpenSL ES on Android, ALSA/PulseAudio on Linux, CoreAudio on iOS/macOS).
  - Exposes a poll-based C ABI (`native/altirra_bridge.h`) for video frames, input, core options, save states, and disk swapping.
- **Flutter/Dart frontend (`lib/`)**:
  - `src/core/`: `dart:ffi` bindings, `Emulator` controller, `CoreOption` model, libretro key/pad constants.
  - `src/emulator/`: `AtariScreen` vsync `Ticker` + `ui.decodeImageFromPixels` renderer.
  - `src/input/`: Multi-touch virtual joystick + Fire/Start/Select/Option buttons, collapsible Atari 800XL on-screen keyboard, and hardware keyboard mapper.
  - `src/ui/`: Library/recent files screen, full-screen play view with HUD, save states, disk swap, and categorized core settings.

## Building

### Prerequisites
- Flutter SDK (tested with 3.50.0)
- CMake 3.24+ and a C++17 compiler
- For Android: Android SDK & NDK (e.g. `28.2.13676358`)

### 1. Build native libraries
```bash
# Linux + Android (arm64-v8a)
./scripts/build_native.sh all

# Or individually:
./scripts/build_native.sh linux
./scripts/build_native.sh android arm64-v8a
```

### 2. Run / package Flutter app
```bash
# Linux desktop
flutter run -d linux
flutter build linux --release

# Android APK
flutter build apk --release
```

### iOS notes
`AltirraBindings.open()` uses `DynamicLibrary.process()` on iOS. To build for iOS on macOS with Xcode, compile `AltirraLibretro` and `altirra_bridge` as static/embedded libraries for `OS64` using `native/bridge.cmake` and link them into the `Runner` target.

## License

Licensed under the **GNU General Public License v2 or later** (same as Altirra and AltirraSDL).
