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
      _sandTx(
        id: 'h',
        description: 'ทรายที่ล้างที่บ้าน',
        drumsWashedAtHome: 5,
      ),
      _sandTx(id: 'm', morning: 40, afternoon: 0, machineType: 'Old'),
    ];
    final totals = sandWashPeriodTotalsForDay('2026-05-19', txs);
    expect(totals.morning, 40);
    expect(totals.afternoon, 0);
    expect(
      dailySandWashModuleStatusLabel('2026-05-19', txs),
      'เช้า 40 คิว · บ่าย 0 คิว',
    );
  });
}
