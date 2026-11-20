import '../models/app_transaction.dart';
import '../models/employee.dart';
import 'advance_employee_filter.dart';
import 'daily_module_transactions.dart';

/// ตำแหน่งที่ถือเป็นคนขับรถดั๊ม (ตรงกับระบบหลังบ้านและแผงนับเที่ยว)
const Set<String> kDrumTripDriverPositionTitles = <String>{
  'คนขับรถ',
  'คนขับรถดั๊ม',
  'คนขับรถดรัม',
  'คนขับดั๊ม',
  'คนขับดรัม',
  'พนักงานขับรถ',
};

/// ตรวจว่าพนักงานเป็นคนขับรถดั๊มหรือไม่ (ไม่รวมคนขับรถแม็คโคร/พนักงานท่าทราย)
bool isDrumTripDriverEmployee(Employee e) {
  final tokens = collectEmployeePositionTokens(e);
  for (final raw in tokens) {
    final compact = normalizePositionTitle(raw).replaceAll(' ', '');
    if (kDrumTripDriverPositionTitles.contains(compact)) {
      return true;
    }
  }
  return false;
}

/// คัดกรองเฉพาะพนักงานที่ยังทำงานอยู่และมีตำแหน่งคนขับรถดั๊มเท่านั้น
List<Employee> filterDrumTripDrivers(Iterable<Employee> employees) {
  return employees
      .where((e) => !e.inactive)
      .where(isDrumTripDriverEmployee)
      .toList();
}

/// สถานะความพร้อมของแถวกรอกรถดรัมและจำนวนเที่ยว
enum VehicleTripRowStatus {
  /// ยังไม่ได้เริ่มกรอก
  empty,

  /// ยังขาดข้อมูลบังคับ (รถ / คนขับ / เที่ยวหรือคิว / ชั่วโมงรายชั่วโมง)
  incomplete,

  /// ข้อมูลครบ พร้อมบันทึก (รายการใหม่)
  ready,

  /// กำลังแก้ไขรายการที่บันทึกไว้แล้ววันนี้
  editing,
}

/// กำหนดสถานะแถวจากค่าที่กรอกปัจจุบัน
VehicleTripRowStatus resolveVehicleTripRowStatus({
  required String vehicleId,
  required String driverId,
  required String billingMode,
  required double morningTrips,
  required double afternoonTrips,
  required double cubicPerTrip,
  required double lumpSumTotalCubic,
  required String workType,
  required double hourlyHours,
  required bool isEditingSaved,
}) {
  final hasVehicle = vehicleId.trim().isNotEmpty;
  final hasDriver = driverId.trim().isNotEmpty;
  final totalTrips = morningTrips + afternoonTrips;
  final isLumpSum = billingMode == 'LumpSum';
  final isHourly = workType == 'Hourly';

  final hasAnyInput = hasVehicle ||
      hasDriver ||
      totalTrips > 0 ||
      (isLumpSum && lumpSumTotalCubic > 0) ||
      (isHourly && hourlyHours > 0);

  if (!hasAnyInput && !isEditingSaved) {
    return VehicleTripRowStatus.empty;
  }

  final tripsValid = isLumpSum
      ? lumpSumTotalCubic > 0
      : (totalTrips > 0 && cubicPerTrip > 0);
  final hoursValid = !isHourly || hourlyHours > 0;

  if (!hasVehicle || !hasDriver || !tripsValid || !hoursValid) {
    return VehicleTripRowStatus.incomplete;
  }

  return isEditingSaved
      ? VehicleTripRowStatus.editing
      : VehicleTripRowStatus.ready;
}

/// ตรวจว่าสถานะพร้อมสำหรับบันทึกแล้วหรือไม่
bool isVehicleTripStatusReady(VehicleTripRowStatus status) =>
    status == VehicleTripRowStatus.ready ||
    status == VehicleTripRowStatus.editing;

/// แปลงเลขไทย + ตัดช่องว่าง/ลูกน้ำ ออกจากข้อความตัวเลข
String normalizeVehicleTripNumericInput(String raw) {
  const thaiDigits = <String, String>{
    '๐': '0',
    '๑': '1',
    '๒': '2',
    '๓': '3',
    '๔': '4',
    '๕': '5',
    '๖': '6',
    '๗': '7',
    '๘': '8',
    '๙': '9',
  };
  final buf = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (ch == ',' || ch == ' ' || ch == '\u00A0') continue;
    buf.write(thaiDigits[ch] ?? ch);
  }
  return buf.toString().trim();
}

/// แปลงข้อความตัวเลขเป็น double อย่างปลอดภัย (คืน 0 หากว่างหรือแปลงไม่ได้)
double parseVehicleTripNumber(String raw) {
  final normalized = normalizeVehicleTripNumericInput(raw);
  if (normalized.isEmpty) return 0;
  final value = double.tryParse(normalized);
  if (value == null || !value.isFinite || value < 0) return 0;
  return value;
}

