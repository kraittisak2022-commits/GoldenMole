import '../models/app_transaction.dart';
import '../models/employee.dart';
import 'count_record_work_mode.dart';

bool _countRecordModeIncludesTrips(CountRecordWorkMode? mode) =>
    mode == null ||
    mode == CountRecordWorkMode.trip ||
    mode == CountRecordWorkMode.both;

bool _countRecordModeIncludesSand(CountRecordWorkMode? mode) =>
    mode == null ||
    mode == CountRecordWorkMode.sand ||
    mode == CountRecordWorkMode.both;

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

/// แถวการนับ «บันทึกและนับจำนวน → การร่อนทราย» (มี lapTimes/จำนวนรอบ)
/// แยกออกจากแถวฟอร์ม «บันทึกการร่อนทราย» (เครื่องร่อนใหม่/เก่า, จำนวนถัง)
bool isCountRecordSandTapRow(AppTransaction t) {
  if (t.category != 'DailyLog') return false;
  if ((t.subCategory ?? '').trim().toLowerCase() != 'sand') return false;
  final desc = t.description;
  if (desc.contains('เครื่องร่อน')) return false;
  if (desc.contains('จำนวนถัง')) return false;
  if (desc.contains('ทรายที่ล้างที่บ้าน')) return false;
  return desc.contains('ร่อนทราย');
}

/// แถวล้างทรายเครื่องร่อน (มีคิวเช้า/บ่าย — ไม่นับถังอย่างเดียว / ทรายที่บ้าน / ตัดรอบ)
bool countsAsSandWashCubicRow(AppTransaction t) {
  if (t.description.contains('ทรายที่ล้างที่บ้าน')) return false;
  if (isHomeSandRoundCloseRow(t)) return false;
  if (isCountRecordSandTapRow(t)) return false;
  final sub = (t.subCategory ?? '').trim().toLowerCase();
  if (t.category == 'DailyLog' && sub == 'sand') {
    if (t.description.contains('จำนวนถัง')) return false;
    final morning = (t.sandMorning ?? 0);
    final afternoon = (t.sandAfternoon ?? 0);
    if (morning + afternoon > 0) return true;
    final mt = (t.sandMachineType ?? '').trim();
    return mt == 'Old' || mt == 'New';
  }
  if (t.category.contains('ร่อนทราย')) {
    return (t.sandMorning ?? 0) > 0 || (t.sandAfternoon ?? 0) > 0;
  }
  return false;
}

/// รวมคิวล้างทรายช่วงเช้า/บ่ายของวัน (จากแถวเครื่องร่อน)
({double morning, double afternoon}) sandWashPeriodTotalsForDay(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  var morning = 0.0;
  var afternoon = 0.0;
  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    if (!countsAsSandWashCubicRow(t)) continue;
    morning += (t.sandMorning ?? 0);
    afternoon += (t.sandAfternoon ?? 0);
  }
  return (morning: morning, afternoon: afternoon);
}

/// จำนวนถังที่ได้รับวันนี้ — จากแถวบันทึกเฉพาะ (ไม่รวมการนับรอบ / เครื่องร่อน)
double sandWashDrumsObtainedForDay(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  var drums = 0.0;
  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    if (t.description.contains('ทรายที่ล้างที่บ้าน')) continue;
    if (isCountRecordSandTapRow(t)) continue;
    if (!t.description.contains('จำนวนถัง')) continue;
    final d = (t.drumsObtained ?? 0).toDouble();
    if (d > drums) drums = d;
  }
  return drums;
}

/// ตัวเลขบนการ์ดเมนู (คิว / เที่ยว / ลิตร / ถัง)
String formatDashboardMetric(double v) {
  if (v.abs() < 1e-9) return '0';
  if ((v - v.roundToDouble()).abs() < 1e-9) return '${v.round()}';
  final s = v.toStringAsFixed(1);
  if (s.endsWith('.0')) return s.substring(0, s.length - 2);
  return s;
}

@Deprecated('ใช้ formatDashboardMetric')
String formatSandWashCubic(double v) => formatDashboardMetric(v);

String normalizeSandDayKey(String raw) {
  final s = raw.trim();
  if (s.length >= 10) return s.substring(0, 10);
  return s;
}

