import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/utils/daily_module_transactions.dart';

AppTransaction _trip({
  double? tripMorning,
  double? tripAfternoon,
  double? perCarTrips,
  double? tripCount,
  List<String>? lapTimes,
}) {
  return AppTransaction(
    id: 't1',
    date: '2026-06-26',
    type: 'Expense',
    category: 'DailyLog',
    subCategory: 'VehicleTrip',
    description: 'รถดรัม',
    amount: 0,
    vehicleId: 'รถดรัมโอเว่น',
    tripMorning: tripMorning,
    tripAfternoon: tripAfternoon,
    perCarTrips: perCarTrips,
    tripCount: tripCount,
    workAssignments: lapTimes == null ? null : {'lapTimes': lapTimes},
  );
}

void main() {
  test('uses explicit morning/afternoon when present', () {
    final s = vehicleTripPeriodSplit(_trip(tripMorning: 2, tripAfternoon: 3));
    expect(s.morning, 2);
    expect(s.afternoon, 3);
  });

  test('splits counter lapTimes by time of day (before/after 12:00)', () {
    final s = vehicleTripPeriodSplit(
      _trip(
        perCarTrips: 4,
        tripCount: 4,
        lapTimes: [
          '26/06 08:10:00',
          '26/06 11:55:00',
          '26/06 13:05:00',
          '26/06 15:40:00',
        ],
      ),
    );
    expect(s.morning, 2);
    expect(s.afternoon, 2);
  });

  test('counts unparseable laps as morning', () {
    final s = vehicleTripPeriodSplit(
      _trip(perCarTrips: 2, lapTimes: ['bad', '26/06 14:00:00']),
    );
    expect(s.morning, 1);
    expect(s.afternoon, 1);
  });

  test('falls back to total trips as morning when no laps', () {
    final s = vehicleTripPeriodSplit(_trip(perCarTrips: 5, tripCount: 5));
    expect(s.morning, 5);
    expect(s.afternoon, 0);
  });

  test('isCountRecordVehicleTrip detects note and lapTimes', () {
    expect(
      isCountRecordVehicleTrip(
        AppTransaction(
          id: 'c1',
          date: '2026-06-26',
          type: 'Expense',
          category: 'DailyLog',
          subCategory: 'VehicleTrip',
          description: 'รถดรัม: 3 เที่ยว',
          amount: 0,
          note: 'นับเที่ยวโดย Admin',
        ),
      ),
      isTrue,
    );
    expect(
      isCountRecordVehicleTrip(
        _trip(perCarTrips: 2, lapTimes: ['26/06 08:10:00']),
      ),
      isTrue,
    );
    expect(
      isCountRecordVehicleTrip(
        AppTransaction(
          id: 'd1',
          date: '2026-06-26',
          type: 'Expense',
          category: 'DailyLog',
          subCategory: 'VehicleTrip',
          description: 'รถดรัม: เหมา 30 คิว',
          amount: 0,
          tripBillingMode: 'LumpSum',
        ),
      ),
      isFalse,
    );
  });
}
