import 'dart:io';

import 'package:flutter/services.dart';

/// Bridges Android home-screen pinned shortcuts to the Flutter UI.
class ShortcutService {
  ShortcutService._();
  static final ShortcutService instance = ShortcutService._();

  static const _channel = MethodChannel('dev.altirra.altirra_flutter/shortcuts');

  void listen(void Function(String path) onLaunchGame) {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLaunchGame' && call.arguments is String) {
        onLaunchGame(call.arguments as String);
      }
    });
  }

  Future<String?> getInitialGamePath() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getInitialGamePath');
    } catch (_) {
      return null;
    }
  }

  Future<bool> isPinSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isPinSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> pinGameShortcut({
    required String path,
    required String label,
    String? iconPath,
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('pinGameShortcut', {
            'path': path,
            'label': label,
            if (iconPath != null) 'iconPath': iconPath,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
