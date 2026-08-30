import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists app [ThemeMode] (light / dark). Matches [LocaleService] pattern.
class ThemeModeService {
  static const _prefKey = 'app_ui_theme_mode_v1';

  Future<ThemeMode> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _fromStorage(prefs.getString(_prefKey));
    } catch (_) {
      return ThemeMode.light;
    }
  }

  Future<void> save(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, _toStorage(mode));
    } catch (_) {}
  }

  static String _toStorage(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
      case ThemeMode.light:
        return 'light';
    }
  }

  static ThemeMode _fromStorage(String? raw) {
    switch (raw) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }
}
