import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppearanceSettings {
  final ThemeMode themeMode;
  // Light Theme
  final String lightBg;
  final String lightFg;
  final String lightAccent;
  // Dark Theme
  final String darkBg;
  final String darkFg;
  final String darkAccent;

  AppearanceSettings({
    this.themeMode = ThemeMode.dark,
    this.lightBg = '#EEEEEE',
    this.lightFg = '#101010',
    this.lightAccent = '#007ACC',
    this.darkBg = '#000000',
    this.darkFg = '#CCCCCC',
    this.darkAccent = '#007ACC',
  });

  AppearanceSettings copyWith({
    ThemeMode? themeMode,
    String? lightBg,
    String? lightFg,
    String? lightAccent,
    String? darkBg,
    String? darkFg,
    String? darkAccent,
  }) {
    return AppearanceSettings(
      themeMode: themeMode ?? this.themeMode,
      lightBg: lightBg ?? this.lightBg,
      lightFg: lightFg ?? this.lightFg,
      lightAccent: lightAccent ?? this.lightAccent,
      darkBg: darkBg ?? this.darkBg,
      darkFg: darkFg ?? this.darkFg,
      darkAccent: darkAccent ?? this.darkAccent,
    );
  }
}

class AppearanceNotifier extends Notifier<AppearanceSettings> {
  static const _storage = FlutterSecureStorage();
  
  @override
  AppearanceSettings build() {
    // Initial synchronous state, updated immediately below
    _loadSettings();
    return AppearanceSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final modeStr = await _storage.read(key: 'themeMode') ?? 'ThemeMode.dark';
      ThemeMode mode = ThemeMode.dark;
      if (modeStr == 'ThemeMode.light') mode = ThemeMode.light;
      if (modeStr == 'ThemeMode.system') mode = ThemeMode.system;

      state = AppearanceSettings(
        themeMode: mode,
        lightBg: await _storage.read(key: 'lightBg') ?? '#EEEEEE',
        lightFg: await _storage.read(key: 'lightFg') ?? '#101010',
        lightAccent: await _storage.read(key: 'lightAccent') ?? '#007ACC',
        darkBg: await _storage.read(key: 'darkBg') ?? '#000000',
        darkFg: await _storage.read(key: 'darkFg') ?? '#CCCCCC',
        darkAccent: await _storage.read(key: 'darkAccent') ?? '#007ACC',
      );
    } catch (e) {
      debugPrint('Error loading appearance settings: $e');
    }
  }

  Future<void> updateSettings(AppearanceSettings newSettings) async {
    state = newSettings;
    await _storage.write(key: 'themeMode', value: newSettings.themeMode.toString());
    await _storage.write(key: 'lightBg', value: newSettings.lightBg);
    await _storage.write(key: 'lightFg', value: newSettings.lightFg);
    await _storage.write(key: 'lightAccent', value: newSettings.lightAccent);
    await _storage.write(key: 'darkBg', value: newSettings.darkBg);
    await _storage.write(key: 'darkFg', value: newSettings.darkFg);
    await _storage.write(key: 'darkAccent', value: newSettings.darkAccent);
  }
}

final appearanceProvider = NotifierProvider<AppearanceNotifier, AppearanceSettings>(() {
  return AppearanceNotifier();
});
