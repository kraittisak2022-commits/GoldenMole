import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
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
}
