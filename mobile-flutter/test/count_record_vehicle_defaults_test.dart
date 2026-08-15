import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/models/employee.dart';
import 'package:mobile_flutter/utils/count_record_vehicle_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

Employee _driver(String id, String nickname) => Employee(
      id: id,
      name: nickname,
      nickname: nickname,
      type: 'Daily',
      positions: const ['คนขับรถ'],
    );

AppTransaction _trip({
  required String id,
  required String vehicleId,
  String? driverId,
}) =>
    AppTransaction(
      id: id,
      date: '2026-06-01',
      type: 'Expense',
      category: 'DailyLog',
      subCategory: 'VehicleTrip',
      description: '$vehicleId: 1 เที่ยว',
      amount: 0,
      vehicleId: vehicleId,
      driverId: driverId,
      tripCount: 1,
      perCarTrips: 1,
    );

void main() {
  test('settings vehicleDefaultDrivers takes priority over trip history', () {
    final drivers = [
      _driver('d9', 'พี่นุ'),
      _driver('d2', 'เดี่ยว'),
    ];
    final history = [
      _trip(id: '1', vehicleId: 'รถดรัมโอเว่น', driverId: 'd9'),
      _trip(id: '2', vehicleId: 'รถดรัมโอเว่น', driverId: 'd9'),
    ];
    expect(
      resolveCountRecordDefaultDriverId(
        vehicleId: 'รถดรัมโอเว่น',
        drivers: drivers,
        tripHistory: history,
        vehicleDefaultDrivers: const {'รถดรัมโอเว่น': 'd2'},
      ),
      'd2',
    );
  });

  test('falls back to trip history when web has no entry', () {
    final drivers = [
      _driver('d1', 'พี่นุ'),
      _driver('d2', 'เดี่ยว'),
    ];
    final history = [
      _trip(id: '1', vehicleId: 'รถดรัมโอเว่น', driverId: 'd1'),
      _trip(id: '2', vehicleId: 'รถดรัมโอเว่น', driverId: 'd1'),
      _trip(id: '3', vehicleId: 'รถดรัมโอเว่น', driverId: 'd2'),
    ];
    expect(
      resolveCountRecordDefaultDriverId(
        vehicleId: 'รถดรัมโอเว่น',
        drivers: drivers,
        tripHistory: history,
        vehicleDefaultDrivers: const {},
      ),
      'd1',
    );
  });

  test('returns null when no web entry and no trip history', () {
    final drivers = [
      _driver('d1', 'พี่นุ'),
      _driver('d2', 'เดี่ยว'),
    ];
    expect(
      resolveCountRecordDefaultDriverId(
        vehicleId: 'รถดรัมโอเว่น',
        drivers: drivers,
        tripHistory: const [],
        vehicleDefaultDrivers: const {},
      ),
      isNull,
    );
  });

  test('sorts vehicles by trip history frequency then web list order', () {
    final history = [
      _trip(id: '1', vehicleId: 'รถดรัมพี่โก', driverId: 'x'),
      _trip(id: '2', vehicleId: 'รถดรัมพี่โก', driverId: 'x'),
      _trip(id: '3', vehicleId: 'รถดรัมโอเว่น', driverId: 'y'),
    ];
    final sorted = sortCountRecordVehicles(
      cars: const [
        'รถดรัมลุงศักดิ์',
        'รถดรัมโอเว่น',
        'รถดรัมพี่โก',
      ],
      tripHistory: history,
    );
    expect(sorted.first, 'รถดรัมพี่โก');
    expect(sorted[1], 'รถดรัมโอเว่น');
    expect(sorted.last, 'รถดรัมลุงศักดิ์');
  });

  test('tie-break uses web cars order when trip counts equal', () {
    final sorted = sortCountRecordVehicles(
      cars: const [
        'รถดรัมลุงศักดิ์',
        'รถดรัมโอเว่น',
        'รถดรัมพี่โก',
      ],
      tripHistory: const [],
    );
    expect(sorted, const [
      'รถดรัมลุงศักดิ์',
      'รถดรัมโอเว่น',
      'รถดรัมพี่โก',
    ]);
  });

  test('orders default driver first in driver list from web settings', () {
    final drivers = [
      _driver('d1', 'พี่นุ'),
      _driver('d2', 'เดี่ยว'),
    ];
    final ordered = orderDriversForVehicle(
      vehicleId: 'รถดรัมลุงศักดิ์',
      drivers: drivers,
      tripHistory: const [],
      vehicleDefaultDrivers: const {'รถดรัมลุงศักดิ์': 'd2'},
    );
    expect(ordered.first.id, 'd2');
  });

  test('new vehicle in count panel starts at 0 trips with empty laps', () {
    expect(kCountRecordNewVehicleInitialRounds, 0);
    final seed = countRecordNewVehicleSeed();
    expect(seed.rounds, 0);
    expect(seed.lapTimes, isEmpty);
  });

  test('availableCountRecordVehicles hides already-added cards', () {
    final available = availableCountRecordVehicles(
      cars: const ['รถดรัมเอ', 'รถดรัมบี', 'รถดรัมซี'],
      alreadyAdded: const ['รถดรัมบี'],
    );
    expect(available, isNot(contains('รถดรัมบี')));
    expect(available, containsAll(['รถดรัมเอ', 'รถดรัมซี']));
  });

  test('availableCountRecordVehicles hides picks from other dialog rows', () {
    final available = availableCountRecordVehicles(
      cars: const ['รถดรัมเอ', 'รถดรัมบี', 'รถดรัมซี'],
      selectedInOtherRows: const ['รถดรัมเอ'],
      currentSelection: 'รถดรัมบี',
    );
    expect(available, isNot(contains('รถดรัมเอ')));
    expect(available, contains('รถดรัมบี'));
    expect(available, contains('รถดรัมซี'));
  });

  test('availableCountRecordVehicles keeps current selection in own row', () {
    final available = availableCountRecordVehicles(
      cars: const ['รถดรัมเอ', 'รถดรัมบี'],
      selectedInOtherRows: const ['รถดรัมเอ'],
      currentSelection: 'รถดรัมเอ',
    );
    expect(available, contains('รถดรัมเอ'));
  });

  test('availableCountRecordVehicles returns empty when all taken', () {
    final available = availableCountRecordVehicles(
      cars: const ['รถดรัมเอ', 'รถดรัมบี'],
      alreadyAdded: const ['รถดรัมเอ'],
      selectedInOtherRows: const ['รถดรัมบี'],
    );
    expect(available, isEmpty);
  });
}
