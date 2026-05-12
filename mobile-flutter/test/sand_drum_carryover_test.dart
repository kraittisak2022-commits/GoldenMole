import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/utils/sand_drum_carryover.dart';

AppTransaction _trip(String id, String date, double cubic) => AppTransaction(
      id: id,
      date: date,
      type: 'Expense',
      category: 'DailyLog',
      subCategory: 'VehicleTrip',
      description: '',
      amount: 0,
      totalCubic: cubic,
    );

AppTransaction _sand({
  required String id,
  required String date,
  double? drumsObtained,
  double? drumsWashedAtHome,
  double sandMorning = 1,
  double sandAfternoon = 0,
  String? sandMachineType,
}) =>
    AppTransaction(
      id: id,
      date: date,
      type: 'Expense',
      category: 'DailyLog',
      subCategory: 'Sand',
      description: '',
      amount: 0,
      drumsObtained: drumsObtained,
      drumsWashedAtHome: drumsWashedAtHome,
      sandMorning: sandMorning,
      sandAfternoon: sandAfternoon,
      sandMachineType: sandMachineType,
    );

void main() {
  test('epoch is day after auto-completed round', () {
    final txs = <AppTransaction>[
      _trip('t1', '2026-05-01', 10),
      _sand(
        id: 's1',
        date: '2026-05-01',
        drumsObtained: 474,
        drumsWashedAtHome: 0,
      ),
      _trip('t2', '2026-05-02', 10),
      _sand(
        id: 's2',
        date: '2026-05-02',
        drumsObtained: 0,
        drumsWashedAtHome: 200,
      ),
      _trip('t3', '2026-05-03', 10),
      _sand(
        id: 's3',
        date: '2026-05-03',
        drumsObtained: 0,
        drumsWashedAtHome: 274,
      ),
    ];
    expect(
      computeSandDrumCarryoverEpochStart('2026-05-04', txs, roundCloseMinDays: 2),
      '2026-05-04',
    );
  });

  test('manual_close_round matches by round start date suffix', () {
    final txs = <AppTransaction>[
      _trip('t1', '2026-05-01', 10),
      _sand(id: 's1', date: '2026-05-01', drumsObtained: 100, drumsWashedAtHome: 0),
      _trip('t2', '2026-05-02', 10),
      _sand(id: 's2', date: '2026-05-02', drumsObtained: 0, drumsWashedAtHome: 100),
    ];
    final audit = [
      {'action': 'manual_close_round', 'roundId': 'round_9_2026-05-01'},
    ];
    expect(
      computeSandDrumCarryoverEpochStart(
        '2026-05-03',
        txs,
        sandRoundAuditTrail: audit,
        roundCloseMinDays: 999,
      ),
      '2026-05-03',
    );
  });
}
