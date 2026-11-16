// Raw dart:ffi bindings for native/altirra_bridge.h.
//
// Kept free of Flutter imports so it can also be used from plain Dart tools
// (see tool/smoke_test.dart).

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _InitN = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _InitD = int Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _VoidN = Void Function();
typedef _VoidD = void Function();
typedef _I32N = Int32 Function();
typedef _I32D = int Function();
typedef _F64N = Double Function();
typedef _F64D = double Function();
typedef _StrN = Pointer<Utf8> Function();
typedef _PathN = Int32 Function(Pointer<Utf8>);
typedef _PathD = int Function(Pointer<Utf8>);
typedef _SetI32N = Void Function(Int32);
typedef _SetI32D = void Function(int);
typedef _I32toI32N = Int32 Function(Int32);
typedef _I32toI32D = int Function(int);
typedef _FrameCopyN = Uint64 Function(
    Pointer<Uint8>, Int32, Pointer<Int32>, Pointer<Int32>, Uint64);
typedef _FrameCopyD = int Function(
    Pointer<Uint8>, int, Pointer<Int32>, Pointer<Int32>, int);
typedef _SetVolN = Void Function(Float);
typedef _SetVolD = void Function(double);
typedef _JoypadN = Void Function(Int32, Uint32);
typedef _JoypadD = void Function(int, int);
typedef _KeyN = Void Function(Int32, Uint32, Uint32, Uint32);
typedef _KeyD = void Function(int, int, int, int);
typedef _AnalogN = Void Function(Int32, Int32, Int32, Int32);
typedef _AnalogD = void Function(int, int, int, int);
typedef _PointerN = Void Function(Int32, Int32, Int32);
typedef _PointerD = void Function(int, int, int);
typedef _OptStrN = Pointer<Utf8> Function(Int32);
typedef _OptStrD = Pointer<Utf8> Function(int);
typedef _OptValN = Pointer<Utf8> Function(Int32, Int32);
typedef _OptValD = Pointer<Utf8> Function(int, int);
typedef _GetOptN = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _SetOptN = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _SetOptD = int Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _PollLogN = Int32 Function(Pointer<Utf8>, Int32);
typedef _PollLogD = int Function(Pointer<Utf8>, int);

/// Thin typed wrapper over the exported `ab_*` functions.
class AltirraBindings {
  AltirraBindings(DynamicLibrary lib)
      : init = lib.lookupFunction<_InitN, _InitD>('ab_init'),
        shutdown = lib.lookupFunction<_VoidN, _VoidD>('ab_shutdown'),
        coreVersion = lib.lookupFunction<_StrN, _StrN>('ab_core_version'),
        load = lib.lookupFunction<_PathN, _PathD>('ab_load'),
        unload = lib.lookupFunction<_VoidN, _VoidD>('ab_unload'),
        isLoaded = lib.lookupFunction<_I32N, _I32D>('ab_is_loaded'),
        setPaused = lib.lookupFunction<_SetI32N, _SetI32D>('ab_set_paused'),
        isPaused = lib.lookupFunction<_I32N, _I32D>('ab_is_paused'),
        setSpeed = lib.lookupFunction<_SetI32N, _SetI32D>('ab_set_speed'),
        coldReset = lib.lookupFunction<_VoidN, _VoidD>('ab_cold_reset'),
        warmReset = lib.lookupFunction<_VoidN, _VoidD>('ab_warm_reset'),
        frameCopy =
            lib.lookupFunction<_FrameCopyN, _FrameCopyD>('ab_frame_copy'),
        getFps = lib.lookupFunction<_F64N, _F64D>('ab_get_fps'),
        getAspect = lib.lookupFunction<_F64N, _F64D>('ab_get_aspect'),
        getMeasuredFps =
            lib.lookupFunction<_F64N, _F64D>('ab_get_measured_fps'),
        setVolume = lib.lookupFunction<_SetVolN, _SetVolD>('ab_set_volume'),
        audioOk = lib.lookupFunction<_I32N, _I32D>('ab_audio_ok'),
        setJoypad = lib.lookupFunction<_JoypadN, _JoypadD>('ab_set_joypad'),
        keyEvent = lib.lookupFunction<_KeyN, _KeyD>('ab_key_event'),
        setAnalog = lib.lookupFunction<_AnalogN, _AnalogD>('ab_set_analog'),
        setPointer =
            lib.lookupFunction<_PointerN, _PointerD>('ab_set_pointer'),
        setPortDevice =
            lib.lookupFunction<_JoypadN, _JoypadD>('ab_set_port_device'),
        optionCount = lib.lookupFunction<_I32N, _I32D>('ab_option_count'),
        optionKey = lib.lookupFunction<_OptStrN, _OptStrD>('ab_option_key'),
        optionDesc = lib.lookupFunction<_OptStrN, _OptStrD>('ab_option_desc'),
        optionInfo = lib.lookupFunction<_OptStrN, _OptStrD>('ab_option_info'),
        optionCategory =
            lib.lookupFunction<_OptStrN, _OptStrD>('ab_option_category'),
        optionDefault =
            lib.lookupFunction<_OptStrN, _OptStrD>('ab_option_default'),
        optionValueCount =
            lib.lookupFunction<_I32toI32N, _I32toI32D>('ab_option_value_count'),
        optionValue = lib.lookupFunction<_OptValN, _OptValD>('ab_option_value'),
        optionValueLabel =
            lib.lookupFunction<_OptValN, _OptValD>('ab_option_value_label'),
        optionVisible =
            lib.lookupFunction<_I32toI32N, _I32toI32D>('ab_option_visible'),
        getOption = lib.lookupFunction<_GetOptN, _GetOptN>('ab_get_option'),
        setOption = lib.lookupFunction<_SetOptN, _SetOptD>('ab_set_option'),
        saveState = lib.lookupFunction<_PathN, _PathD>('ab_save_state'),
        loadState = lib.lookupFunction<_PathN, _PathD>('ab_load_state'),
        diskCount = lib.lookupFunction<_I32N, _I32D>('ab_disk_count'),
        diskIndex = lib.lookupFunction<_I32N, _I32D>('ab_disk_index'),
        diskSelect =
            lib.lookupFunction<_I32toI32N, _I32toI32D>('ab_disk_select'),
        diskInsert = lib.lookupFunction<_PathN, _PathD>('ab_disk_insert'),
        pollLog = lib.lookupFunction<_PollLogN, _PollLogD>('ab_poll_log');

