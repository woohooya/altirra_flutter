import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'altirra_bindings.dart';
import 'core_option.dart';
import 'retro_keys.dart';

/// Where a joystick bit came from. Bits from all sources are OR'd together so
/// e.g. the touch stick and a Bluetooth gamepad can be used simultaneously.
enum InputSource { touch, keyboard, gamepad }

/// High-level, app-wide facade over the native emulator.
class Emulator extends ChangeNotifier {
  Emulator._();
  static final Emulator instance = Emulator._();

  late final AltirraBindings _ab;
  late final SharedPreferences _prefs;
  late final Directory _dataDir;

  bool _initialized = false;
  bool get initialized => _initialized;

  String? _contentPath;
  /// Path of the loaded content, or null when booted without media.
  String? get contentPath => _contentPath;
  bool get isRunning => _initialized && _ab.isLoaded() == 1;

  bool _paused = false;
  bool get paused => _paused;

  int _speed = 1;
  int get speed => _speed;

  String get coreVersion => cString(_ab.coreVersion()) ?? 'Altirra';
  bool get audioOk => _ab.audioOk() == 1;
  double get aspect => _ab.getAspect();
  double get measuredFps => _ab.getMeasuredFps();
  Directory get dataDir => _dataDir;
  Directory get libraryDir => Directory(p.join(_dataDir.path, 'library'));
  Directory get statesDir => Directory(p.join(_dataDir.path, 'states'));

  final Map<InputSource, int> _padBits = {
    for (final s in InputSource.values) s: 0,
  };

  // Frame buffers handed to the Flutter engine. Two of them so the engine can
  // still be uploading one while we copy the next.
  final List<Pointer<Uint8>> _frameBufs = [nullptr, nullptr];
  int _frameCap = 0;
  int _frameBufIndex = 0;
  int _lastSeq = 0;
  final Pointer<Int32> _w = calloc<Int32>();
  final Pointer<Int32> _h = calloc<Int32>();

  // ---- frontend settings (persisted) ---------------------------------------

  double get volume => _prefs.getDouble('ui.volume') ?? 1.0;
  set volume(double v) {
    _prefs.setDouble('ui.volume', v);
    _ab.setVolume(v);
    notifyListeners();
  }

  bool get smoothScaling => _prefs.getBool('ui.smooth') ?? false;
  set smoothScaling(bool v) {
    _prefs.setBool('ui.smooth', v);
    notifyListeners();
  }

  bool get showTouchControls => _prefs.getBool('ui.touch') ?? true;
  set showTouchControls(bool v) {
    _prefs.setBool('ui.touch', v);
    notifyListeners();
  }

  bool get haptics => _prefs.getBool('ui.haptics') ?? true;
  set haptics(bool v) {
    _prefs.setBool('ui.haptics', v);
    notifyListeners();
  }

  /// Arrow keys + Alt act as joystick instead of Atari cursor keys.
  bool get keyboardJoystick => _prefs.getBool('ui.kbjoy') ?? true;
  set keyboardJoystick(bool v) {
    _prefs.setBool('ui.kbjoy', v);
    notifyListeners();
  }

  double get controlsOpacity => _prefs.getDouble('ui.opacity') ?? 0.55;
  set controlsOpacity(double v) {
    _prefs.setDouble('ui.opacity', v);
    notifyListeners();
  }

  List<String> get recent => _prefs.getStringList('library.recent') ?? [];

  // ---- lifecycle -----------------------------------------------------------

