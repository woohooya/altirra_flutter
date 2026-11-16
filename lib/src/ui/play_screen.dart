import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/emulator.dart';
import '../core/retro_keys.dart';
import '../emulator/atari_screen.dart';
import '../input/keyboard_mapper.dart';
import '../input/touch_controls.dart';
import 'settings_screen.dart';

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key});

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> with WidgetsBindingObserver {
  final _emu = Emulator.instance;
  final _focusNode = FocusNode();
  bool _showHud = true;
  bool _showKeyboard = false;
  double _fps = 0.0;
  int _kbJoyBits = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _focusNode.dispose();
    _emu.releaseAllInput();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (!_emu.paused) _emu.setPaused(true);
    }
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    final isDown = event is KeyDownEvent;
    final isUp = event is KeyUpEvent;
    if (!isDown && !isUp) return KeyEventResult.handled;

    // Optional arrow-keys + Alt as Joystick 1
    if (_emu.keyboardJoystick) {
      final joyBit = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowUp => RetroPad.up,
        LogicalKeyboardKey.arrowDown => RetroPad.down,
        LogicalKeyboardKey.arrowLeft => RetroPad.left,
        LogicalKeyboardKey.arrowRight => RetroPad.right,
        LogicalKeyboardKey.altLeft ||
        LogicalKeyboardKey.altRight =>
          RetroPad.b,
        _ => 0,
      };
      if (joyBit != 0) {
        _kbJoyBits = isDown ? (_kbJoyBits | joyBit) : (_kbJoyBits & ~joyBit);
        _emu.setPad(InputSource.keyboard, _kbJoyBits);
        return KeyEventResult.handled;
      }
    }

    final rk = logicalKeyToRetroKey(event.logicalKey);
    if (rk != null) {
      final mods = currentRetroModifiers();
      if (isDown) {
        final ch = event.character != null && event.character!.isNotEmpty
            ? event.character!.runes.first
            : 0;
        _emu.keyDown(rk, character: ch, mods: mods);
      } else {
        _emu.keyUp(rk, mods: mods);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final title = _emu.contentPath != null
        ? p.basename(_emu.contentPath!)
        : 'Atari 800XL';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        _exitToLibrary();
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: ListenableBuilder(
            listenable: _emu,
            builder: (context, _) {
              return Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        // Video output (tap to toggle HUD)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _focusNode.requestFocus();
                            setState(() => _showHud = !_showHud);
                          },
                          child: AtariScreen(
                            onFpsTick: (f) {
                              if (mounted) setState(() => _fps = f);
                            },
                          ),
                        ),

                        // Touch controls overlay
                        if (_emu.showTouchControls && !_showKeyboard)
                          const TouchControls(),

                        // Pause badge
                        if (_emu.paused)
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Text(
                                'PAUSED',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                          ),

                        // Top HUD bar
                        if (_showHud)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: _TopHud(
                              title: title,
                              fps: _fps,
                              paused: _emu.paused,
                              speed: _emu.speed,
                              showKeyboard: _showKeyboard,
                              showTouch: _emu.showTouchControls,
                              onBack: _exitToLibrary,
                              onTogglePause: () => _emu.setPaused(!_emu.paused),
                              onCycleSpeed: () {
                                final next = switch (_emu.speed) {
                                  1 => 2,
                                  2 => 4,
                                  _ => 1,
                                };
                                _emu.setSpeed(next);
                              },
                              onToggleKeyboard: () => setState(
                                  () => _showKeyboard = !_showKeyboard),
                              onToggleTouch: () => _emu.showTouchControls =
                                  !_emu.showTouchControls,
                              onStates: _showStatesSheet,
                              onDisks: _showDisksSheet,
                              onReset: (cold) =>
                                  cold ? _emu.coldReset() : _emu.warmReset(),
                              onSettings: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SettingsScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Collapsible Atari virtual keyboard
                  if (_showKeyboard)
                    AtariKeyboardOverlay(
                      onClose: () => setState(() => _showKeyboard = false),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _exitToLibrary() {
    _emu.unload();
    Navigator.of(context).pop();
  }

  Future<void> _showStatesSheet() async {
    final wasPaused = _emu.paused;
    if (!wasPaused) _emu.setPaused(true);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Save States',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              for (var slot = 1; slot <= 4; slot++)
                ListTile(
                  leading: CircleAvatar(child: Text('$slot')),
                  title: Text('Slot $slot'),
                  subtitle: Text(
                      _emu.hasState(slot) ? 'Saved' : 'Empty'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          final ok = _emu.saveState(slot);
                          setSheetState(() {});
                          _toast(ok ? 'Saved slot $slot' : 'Save failed');
                        },
                        child: const Text('Save'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _emu.hasState(slot)
                            ? () {
                                final ok = _emu.loadState(slot);
                                Navigator.pop(ctx);
                                _toast(
                                    ok ? 'Loaded slot $slot' : 'Load failed');
                              }
                            : null,
                        child: const Text('Load'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!wasPaused && mounted) _emu.setPaused(false);
  }

  Future<void> _showDisksSheet() async {
    final count = _emu.diskCount;
    final current = _emu.diskIndex;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Disk Control (D1:)',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    final files = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: const [
                        'atr',
                        'xfd',
                        'atx',
                        'atz',
                        'dcm',
                        'pro',
                      ],
                    );
                    if (files.isEmpty || files.single.path == null) return;
                    final path = await _emu.importFile(files.single.path!);
                    final ok = _emu.insertDisk(path);
                    if (ctx.mounted) Navigator.pop(ctx);
                    _toast(ok ? 'Inserted ${p.basename(path)}' : 'Insert failed');
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Insert Disk...'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (count <= 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No disk images mounted.'),
              )
            else
              for (var i = 0; i < count; i++)
                RadioListTile<int>(
                  title: Text('Disk ${i + 1}'),
                  value: i,
                  groupValue: current,
                  onChanged: (idx) {
                    if (idx != null) {
                      _emu.selectDisk(idx);
                      Navigator.pop(ctx);
                    }
                  },
                ),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ));
  }
}

