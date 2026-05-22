import '../models/app_transaction.dart';
import '../models/employee.dart';

/// รถแม็คโคร (เมนูแยกจากรถดรัม/เที่ยว) — สอดคล้องกับชื่อรถในการตั้งค่า
bool isMacroVehicleId(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return false;
  return s.contains('แม็คโคร') ||
      s.contains('แมคโคร') ||
      s.contains('excavator') ||
      s.contains('backhoe');
}

bool isMacroVehicleTransaction(AppTransaction t) =>
    t.category == 'Vehicle' && isMacroVehicleId(t.vehicleId);

/// รถหกล้อ / สิบล้อ
bool isSixOrTenWheelVehicleName(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return false;
  final compact = s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (compact.contains('หกล้อ') || compact.contains('6ล้อ')) return true;
  if (RegExp(r'6\s*ล้อ', caseSensitive: false).hasMatch(s)) return true;
  if (compact.contains('สิบล้อ') || compact.contains('10ล้อ')) return true;
  if (RegExp(r'10\s*ล้อ', caseSensitive: false).hasMatch(s)) return true;
  return false;
}

/// รถดั๊ม / ดรัม
bool isDumpTruckVehicleName(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return false;
  final compact = s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (compact.contains('ดั๊ม') ||
      compact.contains('ดั้ม') ||
      compact.contains('ดรัม')) {
    return true;
  }
  if (compact.contains('dump')) return true;
  return false;
}

/// รถในเมนูบันทึกรถดรัมและจำนวนเที่ยว — ดรัม + หกล้อ/สิบล้อ (ไม่รวมแม็คโคร)
bool isVehicleTripDrumCarName(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return false;
  if (isMacroVehicleId(s)) return false;
  return isDumpTruckVehicleName(s) || isSixOrTenWheelVehicleName(s);
}

/// ธุรกรรม «ลา» ที่ใช้ภาพรวมแคลน / ปฏิทิน — ต้องมีรายชื่อพนักงาน
bool isLaborLeaveRecord(AppTransaction t) {
  final cat = t.category.trim();
  if (cat == 'Leave' || t.type.toLowerCase() == 'leave') {
    return t.employeeIds.isNotEmpty;
  }
  final ls = (t.laborStatus ?? '').toLowerCase();
  return t.category == 'Labor' &&
      (ls == 'leave' || ls == 'sick' || ls == 'personal') &&
      t.employeeIds.isNotEmpty;
}

DateTime? _parseTxnDateYmdUtc(String ymd) {
  final parts = ymd.trim().split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime.utc(y, m, d);
}

int leaveInclusiveDayCount(AppTransaction t) {
  final raw = t.leaveDays;
  final n = (raw == null || raw <= 0) ? 1.0 : raw;
  return n.ceil();
}

/// วันที่ [dayKey] (YYYY-MM-DD) อยู่ในช่วงลาที่เริ่มจาก [t.date] ตาม [t.leave_days]
bool laborLeaveCoversCalendarDay(AppTransaction t, String dayKey) {
  if (!isLaborLeaveRecord(t)) return false;
  final start = _parseTxnDateYmdUtc(t.date);
  final needle = _parseTxnDateYmdUtc(dayKey.trim());
  if (start == null || needle == null) return false;
  final span = leaveInclusiveDayCount(t);
  final end = start.add(Duration(days: span - 1));
  return !needle.isBefore(start) && !needle.isAfter(end);
}

/// รายละเอียดการลาสำหรับปฏิทิน (ชื่อ + เหตุผล)
class CalendarLeaveDetail {
  const CalendarLeaveDetail({
    required this.headline,
    required this.reason,
    this.spanNote,
  });

  final String headline;
  final String reason;
  final String? spanNote;
}

String calendarEmployeeDisplayName(String id, List<Employee> employees) {
  for (final e in employees) {
    if (e.id == id) {
      if (e.nickname.trim().isNotEmpty) return e.nickname.trim();
      if (e.name.trim().isNotEmpty) return e.name.trim();
      break;
    }
  }
  return id.trim().isEmpty ? 'ไม่ทราบชื่อ' : id;
}

