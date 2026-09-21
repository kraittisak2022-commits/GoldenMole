import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/utils/sand_work_duration.dart';

void main() {
  group('sand work duration lunch', () {
    test('deducts 12:00–13:00 for full-day span', () {
      final summary = computeSandWorkDurationSummary(
        const ['26/06 08:00:00', '26/06 12:30:00', '26/06 17:00:00'],
        '2026-06-26',
      );
      expect(summary, isNotNull);
      expect(summary!.totalActiveHours, 8);
      expect(summary.lunchDeductedHours, 1);
    });

    test('deducts lunch for sand-like mid-day span', () {
      final summary = computeSandWorkDurationSummary(
        const ['21/03 10:45:00', '21/03 15:44:00'],
        '2026-03-21',
      );
      expect(summary, isNotNull);
      expect(summary!.lunchDeductedHours, closeTo(1, 0.001));
      expect(summary.totalActiveHours, closeTo(3 + 59 / 60, 0.001));
    });
  });
}
