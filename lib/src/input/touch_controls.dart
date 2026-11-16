import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/emulator.dart';
import '../core/retro_keys.dart';

/// Multi-touch virtual joystick + fire + console quick-buttons for mobile.
class TouchControls extends StatefulWidget {
  const TouchControls({super.key});

  @override
  State<TouchControls> createState() => _TouchControlsState();
}

class _TouchControlsState extends State<TouchControls> {
  int _stickBits = 0;
  int _buttonBits = 0;

  void _sync() {
    Emulator.instance.setPad(InputSource.touch, _stickBits | _buttonBits);
  }

  void _updateStick(int bits) {
    if (_stickBits == bits) return;
    if (bits != 0 && _stickBits == 0 && Emulator.instance.haptics) {
      HapticFeedback.selectionClick();
    }
    setState(() => _stickBits = bits);
    _sync();
  }

  void _setButton(int bit, bool down) {
    final next = down ? (_buttonBits | bit) : (_buttonBits & ~bit);
    if (next == _buttonBits) return;
    if (down && Emulator.instance.haptics) {
      HapticFeedback.lightImpact();
    }
    setState(() => _buttonBits = next);
    _sync();
  }

  @override
  void dispose() {
    Emulator.instance.setPad(InputSource.touch, 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = Emulator.instance.controlsOpacity.clamp(0.15, 1.0);
    return IgnorePointer(
      ignoring: false,
      child: Opacity(
        opacity: opacity,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.bottomLeft,
                  child: _VirtualStick(
                    onChanged: _updateStick,
                  ),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Small Atari console switch pills
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ConsolePill(
                            label: 'START',
                            onChanged: (d) =>
                                Emulator.instance.consoleKey('start', d),
                          ),
                          const SizedBox(width: 6),
                          _ConsolePill(
                            label: 'SEL',
                            onChanged: (d) =>
                                Emulator.instance.consoleKey('select', d),
                          ),
                          const SizedBox(width: 6),
                          _ConsolePill(
                            label: 'OPT',
                            onChanged: (d) =>
                                Emulator.instance.consoleKey('option', d),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _KeyRoundButton(
                                label: 'RET',
                                size: 44,
                                onChanged: (d) => d
                                    ? Emulator.instance
                                        .keyDown(RetroKey.returnKey, character: 13)
                                    : Emulator.instance
                                        .keyUp(RetroKey.returnKey),
                              ),
                              const SizedBox(height: 8),
                              _KeyRoundButton(
                                label: 'SPC',
                                size: 44,
                                onChanged: (d) => d
                                    ? Emulator.instance
                                        .keyDown(RetroKey.space, character: 32)
                                    : Emulator.instance.keyUp(RetroKey.space),
                              ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          _FireButton(
                            pressed: (_buttonBits & RetroPad.b) != 0,
                            onChanged: (d) => _setButton(RetroPad.b, d),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VirtualStick extends StatefulWidget {
  const _VirtualStick({required this.onChanged});

  final ValueChanged<int> onChanged;

  @override
  State<_VirtualStick> createState() => _VirtualStickState();
}

class _VirtualStickState extends State<_VirtualStick> {
  static const double _size = 136;
  static const double _knobRadius = 26;
  static const double _maxOffset = (_size / 2) - _knobRadius - 4;

  Offset _knob = Offset.zero;
  int? _activePointer;

  void _handlePoint(Offset local) {
    const center = Offset(_size / 2, _size / 2);
    var delta = local - center;
    final dist = delta.distance;
    if (dist > _maxOffset && dist > 0) {
      delta = delta * (_maxOffset / dist);
    }
    setState(() => _knob = delta);

    const dead = 12.0;
    var bits = 0;
    if (dist >= dead) {
      final angle = math.atan2(delta.dy, delta.dx); // -pi..pi, 0 is right
      final deg = angle * 180 / math.pi;
      // 8-way sectors (each 45° wide, overlapping on diagonals)
      if (deg > -67.5 && deg < 67.5) bits |= RetroPad.right;
      if (deg > 112.5 || deg < -112.5) bits |= RetroPad.left;
      if (deg > 22.5 && deg < 157.5) bits |= RetroPad.down;
      if (deg < -22.5 && deg > -157.5) bits |= RetroPad.up;
    }
    widget.onChanged(bits);
  }

  void _reset() {
    _activePointer = null;
    setState(() => _knob = Offset.zero);
    widget.onChanged(0);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) {
        if (_activePointer != null) return;
        _activePointer = e.pointer;
        _handlePoint(e.localPosition);
      },
      onPointerMove: (e) {
        if (e.pointer == _activePointer) _handlePoint(e.localPosition);
      },
      onPointerUp: (e) {
        if (e.pointer == _activePointer) _reset();
      },
      onPointerCancel: (e) {
        if (e.pointer == _activePointer) _reset();
      },
      child: SizedBox(
        width: _size,
        height: _size,
        child: CustomPaint(
          painter: _StickPainter(_knob),
        ),
      ),
    );
  }
}

class _StickPainter extends CustomPainter {
  _StickPainter(this.knob);
  final Offset knob;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, size.width / 2, outer);
    canvas.drawCircle(center, size.width / 2 - 1, border);

    // Subtle crosshairs
    final cross = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1.5;
    canvas.drawLine(
        Offset(center.dx, 14), Offset(center.dx, size.height - 14), cross);
    canvas.drawLine(
        Offset(14, center.dy), Offset(size.width - 14, center.dy), cross);

    final knobPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center + knob, 26, knobPaint);
  }

  @override
  bool shouldRepaint(_StickPainter old) => old.knob != knob;
}

class _FireButton extends StatelessWidget {
  const _FireButton({required this.pressed, required this.onChanged});

  final bool pressed;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onChanged(true),
      onPointerUp: (_) => onChanged(false),
      onPointerCancel: (_) => onChanged(false),
      child: Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: pressed
              ? const Color(0xFFFF6D00).withValues(alpha: 0.75)
              : const Color(0xFFE65100).withValues(alpha: 0.45),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.5),
            width: 2.5,
          ),
        ),
        alignment: Alignment.center,
        child: const Text(
          'FIRE',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

class _KeyRoundButton extends StatefulWidget {
  const _KeyRoundButton({
    required this.label,
    required this.size,
    required this.onChanged,
  });

  final String label;
  final double size;
  final ValueChanged<bool> onChanged;

  @override
  State<_KeyRoundButton> createState() => _KeyRoundButtonState();
}

class _KeyRoundButtonState extends State<_KeyRoundButton> {
  bool _down = false;

  void _set(bool d) {
    if (_down == d) return;
    if (d && Emulator.instance.haptics) HapticFeedback.selectionClick();
    setState(() => _down = d);
    widget.onChanged(d);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: _down ? 0.42 : 0.2),
          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ConsolePill extends StatefulWidget {
  const _ConsolePill({required this.label, required this.onChanged});

  final String label;
  final ValueChanged<bool> onChanged;

  @override
  State<_ConsolePill> createState() => _ConsolePillState();
}

class _ConsolePillState extends State<_ConsolePill> {
  bool _down = false;

  void _set(bool d) {
    if (_down == d) return;
    if (d && Emulator.instance.haptics) HapticFeedback.selectionClick();
    setState(() => _down = d);
    widget.onChanged(d);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.black.withValues(alpha: _down ? 0.75 : 0.45),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Compact on-screen Atari 800XL keyboard overlay.
class AtariKeyboardOverlay extends StatefulWidget {
  const AtariKeyboardOverlay({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<AtariKeyboardOverlay> createState() => _AtariKeyboardOverlayState();
}

class _AtariKeyboardOverlayState extends State<AtariKeyboardOverlay> {
  bool _shift = false;
  bool _ctrl = false;

  int get _mods =>
      (_shift ? RetroMod.shift : 0) | (_ctrl ? RetroMod.ctrl : 0);

  void _toggleShift() {
    setState(() => _shift = !_shift);
    if (_shift) {
      Emulator.instance.keyDown(RetroKey.lshift, mods: _mods);
    } else {
      Emulator.instance.keyUp(RetroKey.lshift, mods: _mods);
    }
  }

  void _toggleCtrl() {
    setState(() => _ctrl = !_ctrl);
    if (_ctrl) {
      Emulator.instance.keyDown(RetroKey.lctrl, mods: _mods);
    } else {
      Emulator.instance.keyUp(RetroKey.lctrl, mods: _mods);
    }
  }

  @override
  void dispose() {
    if (_shift) Emulator.instance.keyUp(RetroKey.lshift);
    if (_ctrl) Emulator.instance.keyUp(RetroKey.lctrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xEE181615),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Console & special row
              _row([
                _consoleKey('START', 'start', accent: true),
                _consoleKey('SELECT', 'select', accent: true),
                _consoleKey('OPTION', 'option', accent: true),
                _consoleKey('HELP', 'help'),
                _consoleKey('BREAK', 'break'),
                _key('CLR', RetroKey.clear),
                _key('INV', RetroKey.inverse),
                _ActionKey(
                  label: 'HIDE',
                  onTap: widget.onClose,
                ),
              ]),
              const SizedBox(height: 4),
              // Number row
              _row([
                _key('ESC', RetroKey.escape, ch: 27),
                for (var i = 1; i <= 9; i++)
                  _charKey('$i', RetroKey.k0 + i, shifted: _shiftedDigit(i)),
                _charKey('0', RetroKey.k0, shifted: ')'),
                _charKey('-', RetroKey.minus, shifted: '_'),
                _charKey('=', RetroKey.equals, shifted: '+'),
                _key('DEL', RetroKey.backspace, ch: 8, flex: 14),
              ]),
              const SizedBox(height: 4),
              // QWERTY
              _row([
                _key('TAB', RetroKey.tab, ch: 9, flex: 12),
                for (final c in 'QWERTYUIOP'.split(''))
                  _letterKey(c),
                _charKey('[', RetroKey.leftBracket, shifted: '{'),
                _charKey(']', RetroKey.rightBracket, shifted: '}'),
              ]),
              const SizedBox(height: 4),
              // ASDF
              _row([
                _ModKey(label: 'CTRL', active: _ctrl, onTap: _toggleCtrl, flex: 14),
                for (final c in 'ASDFGHJKL'.split(''))
                  _letterKey(c),
                _charKey(';', RetroKey.semicolon, shifted: ':'),
                _key('RET', RetroKey.returnKey, ch: 13, flex: 16),
              ]),
              const SizedBox(height: 4),
              // ZXCV + Space
              _row([
                _ModKey(
                    label: 'SHIFT', active: _shift, onTap: _toggleShift, flex: 16),
                for (final c in 'ZXCVBNM'.split(''))
                  _letterKey(c),
                _charKey(',', RetroKey.comma, shifted: '<'),
                _charKey('.', RetroKey.period, shifted: '>'),
                _charKey('/', RetroKey.slash, shifted: '?'),
                _key('SPC', RetroKey.space, ch: 32, flex: 20),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  String _shiftedDigit(int d) => const [
        ')',
        '!',
        '@',
        '#',
        r'$',
        '%',
        '^',
        '&',
        '*',
        '(',
      ][d];

  Widget _row(List<Widget> children) => Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            children[i],
          ],
        ],
      );

  Widget _letterKey(String upper) {
    final lower = upper.toLowerCase();
    final ch = (_shift ? upper : lower).codeUnitAt(0);
    return _key(
      _shift ? upper : lower,
      RetroKey.letter(lower),
      ch: ch,
    );
  }

  Widget _charKey(String normal, int retroKey, {required String shifted}) {
    final display = _shift ? shifted : normal;
    return _key(display, retroKey, ch: display.codeUnitAt(0));
  }

  Widget _key(String label, int retroKey, {int ch = 0, int flex = 10}) {
    return Expanded(
      flex: flex,
      child: _TouchKey(
        label: label,
        onDown: () =>
            Emulator.instance.keyDown(retroKey, character: ch, mods: _mods),
        onUp: () => Emulator.instance.keyUp(retroKey, mods: _mods),
      ),
    );
  }

  Widget _consoleKey(String label, String which, {bool accent = false}) {
    return Expanded(
      flex: 12,
      child: _TouchKey(
        label: label,
        accent: accent,
        onDown: () => Emulator.instance.consoleKey(which, true),
        onUp: () => Emulator.instance.consoleKey(which, false),
      ),
    );
  }
}

class _TouchKey extends StatefulWidget {
  const _TouchKey({
    required this.label,
    required this.onDown,
    required this.onUp,
    this.accent = false,
  });

  final String label;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final bool accent;

  @override
  State<_TouchKey> createState() => _TouchKeyState();
}

class _TouchKeyState extends State<_TouchKey> {
  bool _down = false;

  void _set(bool d) {
    if (_down == d) return;
    if (d && Emulator.instance.haptics) HapticFeedback.selectionClick();
    setState(() => _down = d);
    d ? widget.onDown() : widget.onUp();
  }

  @override
  Widget build(BuildContext context) {
    final bg = _down
        ? const Color(0xFFFF8F00)
        : widget.accent
            ? const Color(0xFF4E3B2B)
            : const Color(0xFF2E2A27);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModKey extends StatelessWidget {
  const _ModKey({
    required this.label,
    required this.active,
    required this.onTap,
    required this.flex,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFF8F00) : const Color(0xFF3A3532),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.black : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionKey extends StatelessWidget {
  const _ActionKey({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 12,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF424242),
            borderRadius: BorderRadius.circular(5),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
