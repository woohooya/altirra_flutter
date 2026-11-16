// Headless end-to-end smoke test of the native bridge through dart:ffi.
//
//   dart run tool/smoke_test.dart <path/to/libaltirra_bridge.so> [out.png]
//
// Boots the emulator with BASIC enabled and no media, types
// `PRINT 6*7` + RETURN through the libretro keyboard path, and writes the
// resulting screen to a PNG. Exits non-zero if no frames were produced.

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:altirra_flutter/src/core/altirra_bindings.dart';
import 'package:altirra_flutter/src/core/retro_keys.dart';
import 'package:ffi/ffi.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: smoke_test.dart <libaltirra_bridge.so> [out.png]');
    exit(2);
  }
  final out = args.length > 1 ? args[1] : 'smoke.png';
  final ab = AltirraBindings.open(overridePath: args[0]);

  final tmp = Directory.systemTemp.createTempSync('altirra_smoke');
  withCString(tmp.path, (p) => ab.init(p, p));
  print('core: ${cString(ab.coreVersion())}');
  print('audio device: ${ab.audioOk() == 1 ? "ok" : "unavailable"}');
  print('options: ${ab.optionCount()}');

  withCString('altirra_basic', (k) => withCString('enabled', (v) => ab.setOption(k, v)));
  final ok = ab.load(nullptr);
  print('load(no media): ${ok == 1}  fps=${ab.getFps().toStringAsFixed(3)}');
  if (ok != 1) exit(1);

  // Let the OS boot to the READY prompt.
  await Future<void>.delayed(const Duration(seconds: 4));

  Future<void> tap(int key, {int ch = 0, bool shift = false}) async {
    if (shift) ab.keyEvent(1, RetroKey.lshift, 0, RetroMod.shift);
    ab.keyEvent(1, key, ch, shift ? RetroMod.shift : 0);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    ab.keyEvent(0, key, 0, shift ? RetroMod.shift : 0);
    if (shift) ab.keyEvent(0, RetroKey.lshift, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }

  for (final c in 'print 6'.codeUnits) {
    await tap(c, ch: c);
  }
  await tap(RetroKey.k8, ch: '*'.codeUnitAt(0), shift: true);
  await tap(RetroKey.k7, ch: '7'.codeUnitAt(0));
  await tap(RetroKey.returnKey, ch: 13);
  await Future<void>.delayed(const Duration(seconds: 1));

  final w = calloc<Int32>();
  final h = calloc<Int32>();
  ab.frameCopy(nullptr, 0, w, h, 0);
  final cap = w.value * h.value * 4;
  final buf = calloc<Uint8>(cap);
  final seq = ab.frameCopy(buf, cap, w, h, 0);
  print('frame #$seq  ${w.value}x${h.value}  '
      'measured ${ab.getMeasuredFps().toStringAsFixed(1)} fps');

  final logBuf = calloc<Uint8>(1024).cast<Utf8>();
  while (ab.pollLog(logBuf, 1024) >= 0) {
    stdout.write('  log: ${logBuf.toDartString()}');
  }

  if (seq == 0) {
    stderr.writeln('FAIL: no frame produced');
    exit(1);
  }
  final rgba = Uint8List.fromList(buf.asTypedList(cap));
  File(out).writeAsBytesSync(encodePng(w.value, h.value, rgba));
  print('wrote $out');

  ab.shutdown();
  exit(0);
}

/// Minimal RGBA8 PNG encoder (no filtering) using dart:io's zlib.
Uint8List encodePng(int w, int h, Uint8List rgba) {
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0);
    raw.add(rgba.sublist(y * w * 4, (y + 1) * w * 4));
  }
  final out = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final len = ByteData(4)..setUint32(0, data.length);
    final td = [...type.codeUnits, ...data];
    final crc = ByteData(4)..setUint32(0, _crc32(td));
    out
      ..add(len.buffer.asUint8List())
      ..add(td)
      ..add(crc.buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', zlib.encode(raw.toBytes()));
  chunk('IEND', const []);
  return out.toBytes();
}

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
  }
  return c ^ 0xFFFFFFFF;
}
