import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/storage/device_prefs.dart';

/// Light, dark or follow the phone. Starts with the phone's setting and
/// switches to the saved choice as soon as it is read.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    unawaited(_load());
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final saved = await ref.read(devicePrefsProvider).read(_key);
    final mode = ThemeMode.values.where((m) => m.name == saved).firstOrNull;
    if (mode != null && ref.mounted) state = mode;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(devicePrefsProvider).write(_key, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

String themeModeLabel(ThemeMode m) => switch (m) {
  ThemeMode.system => 'Same as phone',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};
