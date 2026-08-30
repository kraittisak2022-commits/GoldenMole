import 'package:flutter/material.dart';

/// Exposes persisted [ThemeMode] + setter below [MaterialApp].
class AppThemeScope extends InheritedWidget {
  const AppThemeScope({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required super.child,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  bool get isDark => themeMode == ThemeMode.dark;

  void toggleDarkMode() {
    onThemeModeChanged(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  static AppThemeScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null, 'AppThemeScope not found in widget tree');
    return scope!;
  }

  static AppThemeScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
  }

  @override
  bool updateShouldNotify(AppThemeScope oldWidget) =>
      oldWidget.themeMode != themeMode;
}