String _joinStatusParts(Iterable<String> parts) =>
    parts.where((p) => p.trim().isNotEmpty).join(' · ');

bool isLaborWorkAttendanceRow(AppTransaction t) {
  if (t.category == 'ค่าแรง') return t.employeeIds.isNotEmpty;
  if (t.category != 'Labor') return false;
  final ls = (t.laborStatus ?? '').toLowerCase();
  final sc = (t.subCategory ?? '').toLowerCase();
  if (sc == 'ot' || ls == 'ot') return false;
  if (sc == 'advance' || ls == 'advance') return false;
  if (ls == 'leave' || ls == 'sick' || ls == 'personal') return false;
  return t.employeeIds.isNotEmpty;
}

bool isOtLaborRow(AppTransaction t) {
  if (t.category != 'Labor') return false;
  final ls = (t.laborStatus ?? '').toUpperCase();
  final sc = (t.subCategory ?? '').toLowerCase();
  return ls == 'OT' || sc == 'ot';
}

/// สรุปถังล้างที่บ้าน / คงเหลือ — สอดคล้อง `_refreshHomeSandStock` บน Quick Input
({double washedToday, double remainingAfterWash}) computeHomeSandDrumStockForDay(
  String dayKey,
  Iterable<AppTransaction> allTransactions,
) {
  final byDay = <String, List<AppTransaction>>{};
  for (final t in allTransactions) {
    if (t.category != 'DailyLog' || (t.subCategory ?? '').trim() != 'Sand') {
      continue;
    }
    final day = normalizeSandDayKey(t.date);
    byDay.putIfAbsent(day, () => []).add(t);
  }
  final map = <String, ({double obtained, double home})>{};
  for (final e in byDay.entries) {
    final txs = e.value;
    var obtained = 0.0;
    for (final t in txs) {
      final o = (t.drumsObtained ?? 0).toDouble();
      if (o > obtained) obtained = o;
    }
    map[e.key] = (obtained: obtained, home: persistedSandHomeDrumsForDay(txs));
  }

  final days = map.keys.toList()..sort();
  var before = 0.0;
  for (final d in days) {
    if (d.compareTo(dayKey) >= 0) continue;
    final rec = map[d]!;
    before = (before + rec.obtained - rec.home).clamp(0.0, 9999999.0);
  }
  final today = map[dayKey];
  final obtainedToday = today?.obtained ?? 0.0;
  final washedToday = today?.home ?? 0.0;
  final remaining = (before + obtainedToday - washedToday).clamp(0.0, 9999999.0);
  return (washedToday: washedToday, remainingAfterWash: remaining);
}

({int vehicleCount, double morningTrips, double afternoonTrips})
    vehicleTripSummaryForDay(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  final vehicles = <String>{};
  var morning = 0.0;
  var afternoon = 0.0;
  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    if (!transactionMatchesVehicleTripModuleList(t)) continue;
    final v = (t.vehicleId ?? '').trim();
    if (v.isNotEmpty) vehicles.add(v);
    final split = vehicleTripPeriodSplit(t);
    morning += split.morning;
    afternoon += split.afternoon;
  }
  return (
    vehicleCount: vehicles.length,
    morningTrips: morning,
    afternoonTrips: afternoon,
  );
}

int macroVehicleUsageCountForDay(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  var n = 0;
  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    if (!transactionTouchesDailyModule(t, dayKey, 'การใช้รถแม็คโคร')) continue;
    n++;
  }
  return n;
}

double fuelLitersTotalForDay(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  var sum = 0.0;
  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    if (!isFuelVehicleUsageRow(t)) continue;
    sum += (t.quantity ?? 0);
  }
  return sum;
}

/// รับเข้าสต็อก vs เติมรถ — สอดคล้อง `inferFuelMovement` บนเว็บ
bool isFuelStockOutRow(AppTransaction t) {
  if (t.category != 'Fuel') return false;
  final mov = (t.fuelMovement ?? '').trim().toLowerCase();
  if (mov == 'stock_in') return false;
  if (mov == 'stock_out') return true;
  return (t.vehicleId ?? '').trim().isNotEmpty;
}

