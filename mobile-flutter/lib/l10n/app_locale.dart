import 'package:flutter/material.dart';

/// ภาษาในแอปมือถือ — ไทย (ค่าเริ่มต้น) และ จีนตัวย่อ
enum AppLocale {
  th,
  zh,
}

extension AppLocaleX on AppLocale {
  String get storageCode => this == AppLocale.zh ? 'zh' : 'th';

  Locale get materialLocale =>
      this == AppLocale.zh ? const Locale('zh', 'CN') : const Locale('th', 'TH');

  String get shortLabel => this == AppLocale.zh ? '中文' : 'ไทย';

  static AppLocale fromStorageCode(String? raw) {
    final code = (raw ?? '').trim().toLowerCase();
    if (code == 'zh' || code == 'zh_cn' || code == 'zh-cn') return AppLocale.zh;
    return AppLocale.th;
  }
}