String leaveKindLabelTh(AppTransaction t) {
  final sub = (t.subCategory ?? '').trim().toLowerCase();
  final ls = (t.laborStatus ?? '').trim().toLowerCase();
  if (sub == 'sick' || ls == 'sick') return 'ลาป่วย';
  if (sub == 'personal' || ls == 'personal') return 'ลากิจ';
  if (t.category.trim() == 'Leave') {
    if (sub == 'sick') return 'ลาป่วย';
    if (sub == 'personal' || sub == 'leave') return 'ลากิจ';
  }
  return 'ลางาน';
}

String resolvedLeaveReason(AppTransaction t) {
  final direct = (t.leaveReason ?? '').trim();
  if (direct.isNotEmpty) return direct;

  final desc = t.description.trim();
  final colon = RegExp(r'ลา(?:กิจ|ป่วย|งาน)?\s*:\s*(.+)', caseSensitive: false);
  final m1 = colon.firstMatch(desc);
  if (m1 != null) {
    var tail = m1.group(1)?.trim() ?? '';
    tail = tail.replaceFirst(RegExp(r'\s*\(ครึ่งวัน[^)]*\)\s*$'), '').trim();
    if (tail.isNotEmpty) return tail;
  }

  final note = (t.note ?? '').trim();
  if (note.isNotEmpty && !note.contains('signedBy')) return note;

  if (desc.isNotEmpty && desc != 'ลางาน') return desc;
  return '';
}

String leaveDurationLabelTh(AppTransaction t) {
  final days = t.leaveDays;
  if (days == null || days <= 0) return '';
  final wd = (t.workDetails ?? '').trim().toLowerCase();
  if ((days - 0.5).abs() < 1e-6) {
    if (wd.contains('morning')) return 'ครึ่งวัน (เช้า)';
    if (wd.contains('afternoon')) return 'ครึ่งวัน (บ่าย)';
    return 'ครึ่งวัน';
  }
  if (days == days.roundToDouble()) return '${days.round()} วัน';
  return '$days วัน';
}

String _formatYmdThaiBe(String ymd) {
  final parts = ymd.trim().split('-');
  if (parts.length != 3) return ymd;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return ymd;
  return '${d.toString().padLeft(2, '0')}/${m.toString().padLeft(2, '0')}/${y + 543}';
}

/// รายการลาพร้อมเหตุผล — ใช้ใน bottom sheet เมื่อเลือกวันที่
List<CalendarLeaveDetail> calendarLeaveDetails(
  List<AppTransaction> leaveRows,
  List<Employee> employees, {
  String? viewingDayKey,
}) {
  final sorted = List<AppTransaction>.from(leaveRows)
    ..sort((a, b) {
      final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });

  final out = <CalendarLeaveDetail>[];
  for (final t in sorted) {
    final names = t.employeeIds
        .map((id) => calendarEmployeeDisplayName(id, employees))
        .where((s) => s.isNotEmpty && s != 'ไม่ทราบชื่อ')
        .toList();
    if (names.isEmpty && t.employeeIds.isEmpty) continue;
    final displayNames = names.isEmpty ? 'ไม่ทราบชื่อ' : names.join(', ');

    final kind = leaveKindLabelTh(t);
    final duration = leaveDurationLabelTh(t);
    final headline = duration.isEmpty
        ? '$displayNames — $kind'
        : '$displayNames — $kind ($duration)';

    String? spanNote;
    final viewKey = viewingDayKey?.trim();
    final startKey = t.date.trim();
    if (viewKey != null &&
        viewKey.isNotEmpty &&
        startKey.isNotEmpty &&
        viewKey != startKey) {
      spanNote = 'เริ่มลาวันที่ ${_formatYmdThaiBe(startKey)}';
    }

    out.add(
      CalendarLeaveDetail(
        headline: headline,
        reason: resolvedLeaveReason(t),
        spanNote: spanNote,
      ),
    );
  }
  return out;
}