/// แถวบันทึกการใช้น้ำมันรายคัน (เติมรถ / stock_out)
bool isFuelVehicleUsageRow(AppTransaction t) {
  if (!isFuelStockOutRow(t)) return false;
  final vehicle = (t.vehicleId ?? '').trim();
  if (vehicle.isEmpty) return false;
  return (t.quantity ?? 0) > 0;
}

Set<String> macroVehicleIdsUsedForDay(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  final ids = <String>{};
  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    if (!transactionTouchesDailyModule(t, dayKey, 'การใช้รถแม็คโคร')) continue;
    final v = (t.vehicleId ?? '').trim();
    if (v.isNotEmpty) ids.add(v);
  }
  return ids;
}

/// คนขับจากบันทึกการใช้รถแม็คโครวันนั้น (driverId ไม่ซ้ำ)
Set<String> macroDriverIdsUsedForDay(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  final ids = <String>{};
  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    if (!transactionTouchesDailyModule(t, dayKey, 'การใช้รถแม็คโคร')) continue;
    final d = (t.driverId ?? '').trim();
    if (d.isNotEmpty) ids.add(d);
  }
  return ids;
}

Set<String> fuelVehicleIdsReportedForDay(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  final ids = <String>{};
  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    if (!isFuelVehicleUsageRow(t)) continue;
    final v = (t.vehicleId ?? '').trim();
    if (v.isNotEmpty) ids.add(v);
  }
  return ids;
}

({
  int usedCount,
  int fueledCount,
  double liters,
  bool allUsedFueled,
}) fuelVehicleCoverageForDay(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  final used = macroVehicleIdsUsedForDay(dayKey, transactions);
  final fueled = fuelVehicleIdsReportedForDay(dayKey, transactions);
  final liters = fuelLitersTotalForDay(dayKey, transactions);
  final missing = used.difference(fueled);
  return (
    usedCount: used.length,
    fueledCount: fueled.length,
    liters: liters,
    allUsedFueled: used.isNotEmpty && missing.isEmpty,
  );
}

DailyModuleFillStatus resolveFuelModuleFillStatus(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  final coverage = fuelVehicleCoverageForDay(dayKey, transactions);
  if (coverage.usedCount > 0) {
    return coverage.allUsedFueled
        ? DailyModuleFillStatus.complete
        : DailyModuleFillStatus.incomplete;
  }
  if (coverage.fueledCount > 0 || coverage.liters > 0) {
    return DailyModuleFillStatus.complete;
  }
  var touch = false;
  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    if (transactionTouchesDailyModule(t, dayKey, 'น้ำมัน')) {
      touch = true;
      break;
    }
  }
  return touch ? DailyModuleFillStatus.incomplete : DailyModuleFillStatus.pending;
}

int laborWorkHeadcountForDay(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  final ids = <String>{};
  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    if (!isLaborWorkAttendanceRow(t)) continue;
    for (final id in t.employeeIds) {
      final s = id.trim();
      if (s.isNotEmpty) ids.add(s);
    }
  }
  return ids.length;
}

String _formatOtHours(double hours) => formatDashboardMetric(hours);

List<({String empId, double hours})> otHoursByEmployeeForDay(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  final byEmp = <String, double>{};
  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    if (!isOtLaborRow(t)) continue;
    final h = (t.otHours ?? 0).toDouble();
    if (h <= 0) continue;
    for (final id in t.employeeIds) {
      final s = id.trim();
      if (s.isEmpty) continue;
      byEmp[s] = (byEmp[s] ?? 0) + h;
    }
  }
  return byEmp.entries
      .map((e) => (empId: e.key, hours: e.value))
      .toList();
}

