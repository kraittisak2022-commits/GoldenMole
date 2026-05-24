import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';

void main() {
  test('fromMap falls back to legacy employee_id column', () {
    final t = AppTransaction.fromMap({
      'id': 'leave_1',
      'date': '2026-05-08',
      'type': 'Leave',
      'category': 'Leave',
      'description': 'ลากิจ: ธุระ',
      'amount': 0,
      'employee_id': 'emp42',
    });
    expect(t.employeeIds, ['emp42']);
  });

  test('toInsertMap clears work_details when workDetails is empty string', () {
    const t = AppTransaction(
      id: 'leave_1',
      date: '2026-05-08',
      type: 'Leave',
      category: 'Leave',
      description: 'ลากิจ: ธุระ',
      amount: 0,
      workDetails: '',
    );
    final map = t.toInsertMap(omitCreatedAt: true);
    expect(map.containsKey('work_details'), isTrue);
    expect(map['work_details'], isNull);
  });

  test('toInsertMap omits work_details when null (new full-day leave)', () {
    const t = AppTransaction(
      id: 'leave_2',
      date: '2026-05-08',
      type: 'Leave',
      category: 'Leave',
      description: 'ลากิจ: ธุระ',
      amount: 0,
    );
    final map = t.toInsertMap(omitCreatedAt: true);
    expect(map.containsKey('work_details'), isFalse);
  });

  test('toInsertMap sends half-day meta in work_details', () {
    const t = AppTransaction(
      id: 'leave_3',
      date: '2026-05-08',
      type: 'Leave',
      category: 'Leave',
      description: 'ลากิจ: ธุระ (ครึ่งวัน — ครึ่งเช้า)',
      amount: 0,
      workDetails: 'leave_half:morning',
      leaveDays: 0.5,
    );
    final map = t.toInsertMap(omitCreatedAt: true);
    expect(map['work_details'], 'leave_half:morning');
  });
}
