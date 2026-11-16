import 'package:flutter/services.dart';

import '../core/retro_keys.dart';

/// Maps Flutter [LogicalKeyboardKey] values to libretro `RETROK_*` keycodes.
int? logicalKeyToRetroKey(LogicalKeyboardKey key) {
  final id = key.keyId;
  // ASCII letters a..z
  if (id >= LogicalKeyboardKey.keyA.keyId &&
      id <= LogicalKeyboardKey.keyZ.keyId) {
    return RetroKey.a + (id - LogicalKeyboardKey.keyA.keyId);
  }
  // Digits 0..9
  if (id >= LogicalKeyboardKey.digit0.keyId &&
      id <= LogicalKeyboardKey.digit9.keyId) {
    return RetroKey.k0 + (id - LogicalKeyboardKey.digit0.keyId);
  }
  // Function keys F1..F12
  if (id >= LogicalKeyboardKey.f1.keyId && id <= LogicalKeyboardKey.f12.keyId) {
    return RetroKey.f1 + (id - LogicalKeyboardKey.f1.keyId);
  }
  // Numpad 0..9
  if (id >= LogicalKeyboardKey.numpad0.keyId &&
      id <= LogicalKeyboardKey.numpad9.keyId) {
    return RetroKey.kp0 + (id - LogicalKeyboardKey.numpad0.keyId);
  }

  return _specialMap[key];
}

final Map<LogicalKeyboardKey, int> _specialMap = {
  LogicalKeyboardKey.backspace: RetroKey.backspace,
  LogicalKeyboardKey.tab: RetroKey.tab,
  LogicalKeyboardKey.enter: RetroKey.returnKey,
  LogicalKeyboardKey.escape: RetroKey.escape,
  LogicalKeyboardKey.space: RetroKey.space,
  LogicalKeyboardKey.comma: RetroKey.comma,
  LogicalKeyboardKey.minus: RetroKey.minus,
  LogicalKeyboardKey.period: RetroKey.period,
  LogicalKeyboardKey.slash: RetroKey.slash,
  LogicalKeyboardKey.semicolon: RetroKey.semicolon,
  LogicalKeyboardKey.equal: RetroKey.equals,
  LogicalKeyboardKey.bracketLeft: RetroKey.leftBracket,
  LogicalKeyboardKey.backslash: RetroKey.backslash,
  LogicalKeyboardKey.bracketRight: RetroKey.rightBracket,
  LogicalKeyboardKey.backquote: RetroKey.backquote,
  LogicalKeyboardKey.delete: RetroKey.delete,
  LogicalKeyboardKey.numpadDecimal: RetroKey.kpPeriod,
  LogicalKeyboardKey.numpadDivide: RetroKey.kpDivide,
  LogicalKeyboardKey.numpadMultiply: RetroKey.kpMultiply,
  LogicalKeyboardKey.numpadSubtract: RetroKey.kpMinus,
  LogicalKeyboardKey.numpadAdd: RetroKey.kpPlus,
  LogicalKeyboardKey.numpadEnter: RetroKey.kpEnter,
  LogicalKeyboardKey.arrowUp: RetroKey.up,
  LogicalKeyboardKey.arrowDown: RetroKey.down,
  LogicalKeyboardKey.arrowRight: RetroKey.right,
  LogicalKeyboardKey.arrowLeft: RetroKey.left,
  LogicalKeyboardKey.insert: RetroKey.insert,
  LogicalKeyboardKey.home: RetroKey.home,
  LogicalKeyboardKey.end: RetroKey.end,
  LogicalKeyboardKey.pageUp: RetroKey.pageUp,
  LogicalKeyboardKey.pageDown: RetroKey.pageDown,
  LogicalKeyboardKey.shiftRight: RetroKey.rshift,
  LogicalKeyboardKey.shiftLeft: RetroKey.lshift,
  LogicalKeyboardKey.controlRight: RetroKey.rctrl,
  LogicalKeyboardKey.controlLeft: RetroKey.lctrl,
  LogicalKeyboardKey.pause: RetroKey.breakKey,
};

/// Returns the current `RETROKMOD_*` bitmask from [HardwareKeyboard].
int currentRetroModifiers() {
  final kb = HardwareKeyboard.instance;
  var mods = 0;
  if (kb.isShiftPressed) mods |= RetroMod.shift;
  if (kb.isControlPressed) mods |= RetroMod.ctrl;
  if (kb.isAltPressed) mods |= RetroMod.alt;
  return mods;
}