/// ชื่อผู้ลาที่ไม่ซ้ำ (แสดงบนเซลล์ปฏิทิน)
List<String> calendarLeaveNames(
  List<AppTransaction> leaveRows,
  List<Employee> employees,
) {
  final ids = <String>{};
  for (final row in leaveRows) {
    ids.addAll(row.employeeIds);
  }
  return ids.map((id) => calendarEmployeeDisplayName(id, employees)).toList();
}

/// ชื่อผู้ลาไม่ซ้ำในวันปฏิทิน [dayKey]
List<String> dailyLeaveEmployeeNamesOnDay(
  String dayKey,
  Iterable<AppTransaction> transactions,
  List<Employee> employees,
) {
  final rows = transactions
      .where((t) => laborLeaveCoversCalendarDay(t, dayKey))
      .toList();
  return calendarLeaveNames(rows, employees);
}

/// ข้อความสถานะการ์ดเมนู «ลางาน» บนหน้าบันทึกประจำวัน
String dailyLeaveModuleStatusLabel(
  String dayKey,
  Iterable<AppTransaction> transactions,
  List<Employee> employees, {
  int maxNames = 2,
}) {
  final names = dailyLeaveEmployeeNamesOnDay(dayKey, transactions, employees);
  final n = names.length;
  if (n == 0) return 'ยังไม่มีรายการลา';
  final head = 'ลา $n คน';
  if (n <= maxNames) return '$head · ${names.join(', ')}';
  return '$head · ${names.take(maxNames).join(', ')} +${n - maxNames}';
}

/// แถวบันทึก «ตัดรอบล้างทรายที่บ้าน» (ไม่นับเป็นจำนวนถังที่ล้าง)
bool isHomeSandRoundCloseRow(AppTransaction t) =>
    t.description.contains('ตัดรอบล้างทรายที่บ้าน');

/// แถวบันทึกจำนวนถังล้างที่บ้าน (Quick Input / Wizard)
bool isDedicatedHomeSandWashRow(AppTransaction t) =>
    t.description.contains('ทรายที่ล้างที่บ้าน') &&
    !isHomeSandRoundCloseRow(t);

/// ถังล้างที่บ้านต่อวัน — สอดคล้องกับ `persistedSandHomeDrums` บนเว็บ
double persistedSandHomeDrumsForDay(List<AppTransaction> sandTxs) {
  if (sandTxs.isEmpty) return 0;
  double homeVal(AppTransaction t) =>
      (t.drumsWashedAtHome ?? 0).toDouble().clamp(0, 9999999);
  bool isMachine(AppTransaction t) {
    final m = (t.sandMachineType ?? '').trim();
    return m == 'Old' || m == 'New';
  }

  final dedicatedHome = sandTxs.where(isDedicatedHomeSandWashRow).toList();
  if (dedicatedHome.isNotEmpty) {
    var maxH = 0.0;
    for (final t in dedicatedHome) {
      final h = homeVal(t);
      if (h > maxH) maxH = h;
    }
    return maxH;
  }

  final withMachine = sandTxs.where(isMachine).toList();
  if (withMachine.isNotEmpty) {
    var maxH = 0.0;
    for (final t in withMachine) {
      final h = homeVal(t);
      if (h > maxH) maxH = h;
    }
    return maxH;
  }
  final drumsOnly = sandTxs.where((t) {
    if (isMachine(t)) return false;
    final sm = (t.sandMorning ?? 0) + (t.sandAfternoon ?? 0);
    return sm == 0;
  }).toList();
  if (drumsOnly.isNotEmpty) {
    var maxH = 0.0;
    for (final t in drumsOnly) {
      final h = homeVal(t);
      if (h > maxH) maxH = h;
    }
    return maxH;
  }
  var maxH = 0.0;
  for (final t in sandTxs) {
    final h = homeVal(t);
    if (h > maxH) maxH = h;
  }
  return maxH;
}