class _TopHud extends StatelessWidget {
  const _TopHud({
    required this.title,
    required this.fps,
    required this.paused,
    required this.speed,
    required this.showKeyboard,
    required this.showTouch,
    required this.onBack,
    required this.onTogglePause,
    required this.onCycleSpeed,
    required this.onToggleKeyboard,
    required this.onToggleTouch,
    required this.onStates,
    required this.onDisks,
    required this.onReset,
    required this.onSettings,
  });

  final String title;
  final double fps;
  final bool paused;
  final int speed;
  final bool showKeyboard;
  final bool showTouch;
  final VoidCallback onBack;
  final VoidCallback onTogglePause;
  final VoidCallback onCycleSpeed;
  final VoidCallback onToggleKeyboard;
  final VoidCallback onToggleTouch;
  final VoidCallback onStates;
  final VoidCallback onDisks;
  final ValueChanged<bool> onReset;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Exit to Library',
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: onBack,
              ),
              Text(
                title,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              if (fps > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${fps.toStringAsFixed(1)} fps',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: paused ? 'Resume' : 'Pause',
                icon: Icon(paused ? Icons.play_arrow : Icons.pause,
                    color: Colors.white),
                onPressed: onTogglePause,
              ),
              TextButton(
                onPressed: onCycleSpeed,
                child: Text(
                  '${speed}x',
                  style: TextStyle(
                    color: speed > 1 ? Colors.amberAccent : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Atari Keyboard',
                icon: Icon(
                  Icons.keyboard,
                  color: showKeyboard ? Colors.amberAccent : Colors.white,
                ),
                onPressed: onToggleKeyboard,
              ),
              IconButton(
                tooltip: 'Touch Controls',
                icon: Icon(
                  Icons.gamepad,
                  color: showTouch ? Colors.amberAccent : Colors.white,
                ),
                onPressed: onToggleTouch,
              ),
              IconButton(
                tooltip: 'Save / Load State',
                icon: const Icon(Icons.save_outlined, color: Colors.white),
                onPressed: onStates,
              ),
              IconButton(
                tooltip: 'Disks',
                icon: const Icon(Icons.album_outlined, color: Colors.white),
                onPressed: onDisks,
              ),
              PopupMenuButton<bool>(
                tooltip: 'Reset',
                icon: const Icon(Icons.restart_alt, color: Colors.white),
                onSelected: onReset,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: false, child: Text('Warm Reset')),
                  PopupMenuItem(value: true, child: Text('Cold Reset')),
                ],
              ),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