  Future<void> init({String? libraryOverride}) async {
    if (_initialized) return;
    _ab = AltirraBindings.open(overridePath: libraryOverride);
    _prefs = await SharedPreferences.getInstance();
    final support = await getApplicationSupportDirectory();
    _dataDir = Directory(p.join(support.path, 'altirra'));
    final systemDir = Directory(p.join(_dataDir.path, 'system'));
    final saveDir = Directory(p.join(_dataDir.path, 'saves'));
    for (final d in [systemDir, saveDir, libraryDir, statesDir]) {
      d.createSync(recursive: true);
    }

    withCString(systemDir.path,
        (s) => withCString(saveDir.path, (v) => _ab.init(s, v)));

    // Re-apply the user's persisted core option overrides.
    for (final key in _prefs.getKeys().where((k) => k.startsWith('opt.'))) {
      _setCoreOption(key.substring(4), _prefs.getString(key)!);
    }
    _ab.setVolume(volume);
    _initialized = true;
    notifyListeners();
  }

  // ---- content -------------------------------------------------------------

  /// Loads [path] (or boots without media when null). Returns true on success.
  Future<bool> load(String? path) async {
    final ok = withCString(path, (s) => _ab.load(s)) == 1;
    if (ok) {
      _contentPath = path;
      _lastSeq = 0;
      setPaused(false);
      setSpeed(1);
      if (path != null) _addRecent(path);
    }
    notifyListeners();
    return ok;
  }

  void unload() {
    _ab.unload();
    _contentPath = null;
    releaseAllInput();
    notifyListeners();
  }

  /// Copies a user-picked file into the app's library so it survives cache
  /// clean-ups (Android hands out temporary copies). Returns the new path.
  Future<String> importFile(String sourcePath, {String? name}) async {
    final dest = File(p.join(libraryDir.path, name ?? p.basename(sourcePath)));
    if (p.equals(p.canonicalize(sourcePath), p.canonicalize(dest.path))) {
      return dest.path;
    }
    await File(sourcePath).copy(dest.path);
    return dest.path;
  }

  void _addRecent(String path) {
    final list = recent..remove(path);
    list.insert(0, path);
    _prefs.setStringList('library.recent', list.take(50).toList());
  }

  void removeRecent(String path) {
    final list = recent..remove(path);
    _prefs.setStringList('library.recent', list);
    notifyListeners();
  }

  void setPaused(bool paused) {
    _paused = paused;
    _ab.setPaused(paused ? 1 : 0);
    if (paused) releaseAllInput();
    notifyListeners();
  }

  void setSpeed(int multiplier) {
    _speed = multiplier;
    _ab.setSpeed(multiplier);
    notifyListeners();
  }

  void coldReset() => _ab.coldReset();
  void warmReset() => _ab.warmReset();

  // ---- video ---------------------------------------------------------------

  /// Returns a new RGBA frame if one is available since the last call.
  ///
  /// The returned bytes are a view of native memory that stays valid until the
  /// call after next.
  ({Uint8List pixels, int width, int height})? pollFrame() {
    if (!_initialized) return null;
    _ab.frameCopy(nullptr, 0, _w, _h, _lastSeq);
    final need = _w.value * _h.value * 4;
    if (need <= 0) return null;
    if (need > _frameCap) {
      for (var i = 0; i < 2; i++) {
        if (_frameBufs[i] != nullptr) calloc.free(_frameBufs[i]);
        _frameBufs[i] = calloc<Uint8>(need);
      }
      _frameCap = need;
    }
    _frameBufIndex ^= 1;
    final buf = _frameBufs[_frameBufIndex];
    final seq = _ab.frameCopy(buf, _frameCap, _w, _h, _lastSeq);
    if (seq == 0) return null;
    _lastSeq = seq;
    return (
      pixels: buf.asTypedList(_w.value * _h.value * 4),
      width: _w.value,
      height: _h.value,
    );
  }

  // ---- input ---------------------------------------------------------------

  void setPad(InputSource source, int bits) {
    if (_padBits[source] == bits) return;
    _padBits[source] = bits;
    _ab.setJoypad(0, _padBits.values.fold(0, (a, b) => a | b));
  }

  int padBits(InputSource source) => _padBits[source]!;

  final Set<int> _heldKeys = {};

