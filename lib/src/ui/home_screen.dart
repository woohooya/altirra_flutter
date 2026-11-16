import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/emulator.dart';
import '../core/shortcut_service.dart';
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
  bool _canPinShortcuts = false;

  @override
  void initState() {
    super.initState();
    _initShortcuts();
  }

  Future<void> _initShortcuts() async {
    ShortcutService.instance.listen(_launchFromShortcut);
    final supported = await ShortcutService.instance.isPinSupported();
    if (mounted && supported) {
      setState(() => _canPinShortcuts = true);
    }
    final initialPath = await ShortcutService.instance.getInitialGamePath();
    if (initialPath != null && initialPath.isNotEmpty && mounted) {
      _launchFromShortcut(initialPath);
    }
  }

  Future<void> _launchFromShortcut(String path) async {
    if (!mounted) return;
    if (!File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File not found: ${p.basename(path)}')),
      );
      return;
    }
    // If already in PlayScreen, return to root before launching the new game.
    Navigator.of(context).popUntil((route) => route.isFirst);
    await _launch(path);
  }

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

  Future<void> _pinShortcut(String path) async {
    final defaultLabel = p.basenameWithoutExtension(path);
    final labelController = TextEditingController(text: defaultLabel);
    String? customIconPath;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pin to Home Screen',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 14),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 64,
                        height: 64,
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        child: customIconPath != null
                            ? Image.file(
                                File(customIconPath!),
                                fit: BoxFit.cover,
                              )
                            : const Icon(Icons.videogame_asset, size: 32),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final files = await FilePicker.pickFiles(
                                type: FileType.image,
                              );
                              if (files.isNotEmpty &&
                                  files.single.path != null) {
                                setSheetState(
                                    () => customIconPath = files.single.path);
                              }
                            },
                            icon: const Icon(Icons.image_outlined, size: 18),
                            label: const Text('Choose Image'),
                          ),
                          if (customIconPath != null)
                            TextButton(
                              onPressed: () =>
                                  setSheetState(() => customIconPath = null),
                              child: const Text('Use Default'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: labelController,
                  maxLength: 25,
                  decoration: const InputDecoration(
                    labelText: 'Shortcut Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.add_to_home_screen),
                    label: const Text('Add to Home Screen'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    final label = labelController.text.trim();
    labelController.dispose();
    if (confirmed != true || label.isEmpty) return;

    final ok = await ShortcutService.instance.pinGameShortcut(
      path: path,
      label: label,
      iconPath: customIconPath,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Requested home screen shortcut for "$label"'
              : 'Home screen shortcuts are not supported on this launcher',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('THE Atari 800'),
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
                    onPin: _canPinShortcuts ? () => _pinShortcut(path) : null,
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
    this.onPin,
  });

  final String path;
  final bool exists;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onPin;

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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onPin != null && exists)
              IconButton(
                tooltip: 'Pin to Home Screen',
                icon: const Icon(Icons.add_to_home_screen, size: 20),
                onPressed: onPin,
              ),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close, size: 18),
              onPressed: onRemove,
            ),
          ],
        ),
        onTap: exists ? onTap : null,
      ),
    );
  }
}
