import 'package:altirra_flutter/src/core/core_option.dart';
import 'package:altirra_flutter/src/core/retro_keys.dart';
import 'package:altirra_flutter/src/input/keyboard_mapper.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keyboard mapper translates letters, digits, and special keys', () {
    expect(logicalKeyToRetroKey(LogicalKeyboardKey.keyA), RetroKey.a);
    expect(logicalKeyToRetroKey(LogicalKeyboardKey.keyZ), RetroKey.a + 25);
    expect(logicalKeyToRetroKey(LogicalKeyboardKey.digit0), RetroKey.k0);
    expect(logicalKeyToRetroKey(LogicalKeyboardKey.digit9), RetroKey.k9);
    expect(logicalKeyToRetroKey(LogicalKeyboardKey.enter), RetroKey.returnKey);
    expect(logicalKeyToRetroKey(LogicalKeyboardKey.f2), RetroKey.consoleStart);
    expect(logicalKeyToRetroKey(LogicalKeyboardKey.f6), RetroKey.help);
  });

  test('CoreOption resolves labels and reset requirements', () {
    const opt = CoreOption(
      key: 'altirra_system',
      label: 'System',
      info: '',
      category: 'System',
      defaultValue: 'auto',
      values: [
        (value: 'auto', label: 'Auto'),
        (value: '800xl', label: 'Atari 800XL'),
      ],
      visible: true,
    );
    expect(opt.labelFor('800xl'), 'Atari 800XL');
    expect(opt.labelFor('unknown'), 'unknown');
    expect(opt.needsReset, isTrue);
  });
}
