import '../models/app_transaction.dart';

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
    if (t.category == 'Vehicle') return true;
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
    case 'น้ำมัน':
      return fuelTouches();
    case 'ค่าแรง':
      return t.category == 'ค่าแรง' || laborTouches();
    case 'บันทึกการทำงาน':
      return laborTouches() || t.category == 'ค่าแรง';
    case 'ลางาน':
      return leaveRecordTouches();
    case 'เบิกเงิน':
      return advanceRecordTouches();
    case 'ทดสอบ SMS':
      return false;
    case 'OT':
      return otTouches();
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
  if (t.category == 'Vehicle') return true;
  if (subRaw.toLowerCase() == 'vehicletrip') return true;
  if (t.category != 'DailyLog') return false;
  if (subRaw.toLowerCase() == 'sand') return false;

  final desc = t.description;
  if (desc.contains('ทรายที่ล้างที่บ้าน')) return false;

  final trips = (t.perCarTrips ?? t.tripCount ?? 0).toDouble();
  if (trips <= 0) return false;

  final hasVid = (t.vehicleId ?? '').trim().isNotEmpty ||
      (t.driverId ?? '').trim().isNotEmpty;
  return hasVid;
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
    return t.description.contains('ทรายที่ล้างที่บ้าน') ||
        ((t.drumsWashedAtHome ?? 0) > 0 && t.description.contains('ล้างที่บ้าน'));
  }

  bool vehicleLike() => transactionCountsAsVehicleTripMenu(t);

  bool fuelLike() => t.category == 'Fuel';

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
    final per = t.advanceAmount ?? 0;
    return t.category == 'Labor' &&
        (t.subCategory ?? '').trim().toLowerCase() == 'advance' &&
        (t.laborStatus ?? '').trim().toLowerCase() == 'advance' &&
        t.employeeIds.isNotEmpty &&
        (per > 0 || t.amount > 0);
  }

  switch (moduleCategory) {
    case 'บันทึกการร่อนทราย':
      return sandWashLike();
    case 'ทรายที่ล้างที่บ้าน':
      return homeSandLike();
    case 'จำนวนเที่ยวรถ':
      return vehicleLike();
    case 'น้ำมัน':
      return fuelLike();
    case 'ค่าแรง':
      return t.category == 'ค่าแรง' || laborLike();
    case 'บันทึกการทำงาน':
      return laborLike() || t.category == 'ค่าแรง';
    case 'ลางาน':
      return leaveLike();
    case 'เบิกเงิน':
      return advanceLike();
    case 'ทดสอบ SMS':
      return false;
    case 'OT':
      return otLike();
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
