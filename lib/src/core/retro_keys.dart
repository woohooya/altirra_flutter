// libretro input constants (subset of libretro.h used by the Altirra core).
// Pure Dart: no Flutter imports.

/// RETROK_* keyboard codes (SDL1-style keysyms).
abstract final class RetroKey {
  static const backspace = 8;
  static const tab = 9;
  static const returnKey = 13;
  static const escape = 27;
  static const space = 32;
  static const comma = 44;
  static const minus = 45;
  static const period = 46;
  static const slash = 47;
  static const k0 = 48;
  static const k1 = 49;
  static const k2 = 50;
  static const k3 = 51;
  static const k4 = 52;
  static const k5 = 53;
  static const k6 = 54;
  static const k7 = 55;
  static const k8 = 56;
  static const k9 = 57;
  static const semicolon = 59;
  static const equals = 61;
  static const leftBracket = 91;
  static const backslash = 92;
  static const rightBracket = 93;
  static const backquote = 96;
  static const a = 97; // a..z are 97..122
  static const delete = 127;
  static const kp0 = 256; // kp0..kp9 are 256..265
  static const kpPeriod = 266;
  static const kpDivide = 267;
  static const kpMultiply = 268;
  static const kpMinus = 269;
  static const kpPlus = 270;
  static const kpEnter = 271;
  static const up = 273;
  static const down = 274;
  static const right = 275;
  static const left = 276;
  static const insert = 277;
  static const home = 278;
  static const end = 279;
  static const pageUp = 280;
  static const pageDown = 281;
  static const f1 = 282; // f1..f12 are 282..293
  static const rshift = 303;
  static const lshift = 304;
  static const rctrl = 305;
  static const lctrl = 306;
  static const breakKey = 318;

  static int letter(String c) => a + (c.toLowerCase().codeUnitAt(0) - 97);
  static int f(int n) => f1 + n - 1;

  // Altirra's default PC keyboard layout for Atari-specific keys.
  static final consoleStart = f(2);
  static final consoleSelect = f(3);
  static final consoleOption = f(4);
  static final help = f(6);
  static final atariBreak = f(7);
  static const clear = home; // Shift+Home also clears
  static const inverse = backquote; // "Fuji"/inverse video key
}

/// RETROKMOD_* modifier bits.
abstract final class RetroMod {
  static const shift = 0x01;
  static const ctrl = 0x02;
  static const alt = 0x04;
}

/// RETRO_DEVICE_ID_JOYPAD_* bits for the RetroPad mask.
abstract final class RetroPad {
  static const b = 1 << 0; // Atari fire
  static const y = 1 << 1;
  static const select = 1 << 2;
  static const start = 1 << 3;
  static const up = 1 << 4;
  static const down = 1 << 5;
  static const left = 1 << 6;
  static const right = 1 << 7;
  static const a = 1 << 8;
  static const x = 1 << 9;
  static const l = 1 << 10;
  static const r = 1 << 11;
  static const l2 = 1 << 12;
  static const r2 = 1 << 13;
  static const l3 = 1 << 14;
  static const r3 = 1 << 15;
}

/// RETRO_DEVICE_* ids used with `ab_set_port_device`.
abstract final class RetroDevice {
  static const none = 0;
  static const joypad = 1;
  static const mouse = 2;
  static const keyboard = 3;
  static const lightgun = 4;
  static const analog = 5;
  static const pointer = 6;
}