/// ข้อความสั้นสำหรับปฏิทินเมื่อวันนั้นมีบันทึกล้างทรายที่บ้าน / ตัดรอบ
List<String> calendarHomeSandLines(List<AppTransaction> dayTransactions) {
  final sandTx = dayTransactions
      .where(
        (t) =>
            t.category == 'DailyLog' &&
            (t.subCategory ?? '').trim() == 'Sand',
      )
      .toList();
  if (sandTx.isEmpty) return const [];
  final lines = <String>[];
  final hasDedicated = sandTx.any(isDedicatedHomeSandWashRow);
  final home = persistedSandHomeDrumsForDay(sandTx);
  if (hasDedicated || home > 0) {
    final n = home == home.roundToDouble()
        ? '${home.round()}'
        : home.toStringAsFixed(1);
    lines.add('ล้างทรายที่บ้าน $n ถัง');
  }
  if (sandTx.any(isHomeSandRoundCloseRow)) {
    lines.add('ตัดรอบล้างทรายที่บ้าน');
  }
  return lines;
}

bool transactionAppliesToDashboardDay(
  AppTransaction t,
  String dayKey,
  String moduleCategory,
) {
  if (moduleCategory == 'ลางาน') {
    return laborLeaveCoversCalendarDay(t, dayKey);
  }
  return t.date.trim() == dayKey.trim();
}

/// สาธารณูปโภค (เว็บเมนูสาธารณูปโภค)
bool transactionIsUtilitiesExpense(AppTransaction t) {
  return t.category == 'Utilities' &&
      t.type.trim().toLowerCase() == 'expense';
}

/// รายรับประจำวัน (เว็บ Daily Wizard → รายรับ → บันทึกรายรับประจำวัน)
bool transactionIsWizardDailyIncome(AppTransaction t) {
  return t.category == 'Income' && t.type.trim().toLowerCase() == 'income';
}

DailyModuleFillStatus resolveIncomeUtilitiesFillStatus(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  var hasUtilities = false;
  var hasIncome = false;
  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    if (transactionIsUtilitiesExpense(t)) hasUtilities = true;
    if (transactionIsWizardDailyIncome(t)) hasIncome = true;
  }
  if (hasUtilities && hasIncome) return DailyModuleFillStatus.complete;
  if (hasUtilities || hasIncome) return DailyModuleFillStatus.incomplete;
  return DailyModuleFillStatus.pending;
}

/// สถานะการกรอกเมนูบันทึกประจำวันบนแดชบอร์ด
enum DailyModuleFillStatus {
  /// ยังไม่มีข้อมูลที่เกี่ยวข้อง
  pending,

  /// มีแถว/ข้อมูลบางส่วนแต่ยังไม่ถือว่าครบตามเกณฑ์เมนู
  incomplete,

  /// ครบตามเกณฑ์ (เดิมคือ «บันทึกแล้ว»)
  complete,
}

/// สรุปสถานะเมนูจากรายการธุรกรรมของวันนั้น
DailyModuleFillStatus resolveDailyModuleFillStatus(
  String dayKey,
  String moduleCategory,
  Iterable<AppTransaction> transactions,
) {
  if (moduleCategory == 'รายจ่ายรายรับ') {
    return resolveIncomeUtilitiesFillStatus(dayKey, transactions);
  }
  var complete = false;
  var touch = false;
  for (final t in transactions) {
    if (!transactionAppliesToDashboardDay(t, dayKey, moduleCategory)) continue;
    if (transactionMatchesDailyModule(t, dayKey, moduleCategory)) {
      complete = true;
      break;
    }
    if (transactionTouchesDailyModule(t, dayKey, moduleCategory)) {
      touch = true;
    }
  }
  if (complete) return DailyModuleFillStatus.complete;
  if (touch) {
    // เมนู OT (ล่วงเวลา) ไม่ต้องผ่านสถานะ «กรอกไม่ครบ» — แสดงครบเหมือนเช็คถูก
    final isOtMenu =
        moduleCategory == 'OT' || moduleCategory.contains('ล่วงเวลา');
    if (isOtMenu) return DailyModuleFillStatus.complete;
    return DailyModuleFillStatus.incomplete;
  }
  return DailyModuleFillStatus.pending;
}

