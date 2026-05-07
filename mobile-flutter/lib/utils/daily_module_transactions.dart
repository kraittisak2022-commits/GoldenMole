import '../models/app_transaction.dart';

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

  bool vehicleLike() {
    return t.category == 'Vehicle' ||
        t.category == 'DailyLog' ||
        t.subCategory == 'VehicleTrip';
  }

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