/// ข้อความสถานะการ์ดเมนู «บันทึกการร่อนทราย» — คิวล้างช่วงเช้า/บ่าย + ถังที่ได้รับ
String dailySandWashModuleStatusLabel(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  final totals = sandWashPeriodTotalsForDay(dayKey, transactions);
  final drums = sandWashDrumsObtainedForDay(dayKey, transactions);
  final parts = <String>[];
  var morning = totals.morning;
  var afternoon = totals.afternoon;
  var usedCountRecordFallback = false;
  // ยังไม่ได้บันทึกฟอร์มเครื่องร่อน → ใช้จำนวนรอบที่นับใน
  // «บันทึกและนับจำนวน → การร่อนทราย» (ค่าเดียวกับที่ฟอร์ม prefill)
  if (morning <= 0 && afternoon <= 0) {
    final rounds = countRecordSandPeriodTotals(dayKey, transactions);
    morning = rounds.morning.toDouble();
    afternoon = rounds.afternoon.toDouble();
    usedCountRecordFallback = true;
  }
  if (morning > 0 || afternoon > 0) {
    parts.add('เช้า ${formatSandWashCubic(morning)} คิว');
    parts.add('บ่าย ${formatSandWashCubic(afternoon)} คิว');
  } else if (usedCountRecordFallback) {
    // มีการนับรอบแต่แยกช่วงเช้า/บ่ายไม่ได้ (ไม่มี lapTimes) → โชว์ยอดรวมรอบ
    final totalRounds = countRecordSandRoundsForDay(dayKey, transactions);
    if (totalRounds > 0) {
      parts.add('ร่อน ${formatDashboardMetric(totalRounds)} รอบ');
    }
  }
  if (drums > 0) {
    parts.add('ถัง ${formatSandWashCubic(drums)}');
  }
  if (parts.isNotEmpty) return _joinStatusParts(parts);
  return 'ยังไม่มีบันทึกล้างทราย';
}

/// ข้อความสถานะการ์ดเมนู «บันทึกรถดรัมและจำนวนเที่ยว»
String dailyVehicleTripModuleStatusLabel(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  final s = vehicleTripSummaryForDay(dayKey, transactions);
  if (s.vehicleCount > 0 ||
      s.morningTrips > 0 ||
      s.afternoonTrips > 0) {
    return _joinStatusParts([
      '${s.vehicleCount} คัน',
      'เช้า ${formatDashboardMetric(s.morningTrips)} เที่ยว',
      'บ่าย ${formatDashboardMetric(s.afternoonTrips)} เที่ยว',
    ]);
  }
  return 'ยังไม่มีบันทึกรถ/เที่ยว';
}

/// ข้อความสถานะการ์ดเมนู «การใช้รถแม็คโคร»
String dailyMacroVehicleModuleStatusLabel(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  final n = macroVehicleUsageCountForDay(dayKey, transactions);
  if (n > 0) return 'ใช้แม็คโคร $n คัน';
  return 'ยังไม่มีบันทึกแม็คโคร';
}

/// ข้อความสถานะการ์ดเมนู «น้ำมัน»
String dailyFuelModuleStatusLabel(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  final c = fuelVehicleCoverageForDay(dayKey, transactions);
  final parts = <String>[];
  if (c.usedCount > 0) {
    parts.add('ใช้งาน ${c.usedCount} คัน');
    parts.add('แจ้ง ${c.fueledCount}/${c.usedCount} คัน');
    parts.add(c.allUsedFueled ? 'ครบแล้ว' : 'ยังไม่ครบ');
  } else if (c.fueledCount > 0) {
    parts.add('แจ้ง ${c.fueledCount} คัน');
  }
  if (c.liters > 0) {
    parts.add('${formatDashboardMetric(c.liters)} ลิตร');
  }
  if (parts.isNotEmpty) return _joinStatusParts(parts);
  return 'ยังไม่มีบันทึกน้ำมัน';
}

/// ข้อความสถานะการ์ดเมนู «ทรายที่ล้างที่บ้าน»
String dailyHomeSandModuleStatusLabel(
  String dayKey,
  Iterable<AppTransaction> dayTransactions, {
  Iterable<AppTransaction>? allTransactionsForStock,
}) {
  final stock = computeHomeSandDrumStockForDay(
    dayKey,
    allTransactionsForStock ?? dayTransactions,
  );
  if (stock.washedToday > 0 || stock.remainingAfterWash > 0) {
    return _joinStatusParts([
      'ล้าง ${formatDashboardMetric(stock.washedToday)} ถัง',
      'คงเหลือ ${formatDashboardMetric(stock.remainingAfterWash)} ถัง',
    ]);
  }
  if (dayTransactions.any(
    (t) =>
        t.date.trim() == dayKey.trim() &&
        transactionTouchesDailyModule(t, dayKey, 'ทรายที่ล้างที่บ้าน'),
  )) {
    return 'บันทึกแล้ว · ยังไม่ระบุถัง';
  }
  return 'ยังไม่มีบันทึกล้างที่บ้าน';
}