/// มีข้อมูลที่ «เกี่ยวข้องกับเมนู» แบบผ่อน (ยังไม่ถือว่าครบ)
bool transactionTouchesDailyModule(
  AppTransaction t,
  String dayKey,
  String moduleCategory,
) {
  if (!transactionAppliesToDashboardDay(t, dayKey, moduleCategory)) {
    return false;
  }

  bool sandWashTouches() {
    if (t.description.contains('ทรายที่ล้างที่บ้าน')) return false;
    if ((t.subCategory ?? '').toLowerCase() == 'sand') return true;
    if (t.category.contains('ร่อนทราย')) return true;
    if ((t.sandMorning ?? 0) > 0 || (t.sandAfternoon ?? 0) > 0) return true;
    if ((t.drumsObtained ?? 0) > 0) return true;
    return false;
  }

  bool homeSandTouches() {
    if ((t.drumsWashedAtHome ?? 0) > 0) return true;
    if (t.description.contains('ทรายที่ล้างที่บ้าน')) return true;
    return false;
  }

  /// มีสัญญาณรถ/เที่ยว แต่อาจยังไม่ผ่านเกณฑ์ [transactionCountsAsVehicleTripMenu]
  bool vehicleTouches() {
    if (transactionCountsAsVehicleTripMenu(t)) return true;
    if (t.category == 'Vehicle' && !isMacroVehicleTransaction(t)) return true;
    final subRaw = (t.subCategory ?? '').trim();
    if (subRaw.toLowerCase() == 'vehicletrip') return true;
    if (t.category != 'DailyLog') return false;
    if (subRaw.toLowerCase() == 'sand') return false;
    if (t.description.contains('ทรายที่ล้างที่บ้าน')) return false;
    return (t.vehicleId ?? '').trim().isNotEmpty ||
        (t.driverId ?? '').trim().isNotEmpty ||
        (t.workDetails ?? '').trim().isNotEmpty ||
        ((t.perCarTrips ?? 0) > 0) ||
        ((t.tripCount ?? 0) > 0) ||
        ((t.tripMorning ?? 0) > 0) ||
        ((t.tripAfternoon ?? 0) > 0) ||
        ((t.cubicPerTrip ?? 0) > 0) ||
        ((t.totalCubic ?? 0) > 0);
  }

  bool fuelTouches() => t.category == 'Fuel';

  bool dailyEventTouches() {
    if (t.category != 'DailyLog') return false;
    return (t.subCategory ?? '').trim() == 'Event';
  }

  bool macroVehicleTouches() {
    return t.category == 'Vehicle' &&
        isMacroVehicleTransaction(t) &&
        ((t.vehicleId ?? '').trim().isNotEmpty ||
            (t.driverId ?? '').trim().isNotEmpty ||
            (t.workDetails ?? '').trim().isNotEmpty);
  }

  bool laborTouches() {
    if (t.category == 'Leave') return false;
    if (t.category != 'Labor') return false;
    final ls = (t.laborStatus ?? '').toLowerCase();
    final sc = (t.subCategory ?? '').toLowerCase();
    if (sc == 'ot' || ls == 'ot') return false;
    if (sc == 'advance' || ls == 'advance') return false;
    if (ls == 'leave' || ls == 'sick' || ls == 'personal') return false;
    return true;
  }

  bool leaveRecordTouches() {
    final cat = t.category.trim();
    if (cat == 'Leave' || t.type.toLowerCase() == 'leave') {
      return t.employeeIds.isNotEmpty;
    }
    final ls = (t.laborStatus ?? '').toLowerCase();
    return t.category == 'Labor' &&
        (ls == 'leave' || ls == 'sick' || ls == 'personal') &&
        t.employeeIds.isNotEmpty;
  }

  bool advanceRecordTouches() {
    return t.category == 'Labor' &&
        (t.subCategory ?? '').trim().toLowerCase() == 'advance' &&
        (t.laborStatus ?? '').trim().toLowerCase() == 'advance';
  }

  bool otTouches() {
    return t.category == 'Labor' &&
        ((t.laborStatus ?? '').toUpperCase() == 'OT' ||
            (t.subCategory ?? '').toLowerCase() == 'ot');
  }

  switch (moduleCategory) {
    case 'บันทึกการร่อนทราย':
      return sandWashTouches();
    case 'ทรายที่ล้างที่บ้าน':
      return homeSandTouches();
    case 'จำนวนเที่ยวรถ':
      return vehicleTouches();
    case 'การใช้รถแม็คโคร':
      return macroVehicleTouches();
    case 'น้ำมัน':
      return fuelTouches();
    case 'เหตุการณ์':
      return dailyEventTouches();
    case 'ค่าแรง':
      return t.category == 'ค่าแรง' || laborTouches();
    case 'บันทึกการทำงาน':
      return laborTouches() || t.category == 'ค่าแรง';
    case 'ลางาน':
      return leaveRecordTouches();
    case 'เบิกเงิน':
      return advanceRecordTouches();
    case 'OT':
      return otTouches();
    case 'รายจ่ายรายรับ':
      return transactionIsUtilitiesExpense(t) || transactionIsWizardDailyIncome(t);
    default:
      if (moduleCategory.contains('ล่วงเวลา')) return otTouches();
      return t.category == moduleCategory;
  }
}

