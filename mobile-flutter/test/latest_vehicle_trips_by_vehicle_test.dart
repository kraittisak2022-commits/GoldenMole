import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/utils/daily_module_transactions.dart';

AppTransaction _drumTrip({
  required String id,
  required String vehicleId,
  String date = '2026-08-12',
  DateTime? createdAt,
  String? driverId,
  double? perCarTrips,
}) {
  return AppTransaction(
    id: id,
    date: date,
    type: 'Expense',
    category: 'DailyLog',
    subCategory: 'VehicleTrip',
    description: 'รถดรัม',
    amount: 0,
    vehicleId: vehicleId,
    driverId: driverId,
    perCarTrips: perCarTrips ?? 10,
    tripCount: perCarTrips ?? 10,
    createdAt: createdAt,
  );
}

AppTransaction _legacyVehicle({
  required String id,
  required String vehicleId,
  String date = '2026-08-12',
  DateTime? createdAt,
}) {
  return AppTransaction(
    id: id,
    date: date,
    type: 'Expense',
    category: 'Vehicle',
    description: 'รถดรัม',
    amount: 0,
    vehicleId: vehicleId,
    createdAt: createdAt,
  );
}

AppTransaction _macroVehicle({
  required String id,
  String date = '2026-08-12',
}) {
  return AppTransaction(
    id: id,
    date: date,
    type: 'Expense',
    category: 'Vehicle',
    description: 'แม็คโคร',
    amount: 0,
    vehicleId: 'รถแม็คโคร1',
    driverId: 'd1',
    createdAt: DateTime(2026, 8, 12, 10),
  );
}

void main() {
  group('latestVehicleTripsByVehicle', () {
    test('two vehicles yield two rows sorted by name', () {
      final rows = latestVehicleTripsByVehicle(
        [
          _drumTrip(id: 'b', vehicleId: 'รถดรัมพี่โก', perCarTrips: 20),
          _drumTrip(id: 'a', vehicleId: 'รถดรัมโอเว่น', perCarTrips: 41),
        ],
        ymd: '2026-08-12',
      );
      expect(rows.map((t) => t.vehicleId).toList(), [
        'รถดรัมพี่โก',
        'รถดรัมโอเว่น',
      ]);
      expect(rows.length, 2);
    });

    test('duplicate vehicle keeps the newer createdAt', () {
      final older = _drumTrip(
        id: 'old',
        vehicleId: 'รถดรัมโอเว่น',
        perCarTrips: 10,
        createdAt: DateTime(2026, 8, 12, 8),
      );
      final newer = _drumTrip(
        id: 'new',
        vehicleId: 'รถดรัมโอเว่น',
        perCarTrips: 41,
        createdAt: DateTime(2026, 8, 12, 14),
      );
      final rows = latestVehicleTripsByVehicle(
        [older, newer],
        ymd: '2026-08-12',
      );
      expect(rows, hasLength(1));
      expect(rows.single.id, 'new');
      expect(rows.single.perCarTrips, 41);
    });

    test('offline row without createdAt beats server row', () {
      final server = _drumTrip(
        id: 'server',
        vehicleId: 'รถดรัมโอเว่น',
        createdAt: DateTime(2026, 8, 12, 10),
      );
      final offline = _drumTrip(
        id: 'offline',
        vehicleId: 'รถดรัมโอเว่น',
        createdAt: null,
      );
      final rows = latestVehicleTripsByVehicle(
        [server, offline],
        ymd: '2026-08-12',
      );
      expect(rows.single.id, 'offline');
    });

    test('skips macro vehicles and wrong day', () {
      final rows = latestVehicleTripsByVehicle(
        [
          _macroVehicle(id: 'm1'),
          _drumTrip(id: 'other-day', vehicleId: 'รถดรัมโอเว่น', date: '2026-08-11'),
          _legacyVehicle(id: 'ok', vehicleId: 'รถดรัมลุงศักดิ์'),
        ],
        ymd: '2026-08-12',
      );
      expect(rows, hasLength(1));
      expect(rows.single.id, 'ok');
      expect(rows.single.vehicleId, 'รถดรัมลุงศักดิ์');
    });

    test('isVehicleTripHydrateSource rejects sand-home rows', () {
      final sand = AppTransaction(
        id: 'sand',
        date: '2026-08-12',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'VehicleTrip',
        description: 'ทรายที่ล้างที่บ้าน',
        amount: 0,
        vehicleId: 'รถดรัมโอเว่น',
      );
      expect(isVehicleTripHydrateSource(sand), isFalse);
      expect(
        latestVehicleTripsByVehicle([sand], ymd: '2026-08-12'),
        isEmpty,
      );
    });
  });
}