/// ข้อความสถานะการ์ดเมนู «บันทึกการทำงาน» (หมวด `ค่าแรง`)
String dailyLaborWorkModuleStatusLabel(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  final n = laborWorkHeadcountForDay(dayKey, transactions);
  if (n > 0) return 'มาทำงาน $n คน';
  return 'ยังไม่มีบันทึกค่าแรง';
}

/// ข้อความสถานะการ์ดเมนู «การทำงานล่วงเวลา (OT)»
String dailyOtModuleStatusLabel(
  String dayKey,
  Iterable<AppTransaction> transactions,
  List<Employee> employees, {
  int maxNames = 2,
}) {
  final rows = otHoursByEmployeeForDay(dayKey, transactions);
  if (rows.isEmpty) return 'ยังไม่มีบันทึก OT';
  rows.sort(
    (a, b) => calendarEmployeeDisplayName(a.empId, employees)
        .compareTo(calendarEmployeeDisplayName(b.empId, employees)),
  );
  final parts = <String>[];
  for (var i = 0; i < rows.length && i < maxNames; i++) {
    final r = rows[i];
    final name = calendarEmployeeDisplayName(r.empId, employees);
    parts.add('$name ${_formatOtHours(r.hours)} ชม.');
  }
  if (rows.length > maxNames) {
    parts.add('+${rows.length - maxNames}');
  }
  return _joinStatusParts(parts);
}

/// ข้อความสถานะการ์ดเมนูบันทึกประจำวัน (แสดงบนการ์ดเมื่อมีข้อมูล)
String? dailyModuleCardStatusLabel({
  required String moduleCategory,
  required String dayKey,
  required Iterable<AppTransaction> dayTransactions,
  List<Employee> employees = const [],
  Iterable<AppTransaction>? allTransactionsForStock,
}) {
  switch (moduleCategory) {
    case 'ลางาน':
      return dailyLeaveModuleStatusLabel(
        dayKey,
        dayTransactions,
        employees,
      );
    case 'บันทึกการร่อนทราย':
      return dailySandWashModuleStatusLabel(dayKey, dayTransactions);
    case 'จำนวนเที่ยวรถ':
      return dailyVehicleTripModuleStatusLabel(dayKey, dayTransactions);
    case 'การใช้รถแม็คโคร':
      return dailyMacroVehicleModuleStatusLabel(dayKey, dayTransactions);
    case 'น้ำมัน':
      return dailyFuelModuleStatusLabel(dayKey, dayTransactions);
    case 'ทรายที่ล้างที่บ้าน':
      return dailyHomeSandModuleStatusLabel(
        dayKey,
        dayTransactions,
        allTransactionsForStock: allTransactionsForStock,
      );
    case 'ค่าแรง':
      return dailyLaborWorkModuleStatusLabel(dayKey, dayTransactions);
    case 'OT':
      return dailyOtModuleStatusLabel(
        dayKey,
        dayTransactions,
        employees,
      );
    default:
      if (moduleCategory.contains('ล่วงเวลา')) {
        return dailyOtModuleStatusLabel(
          dayKey,
          dayTransactions,
          employees,
        );
      }
      return null;
  }
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

bool _isCountRecordVehicleRow(AppTransaction t) {
  if (t.category != 'DailyLog') return false;
  if ((t.subCategory ?? '').trim().toLowerCase() != 'vehicletrip') {
    return false;
  }
  return !t.description.contains('ทรายที่ล้างที่บ้าน');
}

bool _isCountRecordSandRow(AppTransaction t) {
  if (t.category != 'DailyLog') return false;
  if ((t.subCategory ?? '').trim().toLowerCase() != 'sand') return false;
  return !t.description.contains('ทรายที่ล้างที่บ้าน');
}

bool _countRecordRowHasLapTimes(AppTransaction t) {
  final laps = t.workAssignments?['lapTimes'];
  return (laps as List?)?.isNotEmpty ?? false;
}

bool countRecordRowHasSavedData(AppTransaction t) {
  if (_isCountRecordVehicleRow(t)) {
    final trips = (t.perCarTrips ?? t.tripCount ?? 0).toDouble();
    return trips > 0 || _countRecordRowHasLapTimes(t);
  }
  if (_isCountRecordSandRow(t)) {
    final drums = (t.drumsObtained ?? 0).toDouble();
    return drums > 0 || _countRecordRowHasLapTimes(t);
  }
  return false;
}

bool _countRecordRowTouches(AppTransaction t) {
  if (_isCountRecordVehicleRow(t)) {
    return (t.vehicleId ?? '').trim().isNotEmpty ||
        (t.driverId ?? '').trim().isNotEmpty;
  }
  if (_isCountRecordSandRow(t)) return true;
  return false;
}

/// สถานะการ์ดเมนู «บันทึกและนับจำนวน» บนหน้าเมนูหลักบันทึกประจำวัน
DailyModuleFillStatus resolveCountRecordMenuFillStatus(
  String dayKey,
  Iterable<AppTransaction> transactions, {
  CountRecordWorkMode? workMode,
}) {
  final includeTrips = _countRecordModeIncludesTrips(workMode);
  final includeSand = _countRecordModeIncludesSand(workMode);
  var complete = false;
  var touch = false;
  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    final isTrip = _isCountRecordVehicleRow(t);
    final isSand = _isCountRecordSandRow(t);
    if (isTrip && !includeTrips) continue;
    if (isSand && !includeSand) continue;
    if (!isTrip && !isSand) continue;
    if (countRecordRowHasSavedData(t)) {
      complete = true;
      break;
    }
    if (_countRecordRowTouches(t)) touch = true;
  }
  if (complete) return DailyModuleFillStatus.complete;
  if (touch) return DailyModuleFillStatus.incomplete;
  return DailyModuleFillStatus.pending;
}