/// ธุรกรรมที่ใช้สำหรับเมนู **จำนวนเที่ยวรถ** / ภาพรวมว่า «บันทึกแล้ว»
///
/// **ไม่** นับแถว `DailyLog` + Sand (ร่อนทราย / ถังที่บ้าน เดินทางใต้ DailyLog เหมือนกัน)
/// เพื่อกันการขึ้นเช็คทั้งที่ผู้ใช้ยังไม่กรอกรถจริง
bool transactionCountsAsVehicleTripMenu(AppTransaction t) {
  final subRaw = (t.subCategory ?? '').trim();
  if (t.category == 'Vehicle') {
    // แม็คโครอยู่เมนู «การใช้รถแม็คโคร» — ไม่นับเป็นเที่ยวดรัม
    return !isMacroVehicleTransaction(t);
  }
  if (t.category != 'DailyLog') return false;
  if (subRaw.toLowerCase() == 'sand') return false;

  final desc = t.description;
  if (desc.contains('ทรายที่ล้างที่บ้าน')) return false;

  if (subRaw.toLowerCase() != 'vehicletrip') return false;

  final hasVid = (t.vehicleId ?? '').trim().isNotEmpty ||
      (t.driverId ?? '').trim().isNotEmpty;
  if (!hasVid) return false;

  final mode = (t.tripBillingMode ?? '').trim();
  final isLumpSum =
      mode.toLowerCase() == 'lumpsum' || mode == 'เหมา';
  if (isLumpSum) {
    final cubic = (t.perCarCubic ?? t.totalCubic ?? 0).toDouble();
    return cubic > 0;
  }

  final trips = (t.perCarTrips ?? t.tripCount ?? 0).toDouble();
  return trips > 0;
}

/// แถวที่เมนู **จำนวนเที่ยวรถ** / หน้าแอปควรโหลดแสดง (รวมแถว 0 เที่ยวจาก Daily Wizard บนเว็บ)
bool transactionMatchesVehicleTripModuleList(AppTransaction t) {
  if (isMacroVehicleTransaction(t)) return false;
  if (t.description.contains('ทรายที่ล้างที่บ้าน')) return false;
  if (t.category == 'Vehicle') return true;
  if (t.category == 'DailyLog' &&
      (t.subCategory ?? '').trim().toLowerCase() == 'vehicletrip') {
    final hasVid = (t.vehicleId ?? '').trim().isNotEmpty ||
        (t.driverId ?? '').trim().isNotEmpty;
    return hasVid;
  }
  return false;
}

