import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/models/employee.dart';
import 'package:mobile_flutter/utils/advance_line_notify.dart';
import 'package:mobile_flutter/utils/maintenance_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

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

  test('buildCombinedAttendanceLineText matches team report format', () {
    final employees = [
      const Employee(id: 'd1', name: 'ศักดิ์', nickname: 'ลุงศักดิ์', type: 'Daily'),
      const Employee(id: 's1', name: 'โจว์', nickname: 'โจว์', type: 'Daily'),
    ];
    final text = buildCombinedAttendanceLineText(
      dateYmd: '2026-09-04',
      sectionTitle: 'คนขับรถ และ พนักงานท่าทราย',
      presentIds: const ['d1', 's1'],
      leaveIds: const [],
      employees: employees,
    );
    expect(text, contains('━━━━ GoldenMole ━━━━'));
    expect(text, contains('วันที่ : 4 ก.ย. 2569 (2026-09-04)'));
    expect(text, contains('เช็คชื่อ · คนขับรถ และ พนักงานท่าทราย'));
    expect(text, contains('มาทำงาน :2 คน'));
    expect(text, contains('ลุงศักดิ์, โจว์'));
    expect(text, contains('ลางาน : 0 คน'));
    expect(text, contains('รายชื่อลางาน : —'));
  });

  test('attendance waits for driver then sends when both ready', () async {
    await dotenv.load(fileName: '.env');
    final employees = [
      const Employee(id: 's1', name: 'โจว์', nickname: 'โจว์', type: 'Daily'),
      const Employee(id: 'd1', name: 'นุ', nickname: 'พี่นุ', type: 'Daily'),
    ];
    final t0 = DateTime(2026, 9, 4, 8, 0);
    final sand = await upsertAttendanceLineAndMaybeNotify(
      const AttendanceLineSectionUpdate(
        dateYmd: '2026-09-04',
        section: AttendanceLineSection.sandYard,
        presentIds: ['s1'],
        leaveIds: [],
      ),
      employees,
      now: t0,
    );
    expect(sand.skipped, isTrue);
    expect(sand.messageTh, contains('รอข้อมูลคนขับรถ'));

    // เมื่อครบทั้งสองฝั่งจะพยายามส่ง — ในเทสต์อาจ sent หรือ failed ตาม env
    final both = await upsertAttendanceLineAndMaybeNotify(
      const AttendanceLineSectionUpdate(
        dateYmd: '2026-09-04',
        section: AttendanceLineSection.driver,
        presentIds: ['d1'],
        leaveIds: [],
      ),
      employees,
      now: t0.add(const Duration(minutes: 10)),
    );
    expect(both.messageTh ?? '', isNot(contains('รอข้อมูลคนขับรถ')));
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

  test('buildDailyVehicleUsageLineText matches 09:00 digest format', () {
    final text = buildDailyVehicleUsageLineText(
      dateYmd: '2026-09-04',
      drums: const [
        (vehicle: 'รถดั๊มลุงศักดิ์', driverName: 'พี่เดี่ยว'),
        (vehicle: 'รถดั๊มโอเว่น', driverName: 'ไม้'),
      ],
      macros: const [
        MacroVehicleUsageLineItem(
          vehicle: 'รถแม็คโคร SK200-10',
          driverName: 'ลุงศักดิ์',
          workToday: 'ขุดแร่, เปิดหน้าดิน',
        ),
      ],
    );
    expect(text, contains('การใช้รถ 4 ก.ย. 2569'));
    expect(text, contains('บันทึกรถดรัม จำนวน 2 คัน'));
    expect(text, contains('คันที่ 1 : รถดั๊มลุงศักดิ์ · พี่เดี่ยว'));
    expect(text, contains('รถแม็คโคร จำนวน 1 คัน'));
    expect(
      text,
      contains('คันที่ 1 : รถแม็คโคร SK200-10 · ลุงศักดิ์ · ขุดแร่, เปิดหน้าดิน'),
    );
  });

  test('buildDailyFuelStockLineText shows main and reserve tanks', () {
    final text = buildDailyFuelStockLineText(
      dateYmd: '2026-09-04',
      mainDieselLiters: 5432,
      reserveDieselLiters: 320.5,
    );
    expect(text, contains('น้ำมันคงเหลือ 4 ก.ย. 2569'));
    expect(text, contains('ถังหลัก : 5,432 ลิตร'));
    expect(text, contains('ถังสำรอง : 320.5 ลิตร'));
    expect(text, contains('รวม : 5,752.5 ลิตร'));
  });
}