/// ชั่วโมงของ lap «dd/MM HH:mm:ss» (คืน null หากแยกไม่ได้)
int? _countRecordLapHour(String lap) {
  final s = lap.trim();
  final sp = s.indexOf(' ');
  if (sp < 0) return null;
  final time = s.substring(sp + 1);
  final colon = time.indexOf(':');
  final hourStr = colon < 0 ? time : time.substring(0, colon);
  return int.tryParse(hourStr.trim());
}

/// แยกจำนวน lap ของแถวออกเป็นช่วงเช้า (ก่อน 12:00) / บ่าย (ตั้งแต่ 12:00)
({int morning, int afternoon, int unknown}) _countRecordLapPeriods(
  AppTransaction t,
) {
  final laps = (t.workAssignments?['lapTimes'] as List?) ?? const [];
  var morning = 0;
  var afternoon = 0;
  var unknown = 0;
  for (final lap in laps) {
    final h = _countRecordLapHour(lap.toString());
    if (h == null) {
      unknown++;
    } else if (h < 12) {
      morning++;
    } else {
      afternoon++;
    }
  }
  return (morning: morning, afternoon: afternoon, unknown: unknown);
}

/// แยกจำนวนเที่ยวของแถว VehicleTrip ออกเป็นช่วงเช้า/บ่าย ให้สอดคล้องกันทุกที่
///
/// ลำดับการตัดสิน:
/// 1) ถ้ามีค่า `tripMorning`/`tripAfternoon` (กรอกจากฟอร์มดรัม) ใช้ค่านั้นตรงๆ
/// 2) ไม่งั้นแยกจาก `lapTimes` ของตัวนับ — เช้า (ก่อน 12:00) / บ่าย (ตั้งแต่ 12:00)
///    (lap ที่อ่านเวลาไม่ได้ นับเป็นช่วงเช้า)
/// 3) ไม่งั้นใช้ยอดรวม `perCarTrips`/`tripCount` ทั้งหมดเป็นช่วงเช้า
({double morning, double afternoon}) vehicleTripPeriodSplit(AppTransaction t) {
  final tm = (t.tripMorning ?? 0).toDouble();
  final ta = (t.tripAfternoon ?? 0).toDouble();
  if (tm != 0 || ta != 0) {
    return (morning: tm, afternoon: ta);
  }
  final periods = _countRecordLapPeriods(t);
  if (periods.morning > 0 || periods.afternoon > 0 || periods.unknown > 0) {
    return (
      morning: (periods.morning + periods.unknown).toDouble(),
      afternoon: periods.afternoon.toDouble(),
    );
  }
  final total = (t.perCarTrips ?? t.tripCount ?? 0).toDouble();
  return (morning: total, afternoon: 0);
}