  /// Opens the platform's bridge library.
  ///
  /// [overridePath] lets tests point at a freshly built library.
  factory AltirraBindings.open({String? overridePath}) {
    if (overridePath != null) {
      return AltirraBindings(DynamicLibrary.open(overridePath));
    }
    final DynamicLibrary lib;
    if (Platform.isIOS) {
      // Linked statically into the Runner via the Xcode build phase.
      lib = DynamicLibrary.process();
    } else if (Platform.isMacOS) {
      lib = DynamicLibrary.open('libaltirra_bridge.dylib');
    } else if (Platform.isWindows) {
      lib = DynamicLibrary.open('altirra_bridge.dll');
    } else {
      lib = DynamicLibrary.open('libaltirra_bridge.so');
    }
    return AltirraBindings(lib);
  }

  final _InitD init;
  final _VoidD shutdown;
  final _StrN coreVersion;
  final _PathD load;
  final _VoidD unload;
  final _I32D isLoaded;
  final _SetI32D setPaused;
  final _I32D isPaused;
  final _SetI32D setSpeed;
  final _VoidD coldReset;
  final _VoidD warmReset;
  final _FrameCopyD frameCopy;
  final _F64D getFps;
  final _F64D getAspect;
  final _F64D getMeasuredFps;
  final _SetVolD setVolume;
  final _I32D audioOk;
  final _JoypadD setJoypad;
  final _KeyD keyEvent;
  final _AnalogD setAnalog;
  final _PointerD setPointer;
  final _JoypadD setPortDevice;
  final _I32D optionCount;
  final _OptStrD optionKey;
  final _OptStrD optionDesc;
  final _OptStrD optionInfo;
  final _OptStrD optionCategory;
  final _OptStrD optionDefault;
  final _I32toI32D optionValueCount;
  final _OptValD optionValue;
  final _OptValD optionValueLabel;
  final _I32toI32D optionVisible;
  final _GetOptN getOption;
  final _SetOptD setOption;
  final _PathD saveState;
  final _PathD loadState;
  final _I32D diskCount;
  final _I32D diskIndex;
  final _I32toI32D diskSelect;
  final _PathD diskInsert;
  final _PollLogD pollLog;
}

/// Converts a possibly-null C string to Dart.
String? cString(Pointer<Utf8> p) => p == nullptr ? null : p.toDartString();

/// Calls [fn] with a temporary native UTF-8 copy of [s] (null -> nullptr).
T withCString<T>(String? s, T Function(Pointer<Utf8>) fn) {
  if (s == null) return fn(nullptr);
  final p = s.toNativeUtf8();
  try {
    return fn(p);
  } finally {
    malloc.free(p);
  }
}