/// ฟอร์แมตตัวเลขเที่ยว/คิวให้สะอาด (ตัด .0 ทิ้ง)
String formatVehicleTripNumber(double value) {
  if (!value.isFinite) return '0';
  final rounded = (value * 100).roundToDouble() / 100;
  if ((rounded - rounded.round()).abs() < 1e-9) {
    return '${rounded.round()}';
  }
  return rounded.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// ปรับยอดเที่ยวด้วยปุ่ม + / − โดยไม่ติดลบ
String stepVehicleTripCount(String currentRaw, double delta) {
  final current = parseVehicleTripNumber(currentRaw);
  final next = (current + delta).clamp(0, 9999).toDouble();
  if (next <= 0) return '';
  return formatVehicleTripNumber(next);
}

/// ค่าคิวต่อเที่ยวเริ่มต้นตามประเภทรถ (10 ล้อ = 7 คิว, รถดรัม = 3 คิว)
double defaultCubicPerTripForDrumVehicle(String vehicleName) {
  final lower = vehicleName.trim().toLowerCase();
  if (lower.contains('10') || lower.contains('สิบล้อ') || lower.contains('10ล้อ')) {
    return 7;
  }
  return 3;
}

/// ตรวจว่ามีวลีงานด่วนอยู่ในรายละเอียดงานแล้วหรือไม่
bool containsVehicleTripWorkPhrase(String details, String phrase) {
  final target = phrase.trim();
  if (target.isEmpty) return false;
  final parts = details
      .split(RegExp(r'[,/\n·•]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty);
  return parts.any((p) => p == target);
}

/// สลับเพิ่ม/ลบวลีงานด่วนในช่องรายละเอียดงานอย่างเป็นระเบียบ
String toggleVehicleTripWorkPhrase(String currentDetails, String phrase) {
  final target = phrase.trim();
  if (target.isEmpty) return currentDetails.trim();
  final parts = currentDetails
      .split(RegExp(r'[,/\n·•]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (parts.contains(target)) {
    parts.removeWhere((p) => p == target);
  } else {
    parts.add(target);
  }
  return parts.join(', ');
}

/// ป้ายปุ่มบันทึกด้านล่างตามจำนวนคันที่พร้อมบันทึก
String buildVehicleTripSaveButtonLabel({
  required int readyCount,
  required bool hasEditingRow,
}) {
  if (readyCount <= 0) {
    return hasEditingRow ? 'อัปเดตข้อมูลรถ' : 'บันทึกรถดรัม';
  }
  if (readyCount == 1) {
    return hasEditingRow ? 'อัปเดตข้อมูลรถคันนี้' : 'บันทึกรถคันนี้ (1 คัน)';
  }
  return 'บันทึกทั้งหมด ($readyCount คัน)';
}

/// สรุปภาพรวมการวิ่งรถดรัมของทั้งวันสำหรับ KPI Header
class VehicleTripDayOverview {
  const VehicleTripDayOverview({
    required this.savedVehicles,
    required this.fleetTotal,
    required this.totalMorningTrips,
    required this.totalAfternoonTrips,
    required this.totalTrips,
    required this.totalCubic,
    required this.lumpSumVehicles,
    required this.countRecordSyncedVehicles,
  });

  final int savedVehicles;
  final int fleetTotal;
  final double totalMorningTrips;
  final double totalAfternoonTrips;
  final double totalTrips;
  final double totalCubic;
  final int lumpSumVehicles;
  final int countRecordSyncedVehicles;

  double get completionRatio {
    if (fleetTotal <= 0) return savedVehicles > 0 ? 1.0 : 0.0;
    return (savedVehicles / fleetTotal).clamp(0.0, 1.0);
  }

  factory VehicleTripDayOverview.fromTransactions(
    Iterable<AppTransaction> dayTransactions, {
    required String ymd,
    required int fleetTotal,
  }) {
    final latest = latestVehicleTripsByVehicle(dayTransactions, ymd: ymd)
        .where(transactionMatchesVehicleTripModuleList)
        .toList();

    var morning = 0.0;
    var afternoon = 0.0;
    var trips = 0.0;
    var cubic = 0.0;
    var lumpSum = 0;
    var syncedCount = 0;

    for (final t in latest) {
      final split = vehicleTripPeriodSplit(t);
      final rowTotalTrips = (split.morning + split.afternoon) > 0
          ? (split.morning + split.afternoon)
          : (t.tripCount ?? t.perCarTrips ?? 0);
      morning += split.morning;
      afternoon += split.afternoon;
      trips += rowTotalTrips;

      final isLump = (t.tripBillingMode ?? '').trim() == 'LumpSum';
      if (isLump) lumpSum++;
      if (isCountRecordVehicleTrip(t)) syncedCount++;

      final rowCubic = t.totalCubic ??
          t.perCarCubic ??
          (rowTotalTrips * (t.cubicPerTrip ?? 0));
      cubic += rowCubic;
    }

    return VehicleTripDayOverview(
      savedVehicles: latest.length,
      fleetTotal: fleetTotal,
      totalMorningTrips: morning,
      totalAfternoonTrips: afternoon,
      totalTrips: trips,
      totalCubic: cubic,
      lumpSumVehicles: lumpSum,
      countRecordSyncedVehicles: syncedCount,
    );
  }
}
