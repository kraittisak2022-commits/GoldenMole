import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/services/battery_line_alert_service.dart';

BatteryAlertDecision _d(int level, {bool charging = false, int? last}) =>
    decideBatteryAlert(level: level, charging: charging, lastStep: last);

void main() {
  group('decideBatteryAlert', () {
    test('no alert at 15% or above', () {
      expect(_d(15).kind, BatteryAlertKind.none);
      expect(_d(60).kind, BatteryAlertKind.none);
    });

    test('alerts step 15 when dropping below 15%', () {
      final d = _d(14);
      expect(d.kind, BatteryAlertKind.low);
      expect(d.step, 15);
    });

    test('does not repeat the same step', () {
      expect(_d(13, last: 15).kind, BatteryAlertKind.none);
      expect(_d(11, last: 15).kind, BatteryAlertKind.none);
    });

    test('alerts again at 10% and 5%', () {
      final at10 = _d(10, last: 15);
      expect(at10.kind, BatteryAlertKind.low);
      expect(at10.step, 10);
      expect(_d(7, last: 10).kind, BatteryAlertKind.none);
      final at5 = _d(5, last: 10);
      expect(at5.kind, BatteryAlertKind.low);
      expect(at5.step, 5);
      expect(_d(2, last: 5).kind, BatteryAlertKind.none);
    });

    test('skipping steps sends one alert at the lowest step', () {
      final d = _d(8);
      expect(d.kind, BatteryAlertKind.low);
      expect(d.step, 10);
      final low = _d(3, last: 15);
      expect(low.kind, BatteryAlertKind.low);
      expect(low.step, 5);
    });

    test('charging after an alert reports charging started', () {
      expect(
        _d(12, charging: true, last: 15).kind,
        BatteryAlertKind.chargingStarted,
      );
    });

    test('charging without a prior alert does nothing', () {
      expect(_d(12, charging: true).kind, BatteryAlertKind.none);
    });

    test('recovering to 20% resets the cycle', () {
      expect(_d(20, last: 10).kind, BatteryAlertKind.reset);
      expect(_d(19, last: 15).kind, BatteryAlertKind.none);
    });
  });

  test('low battery message includes device, user and level', () {
    final text = buildBatteryLowLineText(
      level: 14,
      device: 'Xiaomi 23043RP34G',
      user: 'สมชาย',
      now: DateTime(2026, 10, 10, 14, 5),
    );
    expect(text, contains('แบตแท็บเล็ตใกล้หมด'));
    expect(text, contains('เครื่อง: Xiaomi 23043RP34G'));
    expect(text, contains('ผู้ใช้: สมชาย'));
    expect(text, contains('แบตเหลือ: 14%'));
    expect(text, contains('10 ต.ค. 2569 14:05'));
  });
}
