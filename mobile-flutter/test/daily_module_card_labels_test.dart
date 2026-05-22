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

  test('fuel card sums liters', () {
    final txs = [
      AppTransaction(
        id: 'f1',
        date: day,
        type: 'Expense',
        category: 'Fuel',
        description: 'น้ำมัน',
        amount: 500,
        quantity: 120.5,
      ),
      AppTransaction(
        id: 'f2',
        date: day,
        type: 'Expense',
        category: 'Fuel',
        description: 'น้ำมัน',
        amount: 300,
        quantity: 30,
      ),
    ];
    expect(
      dailyFuelModuleStatusLabel(day, txs),
      'ใช้น้ำมันรวม 150.5 ลิตร',
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
          ),
        ],
      ),
      'ใช้น้ำมันรวม 10 ลิตร',
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
}
