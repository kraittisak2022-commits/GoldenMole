import '../models/app_transaction.dart';

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
    if (t.date != dayKey) continue;
    if (transactionMatchesDailyModule(t, dayKey, moduleCategory)) {
      complete = true;
      break;
    }
    if (transactionTouchesDailyModule(t, dayKey, moduleCategory)) {
      touch = true;
    }
  }
  if (complete) return DailyModuleFillStatus.complete;
  if (touch) return DailyModuleFillStatus.incomplete;
  return DailyModuleFillStatus.pending;
}

/// มีข้อมูลที่ «เกี่ยวข้องกับเมนู» แบบผ่อน (ยังไม่ถือว่าครบ)
bool transactionTouchesDailyModule(
  AppTransaction t,
  String dayKey,
  String moduleCategory,
) {
  if (t.date != dayKey) return false;

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
    return t.category == 'Labor' &&
        (t.laborStatus ?? '').toLowerCase() != 'ot' &&
        (t.subCategory ?? '').toLowerCase() != 'ot';
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
  if (t.date != dayKey) return false;

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
    return t.category == 'Labor' &&
        (t.laborStatus ?? '').toLowerCase() != 'ot' &&
        (t.subCategory ?? '').toLowerCase() != 'ot';
  }

  bool otLike() {
    return t.category == 'Labor' &&
        ((t.laborStatus ?? '').toUpperCase() == 'OT' ||
            (t.subCategory ?? '').toLowerCase() == 'ot');
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
