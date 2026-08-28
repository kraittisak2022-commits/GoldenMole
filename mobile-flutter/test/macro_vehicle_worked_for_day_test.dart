import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/utils/daily_module_transactions.dart';

const _day = '2026-08-28';
const _car = 'แม็คโคร 01';

AppTransaction _macro({
  required String id,
  String date = _day,
  String? vehicleId,
  String? vehicleName,
  String? driverId,
  String? workDetails,
}) =>
    AppTransaction(
      id: id,
      date: date,
      type: 'Expense',
      category: 'Vehicle',
      description: id,
      amount: 0,
      vehicleId: vehicleId,
      vehicleName: vehicleName,
      driverId: driverId,
      workDetails: workDetails,
    );

void main() {
  group('macroVehicleWorkedForDay', () {
    test('true when macro row has work details', () {
      final txs = [
        _macro(
          id: 'm1',
          vehicleName: _car,
          driverId: 'emp1',
          workDetails: 'ขุดดินหน้างาน',
        ),
      ];
      expect(macroVehicleWorkedForDay(_day, _car, txs), isTrue);
    });

    test('false when macro row has driver only (no work details)', () {
      final txs = [
        _macro(
          id: 'm1',
          vehicleName: _car,
          driverId: 'emp1',
          workDetails: '',
        ),
      ];
      expect(macroVehicleWorkedForDay(_day, _car, txs), isFalse);
    });

    test('matches legacy rows that store name in vehicle_id', () {
      final txs = [
        _macro(
          id: 'm1',
          vehicleId: _car,
          driverId: 'emp1',
          workDetails: 'ขนดิน',
        ),
      ];
      expect(macroVehicleWorkedForDay(_day, _car, txs), isTrue);
    });

    test('false for other day or other vehicle', () {
      final txs = [
        _macro(
          id: 'm1',
          vehicleName: _car,
          workDetails: 'ขุดดิน',
        ),
      ];
      expect(macroVehicleWorkedForDay('2026-08-27', _car, txs), isFalse);
      expect(macroVehicleWorkedForDay(_day, 'แม็คโคร 99', txs), isFalse);
    });
  });
}
