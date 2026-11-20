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
  String? description,
  DateTime? createdAt,
  String date = _day,
}) =>
    AppTransaction(
      id: id,
      date: date,
      type: 'Expense',
      category: 'Fuel',
      subCategory: sub,
      description: description ?? id,
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

void main() {
  group('multi-entry fuel withdrawals on the same day', () {
    test(
      'returns multiple machine transfer rounds sorted chronologically by time and reconciles total',
      () {
        final afternoonOut = _fuel(
          id: 'xfer_out_2',
          sub: kFuelTransferSubCategory,
          movement: 'stock_out',
          liters: 600,
          tank: kFuelTankMain,
          workType: 'machine',
          note: 'xfer:2',
          workDetails: '13:00 (ผู้กรอก: สมชาย)',
          createdAt: DateTime.utc(2026, 8, 10, 6, 0),
        );
        final afternoonIn = _fuel(
          id: 'xfer_in_2',
          sub: kFuelTransferSubCategory,
          movement: 'stock_in',
          liters: 600,
          tank: kFuelTankReserve,
          workType: 'machine',
          note: 'xfer:2',
          workDetails: '13:00 (ผู้กรอก: สมชาย)',
          createdAt: DateTime.utc(2026, 8, 10, 6, 0),
        );
        final morningOut = _fuel(
          id: 'xfer_out_1',
          sub: kFuelTransferSubCategory,
          movement: 'stock_out',
          liters: 600,
          tank: kFuelTankMain,
          workType: 'machine',
          note: 'xfer:1',
          workDetails: '09:00 (ผู้กรอก: สมชาย)',
          createdAt: DateTime.utc(2026, 8, 10, 2, 0),
        );
        final morningIn = _fuel(
          id: 'xfer_in_1',
          sub: kFuelTransferSubCategory,
          movement: 'stock_in',
          liters: 600,
          tank: kFuelTankReserve,
          workType: 'machine',
          note: 'xfer:1',
          workDetails: '09:00 (ผู้กรอก: สมชาย)',
          createdAt: DateTime.utc(2026, 8, 10, 2, 0),
        );
        final txs = [afternoonOut, afternoonIn, morningOut, morningIn];

        final entries = fuelWithdrawEntriesForPurpose(
          dayYmd: _day,
          transactions: txs,
          purpose: FuelWithdrawPurpose.machine,
        );
        expect(entries.map((e) => e.id).toList(), ['xfer_out_1', 'xfer_out_2']);
        expect(fuelWithdrawTimeLabel(entries[0]), '09:00');
        expect(fuelWithdrawTimeLabel(entries[1]), '13:00');

        // Each outTx resolves its own exact Transfer inTx pair
        expect(
          fuelMachineTransferPair(outTx: entries[0], transactions: txs).inTx?.id,
          'xfer_in_1',
        );
        expect(
          fuelMachineTransferPair(outTx: entries[1], transactions: txs).inTx?.id,
          'xfer_in_2',
        );

        // Stock balance sums both rounds accurately (-1200 main, +1200 reserve)
        final bal = computeFuelStockBalance(
          txs,
          openingDiesel: 3000,
          openingReserveDiesel: 100,
        );
        expect(bal.mainDiesel, 1800);
        expect(bal.reserveDiesel, 1300);

        // Reconcile sums both rounds
        final rec = fuelMachineReconcileForDay(
          _day,
          txs,
          tank: kFuelTankReserve,
        );
        expect(rec.machineWithdraw, 1200);
        expect(rec.remaining, 1200);

        // Purpose summary reports 2 rounds and total 1200 liters
        final summary = fuelWithdrawSummaryForPurpose(
          dayYmd: _day,
          transactions: txs,
          purpose: FuelWithdrawPurpose.machine,
        );
        expect(summary.count, 2);
        expect(summary.totalLiters, 1200);
        expect(
          formatFuelWithdrawPurposeSummary(summary),
          '2 รอบ · รวม 1200 ลิตร',
        );
      },
    );

    test(
      'fuelWithdrawEntriesForDay collects all withdraw purposes and excludes unrelated fuel rows',
      () {
        final machine1 = _fuel(
          id: 'm1',
          sub: kFuelTransferSubCategory,
          movement: 'stock_out',
          liters: 600,
          tank: kFuelTankMain,
          workType: 'machine',
          note: 'xfer:1',
          workDetails: '09:00',
        );
        final machine1In = _fuel(
          id: 'm1_in',
          sub: kFuelTransferSubCategory,
          movement: 'stock_in',
          liters: 600,
          tank: kFuelTankReserve,
          workType: 'machine',
          note: 'xfer:1',
          workDetails: '09:00',
        );
        final machine2 = _fuel(
          id: 'm2',
          sub: kFuelTransferSubCategory,
          movement: 'stock_out',
          liters: 600,
          tank: kFuelTankMain,
          workType: 'machine',
          note: 'xfer:2',
          workDetails: '13:00',
        );
        final gen = _fuel(
          id: 'g1',
          sub: kFuelWithdrawSubCategory,
          movement: 'stock_out',
          liters: 25,
          tank: kFuelTankMain,
          workType: 'generator',
          workDetails: '10:30',
        );
        final taplienLegacy = _fuel(
          id: 'car1',
          sub: kFuelWithdrawSubCategory,
          movement: 'stock_out',
          liters: 50,
          tank: kFuelTankMain,
          workType: 'car',
          vehicleId: kFuelCarFillTaplienLegacy,
          workDetails: '11:15',
        );
        final tenWheeler = _fuel(
          id: 'car2',
          sub: kFuelWithdrawSubCategory,
          movement: 'stock_out',
          liters: 120,
          tank: kFuelTankMain,
          workType: 'car',
          vehicleId: kFuelCarFillTenWheelerMayor,
          workDetails: '15:45',
        );
        final mayor = _fuel(
          id: 'may1',
          sub: kFuelWithdrawSubCategory,
          movement: 'stock_out',
          liters: 40,
          tank: kFuelTankMain,
          workType: 'mayor',
          workDetails: '16:00',
        );
        // Should NOT appear in withdraw screen entries:
        final mighty = _fuel(
          id: 'mighty',
          sub: kFuelWithdrawSubCategory,
          movement: 'stock_out',
          liters: 45,
          tank: kFuelTankMain,
          workType: 'car',
          vehicleId: kFuelCarFillMighty,
          workDetails: '08:00',
        );
        final stockIn = _fuel(
          id: 'in1',
          sub: kFuelStockInSubCategory,
          movement: 'stock_in',
          liters: 3000,
          tank: kFuelTankMain,
          workDetails: '07:00',
        );
        final macroUsage = _fuel(
          id: 'vu1',
          sub: kFuelVehicleUsageSubCategory,
          movement: 'stock_out',
          liters: 90,
          tank: kFuelTankReserve,
          vehicleId: 'แม็คโคร 1',
          workDetails: '17:00',
        );
        final otherDay = _fuel(
          id: 'prev',
          sub: kFuelTransferSubCategory,
          movement: 'stock_out',
          liters: 500,
          tank: kFuelTankMain,
          workType: 'machine',
          date: '2026-08-09',
          workDetails: '08:00',
        );

        final all = [
          mayor,
          tenWheeler,
          machine2,
          taplienLegacy,
          gen,
          machine1,
          machine1In,
          mighty,
          stockIn,
          macroUsage,
          otherDay,
        ];

        final entries = fuelWithdrawEntriesForDay(
          dayYmd: _day,
          transactions: all,
        );
        expect(
          entries.map((e) => e.id).toList(),
          ['m1', 'g1', 'car1', 'm2', 'car2', 'may1'],
        );
        expect(fuelWithdrawPurposeOfTx(entries[0]), FuelWithdrawPurpose.machine);
        expect(fuelWithdrawPurposeOfTx(entries[1]), FuelWithdrawPurpose.generator);
        expect(fuelWithdrawPurposeOfTx(entries[2]), FuelWithdrawPurpose.car);
        expect(fuelWithdrawPurposeOfTx(entries[4]), FuelWithdrawPurpose.tenWheelerMayor);
        expect(fuelWithdrawPurposeOfTx(entries[5]), FuelWithdrawPurpose.mayor);

        final daySummary = fuelWithdrawSummaryForDay(
          dayYmd: _day,
          transactions: all,
        );
        expect(daySummary.count, 6);
        expect(daySummary.totalLiters, 1435);
      },
    );

    test(
      'buildFuelSubModeDaySummaries shows single-entry format for 1 entry and multi-entry total for 2+',
      () {
        final one = _fuel(
          id: 'm1',
          sub: kFuelTransferSubCategory,
          movement: 'stock_out',
          liters: 600,
          tank: kFuelTankMain,
          workType: 'machine',
          note: 'xfer:1',
          workDetails: '09:00',
        );
        final two = _fuel(
          id: 'm2',
          sub: kFuelTransferSubCategory,
          movement: 'stock_out',
          liters: 600,
          tank: kFuelTankMain,
          workType: 'machine',
          note: 'xfer:2',
          workDetails: '13:00',
        );

        final singleSummary = buildFuelSubModeDaySummaries(
          dayYmd: _day,
          transactions: [one],
        );
        expect(singleSummary.withdraw, 'มีข้อมูลแล้ว · 600 ลิตร · 09:00');

        final multiSummary = buildFuelSubModeDaySummaries(
          dayYmd: _day,
          transactions: [one, two],
        );
        expect(multiSummary.withdraw, 'มีข้อมูลแล้ว · 2 รายการ · รวม 1200 ลิตร');
      },
    );

    test('fuelWithdrawClockMinutes parses HH:mm, HH.mm, and ignores recorder suffix', () {
      expect(fuelWithdrawClockMinutes('09:00'), 540);
      expect(fuelWithdrawClockMinutes('09.30 น. (ผู้กรอก: เอ)'), 570);
      expect(fuelWithdrawClockMinutes('13:05'), 785);
      expect(fuelWithdrawClockMinutes(''), isNull);
      expect(fuelWithdrawClockMinutes(null), isNull);
    });
  });

  group('computeFuelWithdrawPendingDeltas', () {
    test('add mode machine transfers liters from main to reserve', () {
      final d = computeFuelWithdrawPendingDeltas(
        purpose: FuelWithdrawPurpose.machine,
        inputLiters: 600,
        isEditing: false,
      );
      expect(d.mainDelta, -600);
      expect(d.reserveDelta, 600);
    });

    test('add mode non-machine deducts main only', () {
      final d = computeFuelWithdrawPendingDeltas(
        purpose: FuelWithdrawPurpose.generator,
        inputLiters: 30,
        isEditing: false,
      );
      expect(d.mainDelta, -30);
      expect(d.reserveDelta, 0);
    });

    test('edit mode computes net delta without double-subtracting prior liters', () {
      // Editing 600 -> 600 yields 0 delta
      final same = computeFuelWithdrawPendingDeltas(
        purpose: FuelWithdrawPurpose.machine,
        inputLiters: 600,
        isEditing: true,
        priorLiters: 600,
      );
      expect(same.mainDelta, 0);
      expect(same.reserveDelta, 0);

      // Editing 600 -> 550 refunds +50 to main and removes -50 from reserve
      final less = computeFuelWithdrawPendingDeltas(
        purpose: FuelWithdrawPurpose.machine,
        inputLiters: 550,
        isEditing: true,
        priorLiters: 600,
      );
      expect(less.mainDelta, 50);
      expect(less.reserveDelta, -50);

      // Editing generator 20 -> 35 deducts additional -15 from main
      final moreGen = computeFuelWithdrawPendingDeltas(
        purpose: FuelWithdrawPurpose.generator,
        inputLiters: 35,
        isEditing: true,
        priorLiters: 20,
      );
      expect(moreGen.mainDelta, -15);
      expect(moreGen.reserveDelta, 0);
    });
  });
}
