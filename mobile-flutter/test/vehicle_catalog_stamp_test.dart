import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/models/employee.dart';
import 'package:mobile_flutter/utils/daily_module_transactions.dart';
import 'package:mobile_flutter/utils/vehicle_catalog.dart';

void main() {
  const catalog = VehicleCatalog([
    VehicleCatalogRow(
      id: 'v_abc',
      name: 'รถแม็คโคร SK200-8 (น้องโกลเด้น)',
      defaultDriverId: 'd1',
    ),
  ]);
  const employees = [
    Employee(
      id: 'd1',
      name: 'สมชาย ใจดี',
      nickname: 'น้องโกลเด้น',
      type: 'daily',
    ),
  ];

  test('transactionVehicleLabel prefers vehicle_name', () {
    final t = AppTransaction(
      id: '1',
      date: '2026-08-19',
      type: 'Expense',
      category: 'Vehicle',
      description: 'แม็คโคร',
      amount: 0,
      vehicleId: 'v_abc',
      vehicleName: 'รถแม็คโคร SK200-8 (น้องโกลเด้น)',
    );
    expect(
      transactionVehicleLabel(t),
      'รถแม็คโคร SK200-8 (น้องโกลเด้น)',
    );
    expect(isMacroVehicleTransaction(t), isTrue);
  });

  test('stampVehicleAndDriverNames writes catalog id and display names', () {
    final t = AppTransaction(
      id: '1',
      date: '2026-08-19',
      type: 'Expense',
      category: 'Vehicle',
      description: 'แม็คโคร',
      amount: 0,
      vehicleId: 'รถแม็คโคร SK200-8 (น้องโกลเด้น)',
      driverId: 'd1',
      workDetails: 'ขุดแร่',
    );
    final stamped = stampVehicleAndDriverNames(
      t,
      catalog: catalog,
      employees: employees,
    );
    expect(stamped.vehicleId, 'v_abc');
    expect(stamped.vehicleName, 'รถแม็คโคร SK200-8 (น้องโกลเด้น)');
    expect(stamped.driverId, 'd1');
    expect(stamped.driverName, 'น้องโกลเด้น');
  });

  test('stamp keeps legacy name in vehicle_id when catalog misses', () {
    final t = AppTransaction(
      id: '1',
      date: '2026-08-19',
      type: 'Expense',
      category: 'Vehicle',
      description: 'ดรัม',
      amount: 0,
      vehicleId: 'รถดรัมโอเว่น',
      driverId: 'unknown',
    );
    final stamped = stampVehicleAndDriverNames(
      t,
      catalog: catalog,
      employees: employees,
    );
    expect(stamped.vehicleId, 'รถดรัมโอเว่น');
    expect(stamped.vehicleName, 'รถดรัมโอเว่น');
    expect(stamped.driverName, isNull);
  });
}
