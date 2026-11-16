import 'package:flutter/material.dart';

import '../core/core_option.dart';
import '../core/emulator.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _emu = Emulator.instance;

  @override
  Widget build(BuildContext context) {
    final options = _emu.coreOptions().where((o) => o.visible).toList();
    final grouped = <String, List<CoreOption>>{};
    for (final o in options) {
      final cat = o.category.isEmpty ? 'General' : o.category;
      (grouped[cat] ??= []).add(o);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: () {
              _emu.resetCoreOptions();
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Core options reset to defaults')),
              );
            },
            child: const Text('Reset Core'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _emu,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const _SectionHeader('Display & Audio'),
              ListTile(
                title: const Text('Volume'),
                subtitle: Slider(
                  value: _emu.volume,
                  onChanged: (v) => _emu.volume = v,
                ),
                trailing: Text('${(_emu.volume * 100).round()}%'),
              ),
              SwitchListTile(
                title: const Text('Smooth scaling (bilinear)'),
                subtitle: const Text('Off = crisp nearest-neighbor pixels'),
                value: _emu.smoothScaling,
                onChanged: (v) => _emu.smoothScaling = v,
              ),
              const _SectionHeader('Controls'),
              SwitchListTile(
                title: const Text('On-screen touch controls'),
                value: _emu.showTouchControls,
                onChanged: (v) => _emu.showTouchControls = v,
              ),
              ListTile(
                title: const Text('Touch controls opacity'),
                subtitle: Slider(
                  value: _emu.controlsOpacity,
                  min: 0.15,
                  max: 1.0,
                  onChanged: (v) => _emu.controlsOpacity = v,
                ),
                trailing: Text('${(_emu.controlsOpacity * 100).round()}%'),
              ),
              SwitchListTile(
                title: const Text('Haptic feedback'),
                value: _emu.haptics,
                onChanged: (v) => _emu.haptics = v,
              ),
              SwitchListTile(
                title: const Text('Arrow keys + Alt as Joystick'),
                subtitle: const Text(
                    'When off, arrow keys send Atari cursor keys'),
                value: _emu.keyboardJoystick,
                onChanged: (v) => _emu.keyboardJoystick = v,
              ),
              for (final entry in grouped.entries) ...[
                _SectionHeader('Core: ${entry.key}'),
                for (final opt in entry.value) _CoreOptionTile(option: opt),
              ],
              const _SectionHeader('About'),
              ListTile(
                title: const Text('Emulation Core'),
                subtitle: Text(_emu.coreVersion),
              ),
              ListTile(
                title: const Text('Audio Device'),
                subtitle: Text(_emu.audioOk ? 'Active (48 kHz stereo)' : 'Unavailable (muted)'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _CoreOptionTile extends StatelessWidget {
  const _CoreOptionTile({required this.option});
  final CoreOption option;

  @override
  Widget build(BuildContext context) {
    final emu = Emulator.instance;
    final current = emu.coreOption(option.key) ?? option.defaultValue;
    return ListTile(
      title: Text(option.label),
      subtitle: option.needsReset
          ? const Text('Applies on cold reset',
              style: TextStyle(fontSize: 12, color: Colors.amberAccent))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              option.labelFor(current),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => _pickValue(context, current),
    );
  }

  Future<void> _pickValue(BuildContext context, String current) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(option.label,
                    style: Theme.of(ctx).textTheme.titleMedium),
                if (option.info.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(option.info,
                      style: Theme.of(ctx).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          for (final v in option.values)
            RadioListTile<String>(
              title: Text(v.label),
              value: v.value,
              groupValue: current,
              onChanged: (val) => Navigator.pop(ctx, val),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
    if (chosen != null) {
      Emulator.instance.setCoreOption(
        option.key,
        chosen,
        defaultValue: option.defaultValue,
      );
    }
  }
}
