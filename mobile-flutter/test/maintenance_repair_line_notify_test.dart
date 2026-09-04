import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/models/employee.dart';
import 'package:mobile_flutter/utils/advance_line_notify.dart';
import 'package:mobile_flutter/utils/maintenance_catalog.dart';

void main() {
  test('buildMaintenanceRepairLineText includes asset and urgency', () {
    final tx = AppTransaction(
      id: 'r1',
      date: '2026-08-30',
      type: 'Expense',
      category: kMaintenanceTxCategory,
      subCategory: kMaintenanceTypeRepairRequest,
      description: 'แจ้งซ่อม: สตาร์ทไม่ติด',
      amount: 0,
      vehicleId: 'ไมตี้',
      vehicleName: 'ไมตี้',
      workType: MaintenanceAssetGroup.car.code,
      eventPriority: 'urgent',
    );
    final text = buildMaintenanceRepairLineText(tx);
    expect(text, contains('แจ้งซ่อม'));
    expect(text, contains('ไมตี้'));
    expect(text, contains('ด่วน'));
    expect(text, contains('สตาร์ทไม่ติด'));
  });

  test('buildMaintenanceServiceLogLineText includes type and amount', () {
    final tx = AppTransaction(
      id: 'm1',
      date: '2026-09-04',
      type: 'Expense',
      category: kMaintenanceTxCategory,
      subCategory: kMaintenanceTypeOil,
      description: 'เปลี่ยนถ่ายน้ำมันเครื่อง: ครบระยะ',
      amount: 2500,
      vehicleId: 'แม็คโคร 1',
      vehicleName: 'แม็คโคร 1',
      workType: MaintenanceAssetGroup.macro.code,
    );
    final text = buildMaintenanceServiceLogLineText(tx);
    expect(text, contains('บันทึกบำรุงรักษา'));
    expect(text, contains('แม็คโคร 1'));
    expect(text, contains(kMaintenanceTypeOil));
    expect(text, contains('2,500'));
  });

  test('buildAttendanceLineText includes present and leave names', () {
    final employees = [
      const Employee(id: 'e1', name: 'สมชาย', nickname: 'ชาย', type: 'Daily'),
      const Employee(id: 'e2', name: 'สมหญิง', nickname: 'หญิง', type: 'Daily'),
    ];
    final text = buildAttendanceLineText(
      const AttendanceLineNotifyPayload(
        dateYmd: '2026-09-04',
        sectionTitle: 'พนักงานท่าทราย',
        presentIds: ['e1'],
        leaveIds: ['e2'],
      ),
      employees,
    );
    expect(text, contains('เช็คชื่อ · พนักงานท่าทราย'));
    expect(text, contains('ชาย'));
    expect(text, contains('หญิง'));
  });

  test('buildVehicleTripLineText includes vehicle and trips', () {
    final text = buildVehicleTripLineText(
      dateYmd: '2026-09-04',
      items: const [
        VehicleTripLineItem(
          vehicle: 'ดรัม 1',
          driverName: 'เอ',
          billingLabel: 'คิดเป็นเที่ยว',
          detailLine: 'เช้า 2 / บ่าย 3 · รวม 5 เที่ยว',
        ),
      ],
    );
    expect(text, contains('บันทึกรถดรัม / จำนวนเที่ยว'));
    expect(text, contains('ดรัม 1'));
    expect(text, contains('เอ'));
    expect(text, contains('5 เที่ยว'));
  });
}
