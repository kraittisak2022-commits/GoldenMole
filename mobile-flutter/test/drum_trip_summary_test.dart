import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/models/employee.dart';
import 'package:mobile_flutter/utils/drum_trip_summary.dart';

void main() {
  group('resolveVehicleTripRowStatus', () {
    test('returns empty when no inputs and not editing', () {
      final status = resolveVehicleTripRowStatus(
        vehicleId: '',
        driverId: '',
        billingMode: 'PerTrip',
        morningTrips: 0,
        afternoonTrips: 0,
        cubicPerTrip: 0,
        lumpSumTotalCubic: 0,
        workType: 'FullDay',
        hourlyHours: 0,
        isEditingSaved: false,
      );
      expect(status, VehicleTripRowStatus.empty);
      expect(isVehicleTripStatusReady(status), isFalse);
    });

    test('returns incomplete when vehicle chosen but driver or trips missing', () {
      final status = resolveVehicleTripRowStatus(
        vehicleId: 'รถดรัม 1',
        driverId: '',
        billingMode: 'PerTrip',
        morningTrips: 4,
        afternoonTrips: 0,
        cubicPerTrip: 3,
        lumpSumTotalCubic: 0,
        workType: 'FullDay',
        hourlyHours: 0,
        isEditingSaved: false,
      );
      expect(status, VehicleTripRowStatus.incomplete);
    });

    test('returns ready for valid PerTrip entry', () {
      final status = resolveVehicleTripRowStatus(
        vehicleId: 'รถดรัม 1',
        driverId: 'emp_1',
        billingMode: 'PerTrip',
        morningTrips: 5,
        afternoonTrips: 3,
        cubicPerTrip: 3,
        lumpSumTotalCubic: 0,
        workType: 'FullDay',
        hourlyHours: 0,
        isEditingSaved: false,
      );
      expect(status, VehicleTripRowStatus.ready);
      expect(isVehicleTripStatusReady(status), isTrue);
    });

    test('returns editing for valid saved LumpSum entry', () {
      final status = resolveVehicleTripRowStatus(
        vehicleId: 'รถดรัม 2',
        driverId: 'emp_2',
        billingMode: 'LumpSum',
        morningTrips: 0,
        afternoonTrips: 0,
        cubicPerTrip: 0,
        lumpSumTotalCubic: 30,
        workType: 'FullDay',
        hourlyHours: 0,
        isEditingSaved: true,
      );
      expect(status, VehicleTripRowStatus.editing);
      expect(isVehicleTripStatusReady(status), isTrue);
    });

    test('requires hourly hours > 0 when workType is Hourly', () {
      final incomplete = resolveVehicleTripRowStatus(
        vehicleId: 'รถดรัม 1',
        driverId: 'emp_1',
        billingMode: 'PerTrip',
        morningTrips: 2,
        afternoonTrips: 0,
        cubicPerTrip: 3,
        lumpSumTotalCubic: 0,
        workType: 'Hourly',
        hourlyHours: 0,
        isEditingSaved: false,
      );
      expect(incomplete, VehicleTripRowStatus.incomplete);

      final ready = resolveVehicleTripRowStatus(
        vehicleId: 'รถดรัม 1',
        driverId: 'emp_1',
        billingMode: 'PerTrip',
        morningTrips: 2,
        afternoonTrips: 0,
        cubicPerTrip: 3,
        lumpSumTotalCubic: 0,
        workType: 'Hourly',
        hourlyHours: 4,
        isEditingSaved: false,
      );
      expect(ready, VehicleTripRowStatus.ready);
    });
  });

  group('numeric and phrase helpers', () {
    test('normalizes Thai digits and strips commas', () {
      expect(normalizeVehicleTripNumericInput('๑,๒๓๔.๕'), '1234.5');
      expect(parseVehicleTripNumber('๑๒.๕'), 12.5);
      expect(formatVehicleTripNumber(12.0), '12');
      expect(formatVehicleTripNumber(12.5), '12.5');
    });

    test('stepVehicleTripCount clamps at zero', () {
      expect(stepVehicleTripCount('', 1), '1');
      expect(stepVehicleTripCount('3', 1), '4');
      expect(stepVehicleTripCount('1', -1), '');
      expect(stepVehicleTripCount('', -1), '');
    });

    test('defaultCubicPerTripForDrumVehicle detects 10-wheeler vs drum', () {
      expect(defaultCubicPerTripForDrumVehicle('รถ 10 ล้อ 1'), 7);
      expect(defaultCubicPerTripForDrumVehicle('สิบล้อพี่เอ'), 7);
      expect(defaultCubicPerTripForDrumVehicle('รถดรัม 1'), 3);
    });

    test('toggleVehicleTripWorkPhrase adds and removes cleanly', () {
      var text = toggleVehicleTripWorkPhrase('', 'ขนทรายล้าง');
      expect(text, 'ขนทรายล้าง');
      expect(containsVehicleTripWorkPhrase(text, 'ขนทรายล้าง'), isTrue);

      text = toggleVehicleTripWorkPhrase(text, 'ขนทรายถม');
      expect(text, 'ขนทรายล้าง, ขนทรายถม');

      text = toggleVehicleTripWorkPhrase(text, 'ขนทรายล้าง');
      expect(text, 'ขนทรายถม');
      expect(containsVehicleTripWorkPhrase(text, 'ขนทรายล้าง'), isFalse);
    });

    test('buildVehicleTripSaveButtonLabel reflects ready count and edit mode', () {
      expect(
        buildVehicleTripSaveButtonLabel(readyCount: 0, hasEditingRow: false),
        'บันทึกรถดรัม',
      );
      expect(
        buildVehicleTripSaveButtonLabel(readyCount: 1, hasEditingRow: false),
        'บันทึกรถคันนี้ (1 คัน)',
      );
      expect(
        buildVehicleTripSaveButtonLabel(readyCount: 1, hasEditingRow: true),
        'อัปเดตข้อมูลรถคันนี้',
      );
      expect(
        buildVehicleTripSaveButtonLabel(readyCount: 3, hasEditingRow: false),
        'บันทึกทั้งหมด (3 คัน)',
      );
    });
  });

  group('VehicleTripDayOverview', () {
    test('aggregates saved vehicles, morning/afternoon trips, and cubic', () {
      final txs = [
        const AppTransaction(
          id: 'tx_1',
          date: '2026-06-15',
          type: 'Expense',
          category: 'DailyLog',
          subCategory: 'VehicleTrip',
          description: 'รถดรัม 1: 10 เที่ยว × 3 คิว',
          amount: 0,
          vehicleId: 'รถดรัม 1',
          driverId: 'emp_1',
          tripBillingMode: 'PerTrip',
          tripMorning: 6,
          tripAfternoon: 4,
          tripCount: 10,
          cubicPerTrip: 3,
          totalCubic: 30,
        ),
        const AppTransaction(
          id: 'tx_2',
          date: '2026-06-15',
          type: 'Expense',
          category: 'DailyLog',
          subCategory: 'VehicleTrip',
          description: 'รถดรัม 2: เหมา 25 คิว',
          amount: 0,
          vehicleId: 'รถดรัม 2',
          driverId: 'emp_2',
          tripBillingMode: 'LumpSum',
          tripMorning: 4,
          tripAfternoon: 3,
          tripCount: 7,
          totalCubic: 25,
        ),
      ];

      final overview = VehicleTripDayOverview.fromTransactions(
        txs,
        ymd: '2026-06-15',
        fleetTotal: 4,
      );

      expect(overview.savedVehicles, 2);
      expect(overview.fleetTotal, 4);
      expect(overview.completionRatio, 0.5);
      expect(overview.totalMorningTrips, 10);
      expect(overview.totalAfternoonTrips, 7);
      expect(overview.totalTrips, 17);
      expect(overview.totalCubic, 55);
      expect(overview.lumpSumVehicles, 1);
    });
  });

  group('filterDrumTripDrivers', () {
    test('keeps only active dump-truck drivers and excludes other roles', () {
      const employees = [
        Employee(
          id: 'e1',
          name: 'สมชาย',
          nickname: 'พี่ชาย',
          type: 'Daily',
          positions: ['คนขับรถ'],
        ),
        Employee(
          id: 'e2',
          name: 'สมศักดิ์',
          nickname: 'ลุงศักดิ์',
          type: 'Daily',
          position: 'คนขับรถดั๊ม',
        ),
        Employee(
          id: 'e3',
          name: 'สมปอง',
          nickname: 'ปอง',
          type: 'Daily',
          positions: ['คนขับรถแม็คโคร'],
        ),
        Employee(
          id: 'e4',
          name: 'สมหมาย',
          nickname: 'หมาย',
          type: 'Daily',
          positions: ['พนักงานท่าทราย'],
        ),
        Employee(
          id: 'e5',
          name: 'อดีตคนขับ',
          nickname: 'เก่า',
          type: 'Daily',
          positions: ['คนขับรถ'],
          inactive: true,
        ),
      ];

      final drivers = filterDrumTripDrivers(employees);
      expect(drivers.map((e) => e.id).toList(), ['e1', 'e2']);
    });
  });
}