  void keyDown(int keycode, {int character = 0, int mods = 0}) {
    if (keycode != 0) _heldKeys.add(keycode);
    _ab.keyEvent(1, keycode, character, mods);
  }

  void keyUp(int keycode, {int mods = 0}) {
    _heldKeys.remove(keycode);
    _ab.keyEvent(0, keycode, 0, mods);
  }

  /// Types a character through the core's ATASCII translation (no hold).
  void typeCharacter(int character) => _ab.keyEvent(1, 0, character, 0);

  void releaseAllInput() {
    for (final k in _heldKeys.toList()) {
      keyUp(k);
    }
    for (final s in InputSource.values) {
      setPad(s, 0);
    }
  }

  void consoleKey(String which, bool down) {
    final key = switch (which) {
      'start' => RetroKey.consoleStart,
      'select' => RetroKey.consoleSelect,
      'option' => RetroKey.consoleOption,
      'help' => RetroKey.help,
      'break' => RetroKey.atariBreak,
      _ => 0,
    };
    if (key == 0) return;
    down ? keyDown(key) : keyUp(key);
  }

  // ---- core options --------------------------------------------------------

  List<CoreOption> coreOptions() {
    final n = _ab.optionCount();
    return [
      for (var i = 0; i < n; i++)
        CoreOption(
          key: cString(_ab.optionKey(i))!,
          label: cString(_ab.optionDesc(i)) ?? '',
          info: cString(_ab.optionInfo(i)) ?? '',
          category: cString(_ab.optionCategory(i)) ?? '',
          defaultValue: cString(_ab.optionDefault(i)) ?? '',
          visible: _ab.optionVisible(i) == 1,
          values: [
            for (var v = 0; v < _ab.optionValueCount(i); v++)
              (
                value: cString(_ab.optionValue(i, v))!,
                label: cString(_ab.optionValueLabel(i, v)) ?? '',
              ),
          ],
        ),
    ];
  }

  String? coreOption(String key) =>
      withCString(key, (k) => cString(_ab.getOption(k)));

  void setCoreOption(String key, String value, {String? defaultValue}) {
    _setCoreOption(key, value);
    if (value == defaultValue) {
      _prefs.remove('opt.$key');
    } else {
      _prefs.setString('opt.$key', value);
    }
    notifyListeners();
  }

  void _setCoreOption(String key, String value) =>
      withCString(key, (k) => withCString(value, (v) => _ab.setOption(k, v)));

  void resetCoreOptions() {
    for (final o in coreOptions()) {
      _setCoreOption(o.key, o.defaultValue);
      _prefs.remove('opt.${o.key}');
    }
    notifyListeners();
  }

  // ---- save states ---------------------------------------------------------

  String statePath(int slot) {
    final base = _contentPath == null
        ? '_nomedia'
        : p.basenameWithoutExtension(_contentPath!);
    return p.join(statesDir.path, '$base.$slot.state');
  }

  bool hasState(int slot) => File(statePath(slot)).existsSync();

  bool saveState(int slot) =>
      withCString(statePath(slot), (s) => _ab.saveState(s)) == 1;

  bool loadState(int slot) =>
      withCString(statePath(slot), (s) => _ab.loadState(s)) == 1;

  // ---- disks ---------------------------------------------------------------

  int get diskCount => _ab.diskCount();
  int get diskIndex => _ab.diskIndex();
  bool selectDisk(int index) => _ab.diskSelect(index) == 1;
  bool insertDisk(String path) =>
      withCString(path, (s) => _ab.diskInsert(s)) == 1;

  // ---- diagnostics ---------------------------------------------------------

  List<String> drainLog() {
    final out = <String>[];
    final buf = calloc<Uint8>(1024).cast<Utf8>();
    try {
      while (_ab.pollLog(buf, 1024) >= 0) {
        out.add(buf.toDartString().trimRight());
      }
    } finally {
      calloc.free(buf);
    }
    return out;
  }
}
