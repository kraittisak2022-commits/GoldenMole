import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../l10n/app_localizations.dart';

class AppLocaleScope extends InheritedWidget {
  const AppLocaleScope({
    super.key,
    required this.locale,
    required this.onLocaleChanged,
    required super.child,
  });

  final AppLocale locale;
  final ValueChanged<AppLocale> onLocaleChanged;

  AppLocalizations get localizations => AppLocalizations(locale);

  static AppLocaleScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppLocaleScope>();
    assert(scope != null, 'AppLocaleScope not found in widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppLocaleScope oldWidget) =>
      oldWidget.locale != locale;
}
