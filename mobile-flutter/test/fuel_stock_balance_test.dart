import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/utils/fuel_stock.dart';

const _day = '2026-08-10';

AppTransaction _fuel({
  required String id,
  required String sub,
  required String movement,
  required double liters,
  String? tank,
  String? workType,
  String? vehicleId,
  String? note,
  String? workDetails,
  DateTime? createdAt,
  String date = _day,
}) =>
    AppTransaction(
      id: id,
      date: date,
      type: 'Expense',
      category: 'Fuel',
      subCategory: sub,
      description: id,
      amount: 0,
      quantity: liters,
      unit: 'L',
      fuelType: 'Diesel',
      fuelMovement: movement,
      fuelTank: tank,
      workType: workType,
      vehicleId: vehicleId,
      note: note,
      workDetails: workDetails,
      createdAt: createdAt,
    );

AppTransaction _sand({
  required String date,
  required List<String> laps,
}) =>
    AppTransaction(
      id: '${date}_sand',
      date: date,
      type: 'Expense',
      category: 'DailyLog',
      subCategory: 'Sand',
      description: 'ร่อนทราย',
      amount: 0,
      workAssignments: {'lapTimes': laps},
    );

void main() {
  group('fuelUsageTankOf', () {
    test('VehicleUsage with empty tank is reserve', () {
      final t = _fuel(
        id: 'vu',
        sub: 'VehicleUsage',
        movement: 'stock_out',
        liters: 100,
        vehicleId: 'แม็คโคร',
      );
      expect(fuelUsageTankOf(t), kFuelTankReserve);
    });

    test('VehicleUsage with main tank stays main', () {
      final t = _fuel(
        id: 'vu',
        sub: 'VehicleUsage',
        movement: 'stock_out',
        liters: 100,
        tank: kFuelTankMain,
        vehicleId: 'แม็คโคร',
      );
      expect(fuelUsageTankOf(t), kFuelTankMain);
    });

    test('other fuel rows with empty tank are main', () {
      final t = _fuel(
        id: 'wd',
        sub: kFuelWithdrawSubCategory,
        movement: 'stock_out',
        liters: 40,
        workType: 'car',
      );
      expect(fuelUsageTankOf(t), kFuelTankMain);
    });
  });

  group('computeFuelStockBalance', () {
    test('machine transfer: main down, reserve up', () {
      final b = computeFuelStockBalance([
        _fuel(
          id: 'out',
          sub: kFuelTransferSubCategory,
          movement: 'stock_out',
          liters: 200,
          tank: kFuelTankMain,
          workType: 'machine',
        ),
        _fuel(
          id: 'in',
          sub: kFuelTransferSubCategory,
          movement: 'stock_in',
          liters: 200,
          tank: kFuelTankReserve,
          workType: 'machine',
        ),
      ]);
      expect(b.mainDiesel, -200);
      expect(b.reserveDiesel, 200);
    });

    test('legacy Withdraw+machine is treated as main→reserve transfer', () {
      final b = computeFuelStockBalance([
        _fuel(
          id: 'wd',
          sub: kFuelWithdrawSubCategory,
          movement: 'stock_out',
          liters: 619,
          workType: 'machine',
        ),
      ]);
      expect(b.mainDiesel, -619);
      expect(b.reserveDiesel, 619);
    });

    test('legacy Withdraw+machine does not double-credit when Transfer exists', () {
      final b = computeFuelStockBalance([
        _fuel(
          id: 'out',
          sub: kFuelTransferSubCategory,
          movement: 'stock_out',
          liters: 200,
          tank: kFuelTankMain,
          workType: 'machine',
        ),
        _fuel(
          id: 'in',
          sub: kFuelTransferSubCategory,
          movement: 'stock_in',
          liters: 200,
          tank: kFuelTankReserve,
          workType: 'machine',
        ),
        _fuel(
          id: 'wd',
          sub: kFuelWithdrawSubCategory,
          movement: 'stock_out',
          liters: 50,
          workType: 'machine',
        ),
      ]);
      expect(b.mainDiesel, -250);
      expect(b.reserveDiesel, 200);
    });

    test('generator mayor and other withdraw from main only', () {
      final b = computeFuelStockBalance([
        _fuel(
          id: 'g',
          sub: kFuelWithdrawSubCategory,
          movement: 'stock_out',
          liters: 10,
          workType: 'generator',
        ),
        _fuel(
          id: 'm',
          sub: kFuelWithdrawSubCategory,
          movement: 'stock_out',
          liters: 20,
          workType: 'mayor',
        ),
        _fuel(
          id: 'o',
          sub: kFuelWithdrawSubCategory,
          movement: 'stock_out',
          liters: 16,
          workType: 'other',
        ),
      ]);
      expect(b.mainDiesel, -46);
      expect(b.reserveDiesel, 0);
      expect(fuelWithdrawPurposeLabelOf(FuelWithdrawPurpose.mayor), 'นายกเบิก');
      expect(fuelWithdrawPurposeCodeOf(FuelWithdrawPurpose.mayor), 'mayor');
    });

    test('macro on main deducts main even when machine was filled that day', () {
      final b = computeFuelStockBalance([
        _fuel(
          id: 'out',
          sub: kFuelTransferSubCategory,
          movement: 'stock_out',
          liters: 580,
          tank: kFuelTankMain,
          workType: 'machine',
        ),
        _fuel(
          id: 'in',
          sub: kFuelTransferSubCategory,
          movement: 'stock_in',
          liters: 580,
          tank: kFuelTankReserve,
          workType: 'machine',
        ),
        _fuel(
          id: 'vu',
          sub: 'VehicleUsage',
          movement: 'stock_out',
          liters: 142,
          tank: kFuelTankMain,
          vehicleId: 'แม็คโคร',
        ),
      ]);
      expect(b.mainDiesel, -722);
      expect(b.reserveDiesel, 580);
    });

    test('macro on reserve deducts reserve only', () {
      final b = computeFuelStockBalance([
        _fuel(
          id: 'vu',
          sub: 'VehicleUsage',
          movement: 'stock_out',
          liters: 100,
          tank: kFuelTankReserve,
          vehicleId: 'แม็คโคร',
        ),
      ]);
      expect(b.mainDiesel, 0);
      expect(b.reserveDiesel, -100);
    });

    test('transfer + macro on reserve does not double-deduct main', () {
      final b = computeFuelStockBalance([
        _fuel(
          id: 'out',
          sub: kFuelTransferSubCategory,
          movement: 'stock_out',
          liters: 580,
          tank: kFuelTankMain,
          workType: 'machine',
        ),
        _fuel(
          id: 'in',
          sub: kFuelTransferSubCategory,
          movement: 'stock_in',
          liters: 580,
          tank: kFuelTankReserve,
          workType: 'machine',
        ),
        _fuel(
          id: 'vu',
          sub: kFuelVehicleUsageSubCategory,
          movement: 'stock_out',
          liters: 142,
          tank: kFuelTankReserve,
          vehicleId: 'แม็คโคร',
        ),
      ]);
      expect(b.mainDiesel, -580);
      expect(b.reserveDiesel, 580 - 142);
    });

    test('stock_out with vehicle but not VehicleUsage does not deduct as macro', () {
      final b = computeFuelStockBalance([
        _fuel(
          id: 'other',
          sub: kFuelWithdrawSubCategory,
          movement: 'stock_out',
          liters: 50,
          tank: kFuelTankMain,
          workType: 'generator',
          vehicleId: 'แม็คโคร',
        ),
      ]);
      // เบิกเครื่องปั่นไฟหักหลักครั้งเดียว — ไม่ถูกนับซ้ำเป็นแม็คโคร
      expect(b.mainDiesel, -50);
      expect(b.reserveDiesel, 0);
    });

    test('legacy VehicleUsage with empty tank deducts reserve', () {
      final b = computeFuelStockBalance([
        _fuel(
          id: 'vu',
          sub: 'VehicleUsage',
          movement: 'stock_out',
          liters: 109,
          vehicleId: 'แม็คโคร',
        ),
      ]);
      expect(b.mainDiesel, 0);
      expect(b.reserveDiesel, -109);
    });

    test('car fill deducts main', () {
      final b = computeFuelStockBalance([
        _fuel(
          id: 'car',
          sub: kFuelWithdrawSubCategory,
          movement: 'stock_out',
          liters: 40,
          tank: kFuelTankMain,
          workType: 'car',
          vehicleId: kFuelCarFillMighty,
        ),
      ]);
      expect(b.mainDiesel, -40);
      expect(b.reserveDiesel, 0);
    });

    test('rows on cutover day 2026-08-01 are counted', () {
      final b = computeFuelStockBalance(
        [
          _fuel(
            id: 'in',
            sub: kFuelStockInSubCategory,
            movement: 'stock_in',
            liters: 500,
            tank: kFuelTankMain,
            date: '2026-08-01',
          ),
          _fuel(
            id: 'out',
            sub: kFuelWithdrawSubCategory,
            movement: 'stock_out',
            liters: 100,
            tank: kFuelTankMain,
            workType: 'car',
            date: '2026-08-01',
          ),
        ],
        openingDiesel: 1000,
      );
      expect(b.mainDiesel, 1400); // 1000 + 500 - 100
    });

    test('rows before cutover 2026-07-31 are ignored', () {
      final b = computeFuelStockBalance(
        [
          _fuel(
            id: 'in',
            sub: kFuelStockInSubCategory,
            movement: 'stock_in',
            liters: 9000,
            tank: kFuelTankMain,
            date: '2026-07-31',
          ),
          _fuel(
            id: 'out',
            sub: kFuelWithdrawSubCategory,
            movement: 'stock_out',
            liters: 200,
            tank: kFuelTankMain,
            workType: 'car',
            date: '2026-07-31',
          ),
        ],
        openingDiesel: 8500,
      );
      expect(b.mainDiesel, 8500);
      expect(b.reserveDiesel, 0);
    });

    test('sand sieve hours × 18 L from reserve, lunch deducted', () {
      // 08:00–15:00 minus lunch 12–13 = 6 hours × 18 = 108 L
      final b = computeFuelStockBalance([
        _sand(
          date: '2026-08-05',
          laps: const ['05/08 08:00:00', '05/08 15:00:00'],
        ),
      ]);
      expect(b.mainDiesel, 0);
      expect(b.reserveDiesel, -108);
    });

    test('does not double-count sand hours when SandSieve row exists', () {
      final b = computeFuelStockBalance([
        _sand(
          date: '2026-08-05',
          laps: const ['05/08 08:00:00', '05/08 15:00:00'],
        ),
        _fuel(
          id: fuelSandSieveTxId('2026-08-05'),
          sub: kFuelSandSieveSubCategory,
          movement: 'stock_out',
          liters: 108,
          tank: kFuelTankReserve,
          date: '2026-08-05',
        ),
      ]);
      expect(b.reserveDiesel, -108);
      expect(b.mainDiesel, 0);
    });
  });

  group('applyFuelBalanceDelta', () {
    const start = FuelStockBalance(mainDiesel: 1000, reserveDiesel: 200);

    test('VehicleUsage on main deducts main immediately', () {
      final next = applyFuelBalanceDelta(
        start,
        _fuel(
          id: 'vu',
          sub: 'VehicleUsage',
          movement: 'stock_out',
          liters: 50,
          tank: kFuelTankMain,
          vehicleId: 'แม็คโคร',
        ),
      );
      expect(next, isNotNull);
      expect(next!.mainDiesel, 950);
      expect(next.reserveDiesel, 200);
    });

    test('legacy Withdraw+machine returns null to force full recompute', () {
      final next = applyFuelBalanceDelta(
        start,
        _fuel(
          id: 'wd',
          sub: kFuelWithdrawSubCategory,
          movement: 'stock_out',
          liters: 80,
          workType: 'machine',
        ),
      );
      expect(next, isNull);
    });

    test('reserveShortfallLiters reports absolute negative reserve', () {
      const bal = FuelStockBalance(mainDiesel: 100, reserveDiesel: -45.5);
      expect(bal.reserveShortfallLiters, 45.5);
    });
  });

  group('latest fuel day rows', () {
    test('isFuelCarFillRow only for withdraw+car', () {
      expect(
        isFuelCarFillRow(
          _fuel(
            id: 'car',
            sub: kFuelWithdrawSubCategory,
            movement: 'stock_out',
            liters: 40,
            workType: 'car',
            vehicleId: kFuelCarFillMighty,
          ),
        ),
        isTrue,
      );
      expect(
        isFuelCarFillRow(
          _fuel(
            id: 'gen',
            sub: kFuelWithdrawSubCategory,
            movement: 'stock_out',
            liters: 20,
            workType: 'generator',
          ),
        ),
        isFalse,
      );
    });

    test('latestFuelCarFillForVehicle picks newest by createdAt', () {
      final older = _fuel(
        id: 'old',
        sub: kFuelWithdrawSubCategory,
        movement: 'stock_out',
        liters: 20,
        workType: 'car',
        vehicleId: kFuelCarFillMighty,
        createdAt: DateTime.utc(2026, 8, 10, 8),
      );
      final newer = _fuel(
        id: 'new',
        sub: kFuelWithdrawSubCategory,
        movement: 'stock_out',
        liters: 40,
        workType: 'car',
        vehicleId: kFuelCarFillMighty,
        createdAt: DateTime.utc(2026, 8, 10, 15),
      );
      final hit = latestFuelCarFillForVehicle(
        dayYmd: _day,
        transactions: [older, newer],
        vehicleId: kFuelCarFillMighty,
      );
      expect(hit?.id, 'new');
      expect(fuelTxLiters(hit!), 40);
    });

    test('latestFuelCarFillForVehicle empty vehicleId matches other cars', () {
      final known = _fuel(
        id: 'mighty',
        sub: kFuelWithdrawSubCategory,
        movement: 'stock_out',
        liters: 10,
        workType: 'car',
        vehicleId: kFuelCarFillMighty,
        createdAt: DateTime.utc(2026, 8, 10, 12),
      );
      final other = _fuel(
        id: 'other',
        sub: kFuelWithdrawSubCategory,
        movement: 'stock_out',
        liters: 25,
        workType: 'car',
        vehicleId: 'รถปิคอัพ',
        createdAt: DateTime.utc(2026, 8, 10, 9),
      );
      final hit = latestFuelCarFillForVehicle(
        dayYmd: _day,
        transactions: [known, other],
        vehicleId: '',
      );
      expect(hit?.id, 'other');
    });

    test('latestFuelWithdrawForPurpose picks transfer out for machine', () {
      final outTx = _fuel(
        id: 'xfer_out',
        sub: kFuelTransferSubCategory,
        movement: 'stock_out',
        liters: 100,
        tank: kFuelTankMain,
        workType: 'machine',
        note: 'xfer:1',
        createdAt: DateTime.utc(2026, 8, 10, 10),
      );
      final inTx = _fuel(
        id: 'xfer_in',
        sub: kFuelTransferSubCategory,
        movement: 'stock_in',
        liters: 100,
        tank: kFuelTankReserve,
        workType: 'machine',
        note: 'xfer:1',
        createdAt: DateTime.utc(2026, 8, 10, 10),
      );
      final gen = _fuel(
        id: 'gen',
        sub: kFuelWithdrawSubCategory,
        movement: 'stock_out',
        liters: 30,
        workType: 'generator',
        createdAt: DateTime.utc(2026, 8, 10, 11),
      );
      final hit = latestFuelWithdrawForPurpose(
        dayYmd: _day,
        transactions: [outTx, inTx, gen],
        purpose: FuelWithdrawPurpose.machine,
      );
      expect(hit?.id, 'xfer_out');
      final pair = fuelMachineTransferPair(
        outTx: hit!,
        transactions: [outTx, inTx, gen],
      );
      expect(pair.inTx?.id, 'xfer_in');
    });

    test('latestFuelWithdrawForPurpose picks newest generator', () {
      final older = _fuel(
        id: 'g1',
        sub: kFuelWithdrawSubCategory,
        movement: 'stock_out',
        liters: 10,
        workType: 'generator',
        createdAt: DateTime.utc(2026, 8, 10, 8),
      );
      final newer = _fuel(
        id: 'g2',
        sub: kFuelWithdrawSubCategory,
        movement: 'stock_out',
        liters: 35,
        workType: 'generator',
        createdAt: DateTime.utc(2026, 8, 10, 16),
      );
      final hit = latestFuelWithdrawForPurpose(
        dayYmd: _day,
        transactions: [older, newer],
        purpose: FuelWithdrawPurpose.generator,
      );
      expect(hit?.id, 'g2');
    });
  });

  group('latestFuel*ForDay + summaries', () {
    test('latestFuelStockInForDay skips transfer stock_in', () {
      final truck = _fuel(
        id: 'in1',
        sub: kFuelStockInSubCategory,
        movement: 'stock_in',
        liters: 500,
        tank: kFuelTankMain,
        workDetails: '08:30 (ผู้กรอก: A)',
        createdAt: DateTime.utc(2026, 8, 10, 8),
      );
      final xferIn = _fuel(
        id: 'xfer_in',
        sub: kFuelTransferSubCategory,
        movement: 'stock_in',
        liters: 100,
        tank: kFuelTankReserve,
        workType: 'machine',
        note: 'xfer:1',
        createdAt: DateTime.utc(2026, 8, 10, 12),
      );
      final hit = latestFuelStockInForDay(
        dayYmd: _day,
        transactions: [truck, xferIn],
      );
      expect(hit?.id, 'in1');
      expect(
        fuelExistingEntrySummary(hit),
        'มีข้อมูลแล้ว · 500 ลิตร · 08:30',
      );
    });

    test('latestFuelCarFillForDay picks newest across vehicles', () {
      final mighty = _fuel(
        id: 'c1',
        sub: kFuelWithdrawSubCategory,
        movement: 'stock_out',
        liters: 40,
        workType: 'car',
        vehicleId: kFuelCarFillMighty,
        workDetails: '07:00',
        createdAt: DateTime.utc(2026, 8, 10, 7),
      );
      final taplien = _fuel(
        id: 'c2',
        sub: kFuelWithdrawSubCategory,
        movement: 'stock_out',
        liters: 55,
        workType: 'car',
        vehicleId: kFuelCarFillTaplien,
        workDetails: '15:00',
        createdAt: DateTime.utc(2026, 8, 10, 15),
      );
      final hit = latestFuelCarFillForDay(
        dayYmd: _day,
        transactions: [mighty, taplien],
      );
      expect(hit?.id, 'c2');
      expect(fuelCarFillVehicleFromId(hit!.vehicleId), FuelCarFillVehicle.taplien);
    });

    test('legacy taplien vehicleId maps and matches new id lookup', () {
      final legacy = _fuel(
        id: 'c_legacy',
        sub: kFuelWithdrawSubCategory,
        movement: 'stock_out',
        liters: 30,
        workType: 'car',
        vehicleId: kFuelCarFillTaplienLegacy,
        workDetails: '10:00',
        createdAt: DateTime.utc(2026, 8, 10, 10),
      );
      expect(
        fuelCarFillVehicleFromId(legacy.vehicleId),
        FuelCarFillVehicle.taplien,
      );
      expect(
        fuelCarFillVehicleIdMatches(
          kFuelCarFillTaplienLegacy,
          kFuelCarFillTaplien,
        ),
        isTrue,
      );
      final hit = latestFuelCarFillForVehicle(
        dayYmd: _day,
        transactions: [legacy],
        vehicleId: kFuelCarFillTaplien,
      );
      expect(hit?.id, 'c_legacy');
      final taplienDay = latestFuelTaplienFillForDay(
        dayYmd: _day,
        transactions: [legacy],
      );
      expect(taplienDay?.id, 'c_legacy');
    });

    test('other taplien legacy ids map to taplien enum', () {
      for (final legacy in ['ISUZU KB', 'IsuzuKB', 'รถISUZUKB', 'ISUZUตา']) {
        expect(
          fuelCarFillVehicleFromId(legacy),
          FuelCarFillVehicle.taplien,
        );
      }
    });

    test('latestFuelWithdrawForDay picks newest purpose of the day', () {
      final machine = _fuel(
        id: 'xfer_out',
        sub: kFuelTransferSubCategory,
        movement: 'stock_out',
        liters: 200,
        tank: kFuelTankMain,
        workType: 'machine',
        note: 'xfer:1',
        workDetails: '09:00',
        createdAt: DateTime.utc(2026, 8, 10, 9),
      );
      final gen = _fuel(
        id: 'gen',
        sub: kFuelWithdrawSubCategory,
        movement: 'stock_out',
        liters: 25,
        workType: 'generator',
        workDetails: '14:00',
        createdAt: DateTime.utc(2026, 8, 10, 14),
      );
      final hit = latestFuelWithdrawForDay(
        dayYmd: _day,
        transactions: [machine, gen],
      );
      expect(hit?.id, 'gen');
    });

    test('buildFuelSubModeDaySummaries fills modes with data', () {
      final truck = _fuel(
        id: 'in1',
        sub: kFuelStockInSubCategory,
        movement: 'stock_in',
        liters: 300,
        workDetails: '10:00',
        createdAt: DateTime.utc(2026, 8, 10, 10),
      );
      final usage = _fuel(
        id: 'vu',
        sub: 'VehicleUsage',
        movement: 'stock_out',
        liters: 80,
        vehicleId: 'แม็คโคร 1',
        createdAt: DateTime.utc(2026, 8, 10, 11),
      );
      final summaries = buildFuelSubModeDaySummaries(
        dayYmd: _day,
        transactions: [truck, usage],
      );
      expect(summaries.stockIn, contains('มีข้อมูลแล้ว'));
      expect(summaries.stockIn, contains('300'));
      expect(summaries.macroUsage, contains('1 คัน'));
      expect(summaries.withdraw, '');
      expect(summaries.carFill, '');
    });
  });
}
