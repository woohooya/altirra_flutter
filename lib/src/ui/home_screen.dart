import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/emulator.dart';
import 'play_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _emu = Emulator.instance;
  bool _busy = false;

  Future<void> _launch(String? path) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await _emu.load(path);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              path == null
                  ? 'Failed to boot Atari core'
                  : 'Failed to load ${p.basename(path)}',
            ),
          ),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PlayScreen()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndLaunch() async {
    // Use FileType.any because Android's Storage Access Framework often hides
    // .atr/.xex/.car files when custom extensions are passed.
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty || files.single.path == null) return;
    final picked = files.single;
    final stored = await _emu.importFile(picked.path!, name: picked.name);
    await _launch(stored);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Altirra'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _emu,
        builder: (context, _) {
          final recent = _emu.recent;
          final basicEnabled = _emu.coreOption('altirra_basic') == 'enabled';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Hero launch card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.computer,
                                color: cs.onPrimaryContainer),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Atari 8-bit & 5200',
                                    style:
                                        Theme.of(context).textTheme.titleMedium),
                                Text(
                                  _emu.coreVersion,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _pickAndLaunch,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('Open File'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : () => _launch(null),
                              icon: const Icon(Icons.power_settings_new),
                              label: const Text('Boot Atari'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Internal BASIC (for Boot Atari)'),
                        value: basicEnabled,
                        onChanged: (v) => _emu.setCoreOption(
                          'altirra_basic',
                          v ? 'enabled' : 'disabled',
                          defaultValue: 'disabled',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'RECENT',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: cs.primary,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              if (recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'No recent images.\nSupports ATR, XFD, ATX, XEX, CAR, ROM, A52, CAS, SAP, ZIP, M3U.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              else
                for (final path in recent)
                  _RecentTile(
                    path: path,
                    exists: File(path).existsSync(),
                    onTap: () => _launch(path),
                    onRemove: () => _emu.removeRecent(path),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.path,
    required this.exists,
    required this.onTap,
    required this.onRemove,
  });

  final String path;
  final bool exists;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ext = p.extension(path).replaceFirst('.', '').toUpperCase();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        enabled: exists,
        leading: Container(
          width: 44,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            ext.isEmpty ? 'BIN' : ext,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(p.basename(path),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          exists ? path : 'File missing',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 11, color: exists ? Colors.white54 : Colors.redAccent),
        ),
        trailing: IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.close, size: 18),
          onPressed: onRemove,
        ),
        onTap: exists ? onTap : null,
      ),
    );
  }
}