/// จับคู่แถว [transactions] กับเมนูบันทึกประจำวันที่เลือก (หมวดจากแดชบอร์ด)
bool transactionMatchesDailyModule(
  AppTransaction t,
  String dayKey,
  String moduleCategory,
) {
  if (!transactionAppliesToDashboardDay(t, dayKey, moduleCategory)) {
    return false;
  }

  bool sandWashLike() {
    if (t.description.contains('ทรายที่ล้างที่บ้าน')) return false;
    if (t.subCategory == 'Sand') return true;
    if (t.category.contains('ร่อนทราย')) return true;
    if ((t.sandMorning ?? 0) > 0 || (t.sandAfternoon ?? 0) > 0) return true;
    if ((t.drumsObtained ?? 0) > 0 &&
        (t.description.contains('ถัง') || t.description.contains('จำนวนถัง'))) {
      return true;
    }
    return false;
  }

  bool homeSandLike() {
    if (isHomeSandRoundCloseRow(t)) return true;
    return isDedicatedHomeSandWashRow(t) ||
        ((t.drumsWashedAtHome ?? 0) > 0 && t.description.contains('ล้างที่บ้าน'));
  }

  bool vehicleLike() => transactionMatchesVehicleTripModuleList(t);

  bool macroVehicleLike() {
    return t.category == 'Vehicle' &&
        isMacroVehicleTransaction(t) &&
        (t.vehicleId ?? '').trim().isNotEmpty &&
        (t.driverId ?? '').trim().isNotEmpty;
  }

  bool fuelLike() => t.category == 'Fuel';

  bool dailyEventLike() {
    if (t.category != 'DailyLog') return false;
    if ((t.subCategory ?? '').trim() != 'Event') return false;
    return t.description.trim().isNotEmpty;
  }

  bool laborLike() {
    if (t.category != 'Labor') return false;
    final ls = (t.laborStatus ?? '').toLowerCase();
    final sc = (t.subCategory ?? '').toLowerCase();
    if (sc == 'ot' || ls == 'ot') return false;
    if (sc == 'advance' || ls == 'advance') return false;
    if (ls == 'leave' || ls == 'sick' || ls == 'personal') return false;
    return true;
  }

  bool otLike() {
    return t.category == 'Labor' &&
        ((t.laborStatus ?? '').toUpperCase() == 'OT' ||
            (t.subCategory ?? '').toLowerCase() == 'ot');
  }

  bool leaveLike() {
    if (t.type.toLowerCase() == 'leave' || t.category == 'Leave') {
      return t.employeeIds.isNotEmpty;
    }
    final ls = (t.laborStatus ?? '').toLowerCase();
    return t.category == 'Labor' &&
        (ls == 'leave' || ls == 'sick' || ls == 'personal') &&
        t.employeeIds.isNotEmpty;
  }

  bool advanceLike() {
    return t.category == 'Labor' &&
        (t.subCategory ?? '').trim().toLowerCase() == 'advance' &&
        (t.laborStatus ?? '').trim().toLowerCase() == 'advance' &&
        t.employeeIds.isNotEmpty;
  }

  switch (moduleCategory) {
    case 'บันทึกการร่อนทราย':
      return sandWashLike();
    case 'ทรายที่ล้างที่บ้าน':
      return homeSandLike();
    case 'จำนวนเที่ยวรถ':
      return vehicleLike();
    case 'การใช้รถแม็คโคร':
      return macroVehicleLike();
    case 'น้ำมัน':
      return fuelLike();
    case 'เหตุการณ์':
      return dailyEventLike();
    case 'ค่าแรง':
      return t.category == 'ค่าแรง' || laborLike();
    case 'บันทึกการทำงาน':
      return laborLike() || t.category == 'ค่าแรง';
    case 'ลางาน':
      return leaveLike();
    case 'เบิกเงิน':
      return advanceLike();
    case 'OT':
      return otLike();
    case 'รายจ่ายรายรับ':
      return transactionIsUtilitiesExpense(t) ||
          transactionIsWizardDailyIncome(t);
    default:
      if (moduleCategory.contains('ล่วงเวลา')) return otLike();
      return t.category == moduleCategory;
  }
}

String formatTxnHistoryTime(DateTime? dt) {
  if (dt == null) return '—';
  final l = dt.toLocal();
  final hh = l.hour.toString().padLeft(2, '0');
  final mm = l.minute.toString().padLeft(2, '0');
  final be = l.year + 543;
  return '${l.day}/${l.month}/$be $hh:$mm น.';
}
