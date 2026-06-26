import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/models/employee.dart';
import 'package:mobile_flutter/utils/daily_module_transactions.dart';

void main() {
  const day = '2026-05-19';

  test('vehicle trip card shows vehicles and period trips', () {
    final txs = [
      AppTransaction(
        id: 'v1',
        date: day,
        type: 'Expense',
        category: 'Vehicle',
        description: 'เที่ยว',
        amount: 0,
        vehicleId: 'ดรัม-1',
        tripMorning: 2,
        tripAfternoon: 3,
      ),
      AppTransaction(
        id: 'v2',
        date: day,
        type: 'Expense',
        category: 'Vehicle',
        description: 'เที่ยว',
        amount: 0,
        vehicleId: 'ดรัม-2',
        tripMorning: 1,
        tripAfternoon: 0,
      ),
    ];
    expect(
      dailyVehicleTripModuleStatusLabel(day, txs),
      '2 คัน · เช้า 3 เที่ยว · บ่าย 3 เที่ยว',
    );
  });

  test('macro vehicle card counts saved rows', () {
    final txs = [
      AppTransaction(
        id: 'm1',
        date: day,
        type: 'Expense',
        category: 'Vehicle',
        description: 'แม็คโคร',
        amount: 0,
        vehicleId: 'แม็คโคร 01',
        driverId: 'd1',
      ),
      AppTransaction(
        id: 'm2',
        date: day,
        type: 'Expense',
        category: 'Vehicle',
        description: 'แม็คโคร',
        amount: 0,
        vehicleId: 'แม็คโคร 02',
        workDetails: 'ขุด',
      ),
    ];
    expect(dailyMacroVehicleModuleStatusLabel(day, txs), 'ใช้แม็คโคร 2 คัน');
  });

  test('fuel card sums vehicle usage liters and coverage', () {
    final txs = [
      AppTransaction(
        id: 'm1',
        date: day,
        type: 'Expense',
        category: 'Vehicle',
        description: 'แม็คโคร',
        amount: 0,
        vehicleId: 'แม็คโคร 01',
        driverId: 'd1',
      ),
      AppTransaction(
        id: 'm2',
        date: day,
        type: 'Expense',
        category: 'Vehicle',
        description: 'แม็คโคร',
        amount: 0,
        vehicleId: 'แม็คโคร 02',
        driverId: 'd2',
      ),
      AppTransaction(
        id: 'f1',
        date: day,
        type: 'Expense',
        category: 'Fuel',
        description: 'น้ำมัน',
        amount: 0,
        quantity: 120,
        fuelMovement: 'stock_out',
        vehicleId: 'แม็คโคร 01',
      ),
    ];
    expect(
      dailyFuelModuleStatusLabel(day, txs),
      'ใช้งาน 2 คัน · แจ้ง 1/2 คัน · ยังไม่ครบ · 120 ลิตร',
    );
    expect(
      resolveFuelModuleFillStatus(day, txs),
      DailyModuleFillStatus.incomplete,
    );
  });

  test('fuel card shows complete when all used vehicles reported', () {
    final txs = [
      AppTransaction(
        id: 'm1',
        date: day,
        type: 'Expense',
        category: 'Vehicle',
        description: 'แม็คโคร',
        amount: 0,
        vehicleId: 'แม็คโคร 01',
        driverId: 'd1',
      ),
      AppTransaction(
        id: 'f1',
        date: day,
        type: 'Expense',
        category: 'Fuel',
        description: 'น้ำมัน',
        amount: 0,
        quantity: 80,
        fuelMovement: 'stock_out',
        vehicleId: 'แม็คโคร 01',
      ),
    ];
    expect(
      dailyFuelModuleStatusLabel(day, txs),
      'ใช้งาน 1 คัน · แจ้ง 1/1 คัน · ครบแล้ว · 80 ลิตร',
    );
    expect(
      resolveFuelModuleFillStatus(day, txs),
      DailyModuleFillStatus.complete,
    );
  });

  test('fuel card ignores stock-in when summing liters', () {
    final txs = [
      AppTransaction(
        id: 'f1',
        date: day,
        type: 'Expense',
        category: 'Fuel',
        description: 'รับเข้า',
        amount: 500,
        quantity: 1000,
        fuelMovement: 'stock_in',
      ),
      AppTransaction(
        id: 'f2',
        date: day,
        type: 'Expense',
        category: 'Fuel',
        description: 'เติมรถ',
        amount: 0,
        quantity: 50,
        fuelMovement: 'stock_out',
        vehicleId: 'แม็คโคร 01',
      ),
    ];
    expect(
      dailyFuelModuleStatusLabel(day, txs),
      'แจ้ง 1 คัน · 50 ลิตร',
    );
  });

  test('home sand card shows washed and remaining drums', () {
    final all = [
      AppTransaction(
        id: 'ob',
        date: '2026-05-18',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: 'จำนวนถังที่ได้วันนี้',
        amount: 0,
        drumsObtained: 10,
      ),
      AppTransaction(
        id: 'wash18',
        date: '2026-05-18',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: 'ทรายที่ล้างที่บ้าน',
        amount: 0,
        drumsWashedAtHome: 4,
      ),
      AppTransaction(
        id: 'ob19',
        date: day,
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: 'จำนวนถังที่ได้วันนี้',
        amount: 0,
        drumsObtained: 5,
      ),
      AppTransaction(
        id: 'wash19',
        date: day,
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: 'ทรายที่ล้างที่บ้าน',
        amount: 0,
        drumsWashedAtHome: 2,
      ),
    ];
    expect(
      dailyHomeSandModuleStatusLabel(
        day,
        all.where((t) => t.date == day),
        allTransactionsForStock: all,
      ),
      'ล้าง 2 ถัง · คงเหลือ 9 ถัง',
    );
  });

  test('labor work card counts unique employees', () {
    final txs = [
      AppTransaction(
        id: 'l1',
        date: day,
        type: 'Expense',
        category: 'ค่าแรง',
        description: 'งาน',
        amount: 0,
        employeeIds: ['e1', 'e2'],
      ),
      AppTransaction(
        id: 'l2',
        date: day,
        type: 'Expense',
        category: 'Labor',
        description: 'งาน',
        amount: 0,
        laborStatus: 'Work',
        employeeIds: ['e2', 'e3'],
      ),
    ];
    expect(dailyLaborWorkModuleStatusLabel(day, txs), 'มาทำงาน 3 คน');
  });

  test('OT card lists names and hours', () {
    final txs = [
      AppTransaction(
        id: 'o1',
        date: day,
        type: 'Expense',
        category: 'Labor',
        description: 'OT',
        amount: 0,
        laborStatus: 'OT',
        employeeIds: ['e2'],
        otHours: 2,
      ),
      AppTransaction(
        id: 'o2',
        date: day,
        type: 'Expense',
        category: 'Labor',
        description: 'OT',
        amount: 0,
        subCategory: 'ot',
        employeeIds: ['e1'],
        otHours: 1.5,
      ),
    ];
    final employees = [
      const Employee(
        id: 'e1',
        name: 'สมชาย',
        nickname: 'ชาย',
        type: 'daily',
        position: 'ช่าง',
      ),
      const Employee(
        id: 'e2',
        name: 'สมหญิง',
        nickname: 'หญิง',
        type: 'daily',
        position: 'คนขับ',
      ),
    ];
    final label = dailyOtModuleStatusLabel(day, txs, employees);
    expect(label, contains('ชาย'));
    expect(label, contains('1.5 ชม.'));
    expect(label, contains('หญิง'));
    expect(label, contains('2 ชม.'));
  });

  test('dailyModuleCardStatusLabel routes categories', () {
    expect(
      dailyModuleCardStatusLabel(
        moduleCategory: 'น้ำมัน',
        dayKey: day,
        dayTransactions: [
          AppTransaction(
            id: 'f',
            date: day,
            type: 'Expense',
            category: 'Fuel',
            description: 'น้ำมัน',
            amount: 0,
            quantity: 10,
            fuelMovement: 'stock_out',
            vehicleId: 'แม็คโคร 01',
          ),
        ],
      ),
      'แจ้ง 1 คัน · 10 ลิตร',
    );
    expect(
      dailyModuleCardStatusLabel(
        moduleCategory: 'เหตุการณ์',
        dayKey: day,
        dayTransactions: const [],
      ),
      isNull,
    );
  });

  test('count record menu card reflects trip and sand saves', () {
    final txs = [
      AppTransaction(
        id: 'trip1',
        date: day,
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'VehicleTrip',
        description: 'ดรัม-1: 3 เที่ยว',
        amount: 0,
        vehicleId: 'ดรัม-1',
        tripCount: 3,
        perCarTrips: 3,
      ),
      AppTransaction(
        id: 'sand1',
        date: day,
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: 'ร่อนทราย: 2 รอบ',
        amount: 0,
        drumsObtained: 2,
      ),
    ];
    expect(
      resolveCountRecordMenuFillStatus(day, txs),
      DailyModuleFillStatus.complete,
    );
    expect(
      countRecordMenuStatusLabel(day, txs),
      '1 คัน · 3 เที่ยว · ร่อน 2 รอบ',
    );
  });

  test('count record menu card stays pending without saved counts', () {
    final txs = [
      AppTransaction(
        id: 'trip0',
        date: day,
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'VehicleTrip',
        description: 'ดรัม-1',
        amount: 0,
        vehicleId: 'ดรัม-1',
      ),
    ];
    expect(
      resolveCountRecordMenuFillStatus(day, txs),
      DailyModuleFillStatus.incomplete,
    );
    expect(countRecordMenuStatusLabel(day, txs), isNull);
  });

  test('count record sand card splits rounds into morning/afternoon', () {
    final txs = [
      AppTransaction(
        id: 'sand1',
        date: day,
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: 'ร่อนทราย: 5 รอบ',
        amount: 0,
        drumsObtained: 5,
        workAssignments: {
          'lapTimes': [
            '19/05 08:10:00',
            '19/05 09:30:00',
            '19/05 11:55:00',
            '19/05 13:05:00',
            '19/05 15:40:00',
          ],
        },
      ),
    ];
    expect(
      countRecordMenuStatusLabel(day, txs),
      'ร่อน 5 รอบ (เช้า 3 · บ่าย 2)',
    );
    final periods = countRecordSandPeriodTotals(day, txs);
    expect(periods.morning, 3);
    expect(periods.afternoon, 2);
  });

  test('sand rounds split gives the remainder to the new machine', () {
    expect(splitSandRoundsNewFirst(6).newer, 3);
    expect(splitSandRoundsNewFirst(6).older, 3);
    expect(splitSandRoundsNewFirst(7).newer, 4);
    expect(splitSandRoundsNewFirst(7).older, 3);
    expect(splitSandRoundsNewFirst(0).newer, 0);
    expect(splitSandRoundsNewFirst(0).older, 0);
  });
}
