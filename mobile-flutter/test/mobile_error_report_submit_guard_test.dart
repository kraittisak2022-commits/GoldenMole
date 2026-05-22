import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/utils/mobile_error_report_submit_guard.dart';

void main() {
  setUp(MobileErrorReportSubmitGuard.resetForTest);

  test('blocks duplicate fingerprint within window', () {
    const fp = 'manual_settings|test error';
    expect(MobileErrorReportSubmitGuard.blockReason(fingerprint: fp), isNull);
    MobileErrorReportSubmitGuard.recordSuccess(fp);
    expect(
      MobileErrorReportSubmitGuard.blockReason(fingerprint: fp),
      contains('ส่งรายงานนี้'),
    );
  });

  test('blocks rapid sends within min interval', () {
    MobileErrorReportSubmitGuard.recordSuccess('a|one');
    final blocked = MobileErrorReportSubmitGuard.blockReason(
      fingerprint: 'b|two',
    );
    expect(blocked, isNotNull);
    expect(blocked, contains('รอ'));
  });
}
