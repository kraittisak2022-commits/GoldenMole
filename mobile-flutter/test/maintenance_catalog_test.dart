import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/utils/daily_module_transactions.dart';
import 'package:mobile_flutter/utils/maintenance_catalog.dart';

void main() {
  group('maintenance_catalog', () {
    test('groups expose expected asset counts', () {
      expect(maintenanceAssetsFor(MaintenanceAssetGroup.macro), hasLength(5));
      expect(maintenanceAssetsFor(MaintenanceAssetGroup.car), hasLength(2));
      expect(maintenanceAssetsFor(MaintenanceAssetGroup.motorcycle), hasLength(5));
      expect(maintenanceAssetsFor(MaintenanceAssetGroup.generator), hasLength(3));
      expect(maintenanceAssetsFor(MaintenanceAssetGroup.sandSieve), hasLength(1));
    });

    test('maintenanceGroupForAsset resolves known names', () {
      expect(
        maintenanceGroupForAsset('รถแม็คโคร SK200-8 (น้องโกลเด้น)'),
        MaintenanceAssetGroup.macro,
      );
      expect(maintenanceGroupForAsset('ไมตี้'), MaintenanceAssetGroup.car);
      expect(
        maintenanceGroupForAsset('เครื่องร่อนทราย'),
        MaintenanceAssetGroup.sandSieve,
      );
    });

    test('description round-trip', () {
      final desc = maintenanceDescription(
        type: kMaintenanceTypeOil,
        detail: 'รอบที่ 5',
      );
      expect(desc, 'เปลี่ยนถ่ายน้ำมันเครื่อง: รอบที่ 5');
      expect(
        maintenanceDetailFromDescription(desc, kMaintenanceTypeOil),
        'รอบที่ 5',
      );
    });

    test('transactionMatchesDailyModule for บำรุงรักษา', () {
      final t = AppTransaction(
        id: 'm1',
        date: '2026-08-30',
        type: 'Expense',
        category: kMaintenanceTxCategory,
        subCategory: kMaintenanceTypeRepair,
        description: 'ซ่อม/ดูแลรักษา: เปลี่ยนไส้กรอง',
        amount: 1200,
        vehicleId: 'ไมตี้',
        workType: MaintenanceAssetGroup.car.code,
      );
      expect(
        transactionMatchesDailyModule(t, '2026-08-30', kMaintenanceModuleCategory),
        isTrue,
      );
      expect(
        transactionMatchesDailyModule(t, '2026-08-30', 'น้ำมัน'),
        isFalse,
      );
    });
  });
}
