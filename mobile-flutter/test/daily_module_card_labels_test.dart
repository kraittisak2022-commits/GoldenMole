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

  test('macro vehicle card counts only rows with work details', () {
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
    expect(macroVehicleUsageCountForDay(day, txs), 1);
    expect(dailyMacroVehicleModuleStatusLabel(day, txs), 'ใช้แม็คโคร 1 คัน');
  });

  test('macro vehicle card counts unique vehicles when rows are duplicated', () {
    final txs = [
      AppTransaction(
        id: 'm1a',
        date: day,
        type: 'Expense',
        category: 'Vehicle',
        description: 'แม็คโคร',
        amount: 0,
        vehicleId: 'แม็คโคร 01',
        driverId: 'd1',
        workDetails: 'ขุดแร่',
      ),
      AppTransaction(
        id: 'm1b',
        date: day,
        type: 'Expense',
        category: 'Vehicle',
        description: 'แม็คโคร',
        amount: 0,
        vehicleId: 'แม็คโคร 01',
        driverId: 'd1',
        workDetails: 'ขุดแร่',
      ),
      AppTransaction(
        id: 'm2a',
        date: day,
        type: 'Expense',
        category: 'Vehicle',
        description: 'แม็คโคร',
        amount: 0,
        vehicleId: 'แม็คโคร 02',
        driverId: 'd2',
        workDetails: 'ขุดแร่',
      ),
      AppTransaction(
        id: 'm2b',
        date: day,
        type: 'Expense',
        category: 'Vehicle',
        description: 'แม็คโคร',
        amount: 0,
        vehicleId: 'แม็คโคร 02',
        driverId: 'd2',
        workDetails: 'ขุดแร่',
      ),
      AppTransaction(
        id: 'm3',
        date: day,
        type: 'Expense',
        category: 'Vehicle',
        description: 'แม็คโคร',
        amount: 0,
        vehicleId: 'แม็คโคร 03',
        driverId: 'd3',
        workDetails: 'ขุดแร่',
      ),
      // placeholder — มีคนขับไม่มีรายละเอียด ต้องไม่ถูกนับ
      AppTransaction(
        id: 'placeholder',
        date: day,
        type: 'Expense',
        category: 'Vehicle',
        description: 'แม็คโคร',
        amount: 0,
        vehicleId: 'แม็คโคร 04',
        driverId: 'd4',
      ),
    ];
    expect(macroVehicleUsageCountForDay(day, txs), 3);
    expect(dailyMacroVehicleModuleStatusLabel(day, txs), 'ใช้แม็คโคร 3 คัน');
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
        workDetails: 'ขุด',
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
        workDetails: 'ขุด',
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
        workDetails: 'ขุด',
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

  test('countRecordDayMark flags trips and sand with status label', () {
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
    final mark = countRecordDayMark(day, txs);
    expect(mark.hasTrips, isTrue);
    expect(mark.hasSand, isTrue);
    expect(mark.hasAny, isTrue);
    expect(mark.label, '1 คัน · 3 เที่ยว · ร่อน 2 รอบ');
  });

  test('countRecordDayMark empty day has no flags or label', () {
    final mark = countRecordDayMark(day, const []);
    expect(mark.hasTrips, isFalse);
    expect(mark.hasSand, isFalse);
    expect(mark.hasAny, isFalse);
    expect(mark.label, isNull);
  });

  test('countRecordDayMarksForMonth indexes only days with data', () {
    final txs = [
      AppTransaction(
        id: 't1',
        date: '2026-05-19',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'VehicleTrip',
        description: 'ดรัม: 1 เที่ยว',
        amount: 0,
        vehicleId: 'ดรัม-1',
        tripCount: 1,
        perCarTrips: 1,
      ),
      AppTransaction(
        id: 's1',
        date: '2026-05-20',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: 'ร่อนทราย: 5 รอบ',
        amount: 0,
        drumsObtained: 5,
      ),
      AppTransaction(
        id: 'other',
        date: '2026-06-01',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'VehicleTrip',
        description: 'ดรัม: 2 เที่ยว',
        amount: 0,
        vehicleId: 'ดรัม-2',
        tripCount: 2,
        perCarTrips: 2,
      ),
    ];
    final marks = countRecordDayMarksForMonth(
      year: 2026,
      month: 5,
      transactions: txs,
    );
    expect(marks.keys, containsAll(['2026-05-19', '2026-05-20']));
    expect(marks.containsKey('2026-06-01'), isFalse);
    expect(marks['2026-05-19']!.hasTrips, isTrue);
    expect(marks['2026-05-19']!.hasSand, isFalse);
    expect(marks['2026-05-20']!.hasSand, isTrue);
    expect(marks['2026-05-20']!.hasTrips, isFalse);
  });

  test('dailyRecordDayMark flags attendance and event with summary label', () {
    final txs = [
      AppTransaction(
        id: 'att1',
        date: day,
        type: 'Expense',
        category: 'Labor',
        description: 'เช็คชื่อ',
        amount: 0,
        employeeIds: const ['e1'],
      ),
      AppTransaction(
        id: 'ev1',
        date: day,
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Event',
        description: 'ฝนตก หยุดงาน',
        amount: 0,
        eventType: 'warning',
        eventPriority: 'normal',
      ),
    ];
    final mark = dailyRecordDayMark(day, txs);
    expect(mark.hasAttendance, isTrue);
    expect(mark.hasEvent, isTrue);
    expect(mark.hasTrips, isFalse);
    expect(mark.hasFuel, isFalse);
    expect(mark.hasDot, isTrue);
    expect(mark.hasAny, isTrue);
    expect(mark.label, 'เช็คชื่อ · เหตุการณ์');
  });

  test('dailyRecordDayMark empty day has no flags or label', () {
    final mark = dailyRecordDayMark(day, const []);
    expect(mark.hasAttendance, isFalse);
    expect(mark.hasTrips, isFalse);
    expect(mark.hasFuel, isFalse);
    expect(mark.hasEvent, isFalse);
    expect(mark.hasAny, isFalse);
    expect(mark.label, isNull);
  });

  test('dailyRecordDayMarksForMonth indexes only days with data', () {
    final txs = [
      AppTransaction(
        id: 'fuel1',
        date: '2026-05-19',
        type: 'Expense',
        category: 'Fuel',
        description: 'เติมน้ำมัน',
        amount: 0,
      ),
      AppTransaction(
        id: 'ev1',
        date: '2026-05-21',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Event',
        description: 'เครื่องจักรเสีย',
        amount: 0,
      ),
      AppTransaction(
        id: 'other',
        date: '2026-06-01',
        type: 'Expense',
        category: 'Fuel',
        description: 'เติม',
        amount: 0,
      ),
    ];
    final marks = dailyRecordDayMarksForMonth(
      year: 2026,
      month: 5,
      transactions: txs,
    );
    expect(marks.keys, containsAll(['2026-05-19', '2026-05-21']));
    expect(marks.containsKey('2026-06-01'), isFalse);
    expect(marks.containsKey('2026-05-20'), isFalse);
    expect(marks['2026-05-19']!.hasFuel, isTrue);
    expect(marks['2026-05-19']!.label, 'น้ำมัน');
    expect(marks['2026-05-21']!.hasEvent, isTrue);
    expect(marks['2026-05-21']!.label, 'เหตุการณ์');
  });

  test('count record card always shows trip and sand together', () {
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
      countRecordMenuStatusLabel(day, txs),
      '1 คัน · 3 เที่ยว · ร่อน 2 รอบ',
    );
    expect(
      resolveCountRecordMenuFillStatus(day, txs),
      DailyModuleFillStatus.complete,
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
