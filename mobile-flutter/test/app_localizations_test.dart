import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/l10n/app_locale.dart';
import 'package:mobile_flutter/l10n/app_localizations.dart';
import 'package:mobile_flutter/l10n/daily_status_translator.dart';

void main() {
  test('module titles in Chinese', () {
    final l10n = AppLocalizations(AppLocale.zh);
    expect(l10n.moduleTitle('ลางาน'), '请假');
    expect(l10n.dailyLogTitle, '每日记录');
  });

  test('translateDailyCardStatus maps Thai fuel label', () {
    const th = 'ใช้งาน 2 คัน · แจ้ง 1/2 คัน · ยังไม่ครบ · 120 ลิตร';
    final zh = translateDailyCardStatus(th, AppLocale.zh);
    expect(zh.contains('辆'), isTrue);
    expect(zh.contains('未完成'), isTrue);
  });

  test('LocaleService storage codes', () {
    expect(AppLocaleX.fromStorageCode('zh'), AppLocale.zh);
    expect(AppLocaleX.fromStorageCode('th'), AppLocale.th);
  });
}
