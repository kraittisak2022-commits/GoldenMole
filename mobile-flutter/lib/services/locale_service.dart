import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_locale.dart';

class LocaleService {
  static const _prefKey = 'app_ui_locale_v1';

  Future<AppLocale> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AppLocaleX.fromStorageCode(prefs.getString(_prefKey));
    } catch (_) {
      return AppLocale.th;
    }
  }

  Future<void> save(AppLocale locale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, locale.storageCode);
    } catch (_) {}
  }
}