/// ข้อความสถานะการ์ดเมนู «บันทึกและนับจำนวน»
String? countRecordMenuStatusLabel(
  String dayKey,
  Iterable<AppTransaction> transactions, {
  CountRecordWorkMode? workMode,
}) {
  final includeTrips = _countRecordModeIncludesTrips(workMode);
  final includeSand = _countRecordModeIncludesSand(workMode);
  final vehicles = <String>{};
  var tripTotal = 0.0;
  var sandRounds = 0.0;
  var sandMorning = 0;
  var sandAfternoon = 0;

  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    if (!countRecordRowHasSavedData(t)) continue;
    if (includeTrips && _isCountRecordVehicleRow(t)) {
      final vid = (t.vehicleId ?? '').trim();
      if (vid.isNotEmpty) vehicles.add(vid);
      tripTotal += (t.perCarTrips ?? t.tripCount ?? 0).toDouble();
    } else if (includeSand && _isCountRecordSandRow(t)) {
      sandRounds += (t.drumsObtained ?? 0).toDouble();
      final periods = _countRecordLapPeriods(t);
      sandMorning += periods.morning;
      sandAfternoon += periods.afternoon;
    }
  }

  final parts = <String>[];
  if (includeTrips && (tripTotal > 0 || vehicles.isNotEmpty)) {
    parts.add(
      '${vehicles.length} คัน · ${formatDashboardMetric(tripTotal)} เที่ยว',
    );
  }
  if (includeSand && sandRounds > 0) {
    final buf = StringBuffer('ร่อน ${formatDashboardMetric(sandRounds)} รอบ');
    if (sandMorning > 0 || sandAfternoon > 0) {
      buf.write(' (เช้า $sandMorning · บ่าย $sandAfternoon)');
    }
    parts.add(buf.toString());
  }
  if (parts.isEmpty) return null;
  return _joinStatusParts(parts);
}

/// รวมจำนวนรอบที่นับได้ในวันนั้นแยกช่วงเช้า (ก่อน 12:00) / บ่าย (ตั้งแต่ 12:00)
({int morning, int afternoon}) countRecordSandPeriodTotals(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  var morning = 0;
  var afternoon = 0;
  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    if (!isCountRecordSandTapRow(t)) continue;
    final p = _countRecordLapPeriods(t);
    morning += p.morning;
    afternoon += p.afternoon;
  }
  return (morning: morning, afternoon: afternoon);
}

/// รวมจำนวนรอบร่อนทรายทั้งวันจากแถว «บันทึกและนับจำนวน → การร่อนทราย»
/// (ใช้ตอนแยกช่วงเช้า/บ่ายไม่ได้เพราะไม่มี lapTimes)
double countRecordSandRoundsForDay(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  var rounds = 0.0;
  for (final t in transactions) {
    if (t.date.trim() != dayKey.trim()) continue;
    if (!isCountRecordSandTapRow(t)) continue;
    rounds += (t.drumsObtained ?? 0).toDouble();
  }
  return rounds;
}

/// แบ่งจำนวนรอบให้เครื่องร่อนใหม่/เก่า โดยเศษที่เหลือให้เครื่องใหม่ก่อน
/// (เช่น 6 → ใหม่ 3 / เก่า 3, 7 → ใหม่ 4 / เก่า 3)
({int newer, int older}) splitSandRoundsNewFirst(int rounds) {
  if (rounds <= 0) return (newer: 0, older: 0);
  final older = rounds ~/ 2;
  return (newer: rounds - older, older: older);
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
  if (moduleCategory == 'น้ำมัน') {
    return resolveFuelModuleFillStatus(dayKey, transactions);
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
    case 'เช็คชื่อ':
      return laborTouches() || leaveRecordTouches() || otTouches();
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

  // เช็คชื่อ: รวมรายการที่กระดานเช็คชื่อเขียนลง — ค่าแรง(มาทำงาน)/ลางาน/OT
  bool attendanceLike() {
    return laborLike() || leaveLike() || otLike();
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
    case 'เช็คชื่อ':
      return attendanceLike();
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
