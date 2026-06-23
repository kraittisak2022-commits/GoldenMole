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
  test('maps known vehicles to default driver nicknames', () {
    expect(
      defaultDriverNicknameForVehicle('รถดรัมโอเว่น'),
      'พี่นุ',
    );
    expect(
      defaultDriverNicknameForVehicle('รถดรัมลุงศักดิ์'),
      'เดี่ยว',
    );
    expect(
      defaultDriverNicknameForVehicle('รถสิบล้อนายกพนม'),
      'พี่สัน',
    );
    expect(
      defaultDriverNicknameForVehicle('รถดรัมนายกพนม'),
      'ใหญ่',
    );
  });

  test('resolves default driver id from nickname', () {
    final drivers = [
      _driver('d1', 'พี่นุ'),
      _driver('d2', 'เดี่ยว'),
    ];
    expect(
      resolveCountRecordDefaultDriverId(
        vehicleId: 'รถดรัมโอเว่น',
        drivers: drivers,
        tripHistory: const [],
      ),
      'd1',
    );
  });

  test('sorts vehicles by trip history frequency then default priority', () {
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
  });

  test('orders default driver first in driver list', () {
    final drivers = [
      _driver('d1', 'พี่นุ'),
      _driver('d2', 'เดี่ยว'),
    ];
    final ordered = orderDriversForVehicle(
      vehicleId: 'รถดรัมลุงศักดิ์',
      drivers: drivers,
      tripHistory: const [],
    );
    expect(ordered.first.id, 'd2');
  });
}
