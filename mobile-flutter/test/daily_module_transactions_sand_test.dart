import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/utils/daily_module_transactions.dart';

AppTransaction _sandTx({
  required String id,
  double? morning,
  double? afternoon,
  String? machineType,
  String description = 'ล้างทราย เครื่องร่อน (เก่า)',
  double? drumsObtained,
}) =>
    AppTransaction(
      id: id,
      date: '2026-05-19',
      type: 'Expense',
      category: 'DailyLog',
      subCategory: 'Sand',
      description: description,
      amount: 0,
      sandMorning: morning,
      sandAfternoon: afternoon,
      sandMachineType: machineType,
      drumsObtained: drumsObtained,
    );

void main() {
  test('sums morning and afternoon across machines', () {
    final txs = [
      _sandTx(id: '1', morning: 30, afternoon: 10, machineType: 'Old'),
      _sandTx(
        id: '2',
        morning: 50,
        afternoon: 20,
        machineType: 'New',
        description: 'ล้างทราย เครื่องร่อน (ใหม่)',
      ),
    ];
    final totals = sandWashPeriodTotalsForDay('2026-05-19', txs);
    expect(totals.morning, 80);
    expect(totals.afternoon, 30);
    expect(
      dailySandWashModuleStatusLabel('2026-05-19', txs),
      'เช้า 80 คิว · บ่าย 30 คิว',
    );
  });

  test('ignores drums-only and home sand rows', () {
    final txs = [
      _sandTx(
        id: 'd',
        description: 'จำนวนถังที่ได้วันนี้',
        drumsObtained: 12,
      ),
      AppTransaction(
        id: 'h',
        date: '2026-05-19',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: 'ทรายที่ล้างที่บ้าน',
        amount: 0,
      ),
      _sandTx(id: 'm', morning: 40, afternoon: 0, machineType: 'Old'),
    ];
    final totals = sandWashPeriodTotalsForDay('2026-05-19', txs);
    expect(totals.morning, 40);
    expect(totals.afternoon, 0);
    expect(sandWashDrumsObtainedForDay('2026-05-19', txs), 12);
    expect(
      dailySandWashModuleStatusLabel('2026-05-19', txs),
      'เช้า 40 คิว · บ่าย 0 คิว · ถัง 12',
    );
  });

  test('shows drums without cubic when only drums row saved', () {
    final txs = [
      _sandTx(
        id: 'd',
        description: 'จำนวนถังที่ได้วันนี้',
        drumsObtained: 8,
      ),
    ];
    expect(
      dailySandWashModuleStatusLabel('2026-05-19', txs),
      'ถัง 8',
    );
  });

  test('sand wash card falls back to count-record rounds when no machine rows',
      () {
    final txs = [
      AppTransaction(
        id: 'cr',
        date: '2026-05-19',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: 'ร่อนทราย: 3 รอบ',
        amount: 0,
        drumsObtained: 3,
        workAssignments: {
          'lapTimes': ['x 08:30', 'x 09:15', 'x 13:20'],
        },
      ),
    ];
    // ยังไม่มีแถวฟอร์มเครื่องร่อน → การ์ดต้องโชว์จำนวนรอบที่นับไว้ (เช้า 2 / บ่าย 1)
    expect(
      dailySandWashModuleStatusLabel('2026-05-19', txs),
      'เช้า 2 คิว · บ่าย 1 คิว',
    );
  });

  test('sand wash card shows total rounds when count rows have no lapTimes',
      () {
    final txs = [
      AppTransaction(
        id: 'cr',
        date: '2026-05-19',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: 'ร่อนทราย: 5 รอบ',
        amount: 0,
        drumsObtained: 5,
      ),
    ];
    // ไม่มี lapTimes แยกช่วงไม่ได้ → ต้องโชว์ยอดรวมรอบ ไม่ใช่ "ยังไม่มีบันทึก"
    expect(
      dailySandWashModuleStatusLabel('2026-05-19', txs),
      'ร่อน 5 รอบ',
    );
  });

  test('machine rows take precedence over count-record rounds', () {
    final txs = [
      AppTransaction(
        id: 'cr',
        date: '2026-05-19',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: 'ร่อนทราย: 3 รอบ',
        amount: 0,
        drumsObtained: 3,
        workAssignments: {
          'lapTimes': ['x 08:30', 'x 09:15', 'x 13:20'],
        },
      ),
      _sandTx(id: 'm', morning: 30, afternoon: 20, machineType: 'Old'),
    ];
    // มีแถวฟอร์มแล้ว → ใช้ค่าฟอร์ม ไม่นับรอบซ้ำ
    expect(
      dailySandWashModuleStatusLabel('2026-05-19', txs),
      'เช้า 30 คิว · บ่าย 20 คิว',
    );
  });

  test('count record rounds do not count as drums on sand wash card', () {
    final txs = [
      AppTransaction(
        id: 'cr',
        date: '2026-05-19',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: 'ร่อนทราย: 6 รอบ',
        amount: 0,
        drumsObtained: 6,
      ),
      _sandTx(
        id: 'd',
        description: 'จำนวนถังที่ได้วันนี้',
        drumsObtained: 10,
      ),
      _sandTx(id: 'm', morning: 30, afternoon: 20, machineType: 'Old'),
    ];
    expect(sandWashDrumsObtainedForDay('2026-05-19', txs), 10);
    expect(
      dailySandWashModuleStatusLabel('2026-05-19', txs),
      'เช้า 30 คิว · บ่าย 20 คิว · ถัง 10',
    );
  });
}
