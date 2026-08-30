import '../models/app_transaction.dart';
import 'daily_module_transactions.dart';
import 'sand_work_duration.dart';

/// ความจุถังสต็อกน้ำมันหลัก (ลิตร)
const double kFuelTankCapacityMainLiters = 12000;

/// ความจุถังสต็อกน้ำมันสำรอง (ลิตร)
const double kFuelTankCapacityReserveLiters = 1000;

/// alias ความเข้ากันได้ — หมายถึงถังหลัก
const double kFuelTankCapacityLiters = kFuelTankCapacityMainLiters;

/// รหัสถัง: หลัก / สำรอง
const String kFuelTankMain = 'main';
const String kFuelTankReserve = 'reserve';

/// วันตัดยอดสต็อก — ก่อนวันนี้ถือว่าน้ำมันในถังเหลือ 0 (ถูกใช้หมดแล้ว)
/// ตั้งแต่วันนี้หักลบจากถังปกติ · พ.ศ. 1 ส.ค. 2569 = ค.ศ. 2026-08-01
const String kFuelStockCutoverYmd = '2026-08-01';

/// `subCategory` ของแถวรับน้ำมันเข้าถัง (รถน้ำมันมาเติม)
const String kFuelStockInSubCategory = 'StockIn';

/// `subCategory` ของแถวเบิกน้ำมันออกจากถัง
const String kFuelWithdrawSubCategory = 'Withdraw';

/// `subCategory` ของคู่แถวโอนหลัก→สำรอง
const String kFuelTransferSubCategory = 'Transfer';

/// `subCategory` ของการใช้น้ำมันเครื่องร่อนทราย (อัตโนมัติ)
const String kFuelSandSieveSubCategory = 'SandSieve';

/// ชื่อรถ/เครื่องจักรที่บันทึกเมื่อเครื่องร่อนทรายทำงาน
const String kFuelSandSieveVehicleId = 'เครื่องจักรร่อนทราย เครื่องปั่นไฟ';

/// `subCategory` ของบันทึกการใช้น้ำมันรถแม็คโคร
const String kFuelVehicleUsageSubCategory = 'VehicleUsage';

/// อัตราใช้น้ำมันเครื่องร่อนทราย (ลิตร/ชั่วโมง)
const double kFuelSandSieveLitersPerHour = 18;

/// วัตถุประสงค์การเบิกน้ำมันออกจากถัง
enum FuelWithdrawPurpose { machine, car, generator, mayor, other }

/// รถที่เติมจากเมนู «เติมน้ำมันรถยนต์» (หักถังหลัก)
enum FuelCarFillVehicle { mighty, taplien, ahming, other }

const String kFuelCarFillMighty = 'ไมตี้';
const String kFuelCarFillTaplien = 'รถตาเปลื่ยน (ISUZU KB)';

/// ค่าเดิมที่เคยบันทึกไว้ก่อนเปลี่ยนชื่อ — ยังต้องอ่าน/แก้ได้
const String kFuelCarFillTaplienLegacy = 'รถตาเปลื่ยน';

/// ชื่ออื่นที่เคยบันทึกของรถตาเปลื่ยนคันเดียวกัน
const Set<String> kFuelCarFillTaplienLegacyIds = {
  kFuelCarFillTaplienLegacy,
  'ISUZU KB',
  'รถISUZUKB',
  'ISUZUตา',
  'IsuzuKB',
};

bool _isTaplienVehicleId(String vehicleId) {
  final v = vehicleId.trim();
  return v == kFuelCarFillTaplien || kFuelCarFillTaplienLegacyIds.contains(v);
}

const String kFuelCarFillAhming = 'อาหมิง';

String fuelCarFillVehicleLabelOf(FuelCarFillVehicle vehicle) {
  switch (vehicle) {
    case FuelCarFillVehicle.mighty:
      return kFuelCarFillMighty;
    case FuelCarFillVehicle.taplien:
      return kFuelCarFillTaplien;
    case FuelCarFillVehicle.ahming:
      return kFuelCarFillAhming;
    case FuelCarFillVehicle.other:
      return 'อื่นๆ';
  }
}

/// ค่า `vehicleId` ที่บันทึก — อื่นๆ ใช้ข้อความที่ระบุ
String fuelCarFillVehicleIdOf(
  FuelCarFillVehicle vehicle, {
  String otherText = '',
}) {
  switch (vehicle) {
    case FuelCarFillVehicle.mighty:
      return kFuelCarFillMighty;
    case FuelCarFillVehicle.taplien:
      return kFuelCarFillTaplien;
    case FuelCarFillVehicle.ahming:
      return kFuelCarFillAhming;
    case FuelCarFillVehicle.other:
      return otherText.trim();
  }
}

String fuelWithdrawPurposeCodeOf(FuelWithdrawPurpose purpose) {
  switch (purpose) {
    case FuelWithdrawPurpose.machine:
      return 'machine';
    case FuelWithdrawPurpose.car:
      return 'car';
    case FuelWithdrawPurpose.generator:
      return 'generator';
    case FuelWithdrawPurpose.mayor:
      return 'mayor';
    case FuelWithdrawPurpose.other:
      return 'other';
  }
}

String fuelWithdrawPurposeLabelOf(FuelWithdrawPurpose purpose) {
  switch (purpose) {
    case FuelWithdrawPurpose.machine:
      return 'เติมเครื่องจักร (ถังสำรอง)';
    case FuelWithdrawPurpose.car:
      return 'รถยนต์';
    case FuelWithdrawPurpose.generator:
      return 'เครื่องปั่นไฟเล็ก';
    case FuelWithdrawPurpose.mayor:
      return 'นายกเบิก';
    case FuelWithdrawPurpose.other:
      return 'อื่นๆ';
  }
}

FuelWithdrawPurpose? fuelWithdrawPurposeFromCode(String? code) {
  switch ((code ?? '').trim().toLowerCase()) {
    case 'machine':
      return FuelWithdrawPurpose.machine;
    case 'car':
      return FuelWithdrawPurpose.car;
    case 'generator':
      return FuelWithdrawPurpose.generator;
    case 'mayor':
      return FuelWithdrawPurpose.mayor;
    case 'other':
      return FuelWithdrawPurpose.other;
    default:
      return null;
  }
}

bool fuelTypeIsBenzine(String? fuelType) =>
    (fuelType ?? '').trim().toLowerCase() == 'benzine';

/// normalize รหัสถัง — ค่าว่าง/legacy = ถังหลัก
String normalizeFuelTank(String? raw) {
  final v = (raw ?? '').trim().toLowerCase();
  if (v == kFuelTankReserve || v == 'สำรอง') return kFuelTankReserve;
  return kFuelTankMain;
}

/// แถวบันทึกการใช้น้ำมันรถแม็คโคร (`subCategory == VehicleUsage` เท่านั้น)
///
/// ไม่ใช้ตัวจำแนกกว้าง `isFuelVehicleUsageRow` (นับทุก stock_out ที่มีรถ)
/// เพื่อไม่ให้แถวอื่นที่มีชื่อรถไปหักถังหลักซ้ำ
bool isFuelMacroVehicleUsageRow(AppTransaction t) {
  if (!_isFuelExpenseRow(t)) return false;
  return (t.subCategory ?? '').trim() == kFuelVehicleUsageSubCategory;
}

/// ถังที่ใช้คิดยอดการใช้น้ำมัน
///
/// แถว `VehicleUsage` ที่ไม่ระบุถัง (แอปเก่า) = ถังสำรอง
/// ตรงกับค่าเริ่มต้นของฟอร์มแม็คโคร — ประเภทอื่นที่ว่าง = ถังหลัก
String fuelUsageTankOf(AppTransaction t) {
  final raw = (t.fuelTank ?? '').trim();
  if (raw.isNotEmpty) return normalizeFuelTank(raw);
  if (isFuelMacroVehicleUsageRow(t)) {
    return kFuelTankReserve;
  }
  return kFuelTankMain;
}

bool fuelTankIsReserve(String? raw) => normalizeFuelTank(raw) == kFuelTankReserve;

String fuelTankLabelOf(String? raw) =>
    fuelTankIsReserve(raw) ? 'ถังสำรอง' : 'ถังหลัก';

double fuelTankCapacityOf(String? raw) => fuelTankIsReserve(raw)
    ? kFuelTankCapacityReserveLiters
    : kFuelTankCapacityMainLiters;

/// ปริมาณน้ำมันของแถวเป็นลิตร — รองรับหน่วยแกลลอนเหมือน `fuelTxToLiters` บนเว็บ
double fuelTxLiters(AppTransaction t) {
  final q = (t.quantity ?? 0).toDouble();
  if (q == 0) return 0;
  final unit = (t.unit ?? 'L').trim().toLowerCase();
  if (unit == 'gallon' || unit == 'แกลลอน') return q * 3.785411784;
  return q;
}

bool _isFuelExpenseRow(AppTransaction t) =>
    t.category == 'Fuel' && t.type.trim().toLowerCase() == 'expense';

/// แถวรับน้ำมันเข้าถัง — สอดคล้อง `inferFuelMovement` บนเว็บ (ข้อมูลเก่าที่ไม่มีรถ = รับเข้า)
bool isFuelStockInRow(AppTransaction t) {
  if (!_isFuelExpenseRow(t)) return false;
  final mov = (t.fuelMovement ?? '').trim().toLowerCase();
  if (mov == 'stock_in') return true;
  if (mov == 'stock_out') return false;
  return !transactionHasVehicle(t);
}

/// แถวเบิกน้ำมันออกจากถัง (เมนู «เบิกน้ำมัน»)
bool isFuelWithdrawRow(AppTransaction t) {
  if (!_isFuelExpenseRow(t)) return false;
  if ((t.subCategory ?? '').trim() != kFuelWithdrawSubCategory) return false;
  return !isFuelStockInRow(t);
}

bool isFuelTransferRow(AppTransaction t) {
  if (!_isFuelExpenseRow(t)) return false;
  return (t.subCategory ?? '').trim() == kFuelTransferSubCategory;
}

bool isFuelSandSieveRow(AppTransaction t) {
  if (!_isFuelExpenseRow(t)) return false;
  return (t.subCategory ?? '').trim() == kFuelSandSieveSubCategory;
}

/// รหัสวัตถุประสงค์ของแถวเบิกน้ำมัน (`machine` | `car` | `generator` | `mayor` | `other`)
String? fuelWithdrawPurposeCode(AppTransaction t) {
  if (!isFuelWithdrawRow(t)) return null;
  final code = (t.workType ?? '').trim().toLowerCase();
  return code.isEmpty ? null : code;
}

/// แถวเติมน้ำมันรถยนต์ (เมนู «เติมน้ำมันรถยนต์»)
bool isFuelCarFillRow(AppTransaction t) {
  if (!isFuelWithdrawRow(t)) return false;
  return fuelWithdrawPurposeCode(t) == 'car';
}

const Set<String> _kFuelCarFillKnownVehicleIds = {
  kFuelCarFillMighty,
  kFuelCarFillTaplien,
  ...kFuelCarFillTaplienLegacyIds,
  kFuelCarFillAhming,
};

bool isKnownFuelCarFillVehicleId(String? vehicleId) {
  final v = (vehicleId ?? '').trim();
  return v.isNotEmpty && _kFuelCarFillKnownVehicleIds.contains(v);
}

/// แมป `vehicleId` ที่บันทึก → enum เมนูเติมรถยนต์ (ไม่รู้จัก = other)
FuelCarFillVehicle fuelCarFillVehicleFromId(String? vehicleId) {
  final v = (vehicleId ?? '').trim();
  if (v == kFuelCarFillMighty) return FuelCarFillVehicle.mighty;
  if (_isTaplienVehicleId(v)) return FuelCarFillVehicle.taplien;
  if (v == kFuelCarFillAhming) return FuelCarFillVehicle.ahming;
  return FuelCarFillVehicle.other;
}

/// เทียบ `vehicleId` ที่บันทึก — รองรับชื่อเก่า/ใหม่ของรถตาเปลื่ยน
bool fuelCarFillVehicleIdMatches(String rowVehicleId, String wantVehicleId) {
  final a = rowVehicleId.trim();
  final b = wantVehicleId.trim();
  if (a == b) return true;
  if (a.isEmpty || b.isEmpty) return false;
  return isKnownFuelCarFillVehicleId(a) &&
      isKnownFuelCarFillVehicleId(b) &&
      fuelCarFillVehicleFromId(a) == fuelCarFillVehicleFromId(b);
}

String _stripFuelRecorderSuffix(String raw) =>
    raw.replaceAll(RegExp(r'\s*\(ผู้กรอก:[^)]+\)\s*$'), '').trim();

/// สรุปสั้นสำหรับไทล์เมนู / ฟอร์มเมื่อมีรายการของวันนี้แล้ว
String fuelExistingEntrySummary(AppTransaction? t) {
  if (t == null) return '';
  final liters = fuelTxLiters(t);
  final time = _stripFuelRecorderSuffix(t.workDetails ?? '');
  final parts = <String>['มีข้อมูลแล้ว'];
  if (liters > 0) parts.add('${formatFuelLiters(liters)} ลิตร');
  if (time.isNotEmpty) parts.add(time);
  return parts.join(' · ');
}

int _fuelRowRecencyMs(AppTransaction t) =>
    t.createdAt?.millisecondsSinceEpoch ?? 0;

AppTransaction? _latestFuelRow(Iterable<AppTransaction> rows) {
  AppTransaction? best;
  var bestMs = -1;
  for (final t in rows) {
    final ms = _fuelRowRecencyMs(t);
    if (best == null || ms >= bestMs) {
      best = t;
      bestMs = ms;
    }
  }
  return best;
}

/// รายการเติมน้ำมันรถยนต์ล่าสุดของวันนั้นสำหรับคันที่เลือก
///
/// [vehicleId] ว่าง = กลุ่ม «อื่นๆ» (ไม่ใช่ 3 คันหลัก)
AppTransaction? latestFuelCarFillForVehicle({
  required String dayYmd,
  required Iterable<AppTransaction> transactions,
  required String vehicleId,
}) {
  final day = dayYmd.trim();
  final vid = vehicleId.trim();
  final wantOther = vid.isEmpty;
  final matches = <AppTransaction>[];
  for (final t in transactions) {
    if (t.date.trim() != day) continue;
    if (!isFuelCarFillRow(t)) continue;
    final rowVid = transactionVehicleLabel(t);
    if (wantOther) {
      if (rowVid.isEmpty || isKnownFuelCarFillVehicleId(rowVid)) continue;
    } else if (!fuelCarFillVehicleIdMatches(rowVid, vid)) {
      continue;
    }
    matches.add(t);
  }
  return _latestFuelRow(matches);
}

/// แถวเติมน้ำมันรถตาเปลื่ยนล่าสุดของวัน (รวมชื่อเก่า/ใหม่)
AppTransaction? latestFuelTaplienFillForDay({
  required String dayYmd,
  required Iterable<AppTransaction> transactions,
}) {
  return latestFuelCarFillForVehicle(
    dayYmd: dayYmd,
    transactions: transactions,
    vehicleId: kFuelCarFillTaplien,
  );
}

/// แถวเบิก/โอนล่าสุดของวันตามวัตถุประสงค์ (ไม่รวม car)
///
/// เครื่องจักรใช้แถว Transfer ที่ `stock_out` (โอนออกจากถังหลัก)
AppTransaction? latestFuelWithdrawForPurpose({
  required String dayYmd,
  required Iterable<AppTransaction> transactions,
  required FuelWithdrawPurpose purpose,
}) {
  if (purpose == FuelWithdrawPurpose.car) return null;
  final day = dayYmd.trim();
  final code = fuelWithdrawPurposeCodeOf(purpose);
  final matches = <AppTransaction>[];
  for (final t in transactions) {
    if (t.date.trim() != day) continue;
    if (purpose == FuelWithdrawPurpose.machine) {
      if (!isFuelTransferRow(t)) continue;
      if ((t.workType ?? '').trim().toLowerCase() != 'machine') continue;
      if ((t.fuelMovement ?? '').trim().toLowerCase() != 'stock_out') continue;
      matches.add(t);
      continue;
    }
    if (!isFuelWithdrawRow(t)) continue;
    if (fuelWithdrawPurposeCode(t) != code) continue;
    matches.add(t);
  }
  return _latestFuelRow(matches);
}

/// แถวรับเข้าถังหลักล่าสุดของวัน (ไม่รวมโอน Transfer เข้าสำรอง)
AppTransaction? latestFuelStockInForDay({
  required String dayYmd,
  required Iterable<AppTransaction> transactions,
}) {
  final day = dayYmd.trim();
  final matches = <AppTransaction>[];
  for (final t in transactions) {
    if (t.date.trim() != day) continue;
    if (!isFuelStockInRow(t)) continue;
    if (isFuelTransferRow(t)) continue;
    matches.add(t);
  }
  return _latestFuelRow(matches);
}

/// แถวเติมน้ำมันรถยนต์ล่าสุดของวัน (ทุกคัน)
AppTransaction? latestFuelCarFillForDay({
  required String dayYmd,
  required Iterable<AppTransaction> transactions,
}) {
  final day = dayYmd.trim();
  final matches = <AppTransaction>[];
  for (final t in transactions) {
    if (t.date.trim() != day) continue;
    if (!isFuelCarFillRow(t)) continue;
    matches.add(t);
  }
  return _latestFuelRow(matches);
}

/// แถวเบิก/โอนล่าสุดของวัน (ทุกวัตถุประสงค์ ยกเว้น car)
AppTransaction? latestFuelWithdrawForDay({
  required String dayYmd,
  required Iterable<AppTransaction> transactions,
}) {
  const purposes = [
    FuelWithdrawPurpose.machine,
    FuelWithdrawPurpose.generator,
    FuelWithdrawPurpose.mayor,
  ];
  final matches = <AppTransaction>[];
  for (final purpose in purposes) {
    final hit = latestFuelWithdrawForPurpose(
      dayYmd: dayYmd,
      transactions: transactions,
      purpose: purpose,
    );
    if (hit != null) matches.add(hit);
  }
  final taplien = latestFuelTaplienFillForDay(
    dayYmd: dayYmd,
    transactions: transactions,
  );
  if (taplien != null) matches.add(taplien);
  return _latestFuelRow(matches);
}

/// สรุปต่อเมนูย่อยน้ำมันสำหรับหน้าเลือก — ว่าง = ยังไม่มีข้อมูลวันนี้
class FuelSubModeDaySummaries {
  const FuelSubModeDaySummaries({
    this.stockIn = '',
    this.withdraw = '',
    this.carFill = '',
    this.macroUsage = '',
  });

  final String stockIn;
  final String withdraw;
  final String carFill;
  final String macroUsage;
}

FuelSubModeDaySummaries buildFuelSubModeDaySummaries({
  required String dayYmd,
  required Iterable<AppTransaction> transactions,
}) {
  final stock = latestFuelStockInForDay(
    dayYmd: dayYmd,
    transactions: transactions,
  );
  final withdraw = latestFuelWithdrawForDay(
    dayYmd: dayYmd,
    transactions: transactions,
  );
  final car = latestFuelCarFillForDay(
    dayYmd: dayYmd,
    transactions: transactions,
  );
  final coverage = fuelVehicleCoverageForDay(dayYmd, transactions);
  var macro = '';
  if (coverage.fueledCount > 0) {
    macro =
        'มีข้อมูลแล้ว · ${coverage.fueledCount} คัน · '
        '${formatFuelLiters(coverage.liters)} ลิตร';
  }
  return FuelSubModeDaySummaries(
    stockIn: fuelExistingEntrySummary(stock),
    withdraw: fuelExistingEntrySummary(withdraw),
    carFill: fuelExistingEntrySummary(car),
    macroUsage: macro,
  );
}

/// คู่โอนหลัก→สำรองที่จับคู่ด้วย note `xfer:...` ของแถว stock_out
({AppTransaction? outTx, AppTransaction? inTx}) fuelMachineTransferPair({
  required AppTransaction outTx,
  required Iterable<AppTransaction> transactions,
}) {
  final note = (outTx.note ?? '').trim();
  if (!note.startsWith('xfer:')) {
    return (outTx: outTx, inTx: null);
  }
  AppTransaction? inTx;
  for (final t in transactions) {
    if (t.id == outTx.id) continue;
    if (!isFuelTransferRow(t)) continue;
    if ((t.note ?? '').trim() != note) continue;
    if ((t.fuelMovement ?? '').trim().toLowerCase() != 'stock_in') continue;
    inTx = t;
    break;
  }
  return (outTx: outTx, inTx: inTx);
}

class FuelStockBalance {
  const FuelStockBalance({
    required this.mainDiesel,
    required this.reserveDiesel,
    this.mainBenzine = 0,
    this.reserveBenzine = 0,
  });

  final double mainDiesel;
  final double reserveDiesel;
  final double mainBenzine;
  final double reserveBenzine;

  /// ความเข้ากันได้ — ดีเซลถังหลัก
  double get diesel => mainDiesel;

  /// ความเข้ากันได้ — เบนซินถังหลัก
  double get benzine => mainBenzine;

  double dieselForTank(String? tank) =>
      fuelTankIsReserve(tank) ? reserveDiesel : mainDiesel;

  double benzineForTank(String? tank) =>
      fuelTankIsReserve(tank) ? reserveBenzine : mainBenzine;

  double forFuelType(String? fuelType, {String? tank}) {
    final reserve = fuelTankIsReserve(tank);
    if (fuelTypeIsBenzine(fuelType)) {
      return reserve ? reserveBenzine : mainBenzine;
    }
    return reserve ? reserveDiesel : mainDiesel;
  }

  /// ลิตรที่ถังสำรองติดลบ (0 ถ้าไม่ติดลบ) — ใช้เตือนว่าขาดบันทึกโอน
  double get reserveShortfallLiters =>
      (reserveDiesel < 0 ? -reserveDiesel : 0) +
      (reserveBenzine < 0 ? -reserveBenzine : 0);
}

class _FuelDayBucket {
  double stockIn = 0;
  double withdraw = 0;
}

List<String> _sandLapTimes(AppTransaction t) {
  final raw = t.workAssignments?['lapTimes'];
  if (raw == null || raw.isEmpty) return const [];
  return [
    for (final e in raw)
      if (e.trim().isNotEmpty) e.trim(),
  ];
}

bool _isDailyLogSandRow(AppTransaction t) =>
    t.category == 'DailyLog' && (t.subCategory ?? '').trim() == 'Sand';

/// คงเหลือแยกถังหลัก/สำรอง
///
/// แต่ละแถวหัก/เติมถังของตัวเอง — ไม่หักล้างข้ามแถว
/// `delta = stockIn − withdraw`
///
/// รายการก่อน [kFuelStockCutoverYmd] ไม่ถูกนับ — ยอดก่อนหน้า = 0
/// แถว `VehicleUsage` ไม่ระบุถัง → ถังสำรอง; ประเภทอื่นไม่ระบุ → ถังหลัก
FuelStockBalance computeFuelStockBalance(
  Iterable<AppTransaction> transactions, {
  double openingDiesel = 0,
  double openingBenzine = 0,
  double openingReserveDiesel = 0,
  double openingReserveBenzine = 0,
}) {
  final buckets = <String, _FuelDayBucket>{};
  _FuelDayBucket bucketFor(String date, String tank, bool benzine) =>
      buckets.putIfAbsent(
        '$date|$tank|${benzine ? 'B' : 'D'}',
        () => _FuelDayBucket(),
      );

  final sandSieveDays = <String>{};
  final transferMachineDays = <String>{};
  final sandByDay = <String, AppTransaction>{};

  for (final t in transactions) {
    final day = t.date.trim();
    if (day.compareTo(kFuelStockCutoverYmd) < 0) continue;
    if (isFuelSandSieveRow(t)) sandSieveDays.add(day);
    if (isFuelTransferRow(t) &&
        (t.workType ?? '').trim().toLowerCase() == 'machine') {
      transferMachineDays.add(day);
    }
    if (_isDailyLogSandRow(t)) {
      final laps = _sandLapTimes(t);
      if (laps.isNotEmpty) {
        final prev = sandByDay[day];
        final prevLen = prev == null ? 0 : _sandLapTimes(prev).length;
        if (laps.length >= prevLen) sandByDay[day] = t;
      }
    }
  }

  for (final t in transactions) {
    if (!_isFuelExpenseRow(t)) continue;
    final day = t.date.trim();
    if (day.compareTo(kFuelStockCutoverYmd) < 0) continue;
    final liters = fuelTxLiters(t);
    if (liters <= 0) continue;
    final tank = fuelUsageTankOf(t);
    final benzine = fuelTypeIsBenzine(t.fuelType);
    final bucket = bucketFor(day, tank, benzine);
    if (isFuelStockInRow(t)) {
      bucket.stockIn += liters;
      continue;
    }
    if (isFuelWithdrawRow(t)) {
      bucket.withdraw += liters;
      // แอปเก่า: เบิกเติมเครื่องจักรเป็นแถวเดียว — ตีความเป็นโอนหลัก→สำรอง
      if (fuelWithdrawPurposeCode(t) == 'machine' &&
          !transferMachineDays.contains(day)) {
        bucketFor(day, kFuelTankReserve, benzine).stockIn += liters;
      }
      continue;
    }
    if (isFuelSandSieveRow(t) || isFuelTransferRow(t)) {
      bucket.withdraw += liters;
      continue;
    }
    if (isFuelMacroVehicleUsageRow(t)) {
      // หักเฉพาะถังที่ติดป้าย (สำรอง/หลัก) — ไม่หักข้ามถัง
      bucket.withdraw += liters;
      continue;
    }
    // ไม่นับ stock_out ทั่วไปที่มีชื่อรถเป็นแม็คโคร
    // (กันแถวอื่นไปหักถังหลักซ้ำ)
  }

  for (final entry in sandByDay.entries) {
    if (sandSieveDays.contains(entry.key)) continue;
    final laps = _sandLapTimes(entry.value);
    final hours =
        computeSandWorkDurationSummary(laps, entry.key)?.totalActiveHours ?? 0;
    if (hours <= 0) continue;
    final liters = double.parse(
      (hours * kFuelSandSieveLitersPerHour).toStringAsFixed(2),
    );
    if (liters <= 0) continue;
    bucketFor(entry.key, kFuelTankReserve, false).withdraw += liters;
  }

  var mainDiesel = openingDiesel;
  var mainBenzine = openingBenzine;
  var reserveDiesel = openingReserveDiesel;
  var reserveBenzine = openingReserveBenzine;
  for (final entry in buckets.entries) {
    final b = entry.value;
    final delta = b.stockIn - b.withdraw;
    final parts = entry.key.split('|');
    final tank = parts.length >= 2 ? parts[1] : kFuelTankMain;
    final isBenzine = entry.key.endsWith('|B');
    if (tank == kFuelTankReserve) {
      if (isBenzine) {
        reserveBenzine += delta;
      } else {
        reserveDiesel += delta;
      }
    } else if (isBenzine) {
      mainBenzine += delta;
    } else {
      mainDiesel += delta;
    }
  }
  return FuelStockBalance(
    mainDiesel: mainDiesel,
    reserveDiesel: reserveDiesel,
    mainBenzine: mainBenzine,
    reserveBenzine: reserveBenzine,
  );
}

/// ยอดกระทบกันของวันเดียว — เบิกเพื่อเครื่องจักร vs ที่ลงบันทึกใช้รถแล้ว
/// [tank] null = รวมทุกถัง; ระบุแล้วคิดเฉพาะถังนั้น
/// ยอดกระทบกันของวันเดียว — โอนเข้าถังสำรอง vs ที่ลงบันทึกใช้แม็คโครแล้ว
/// [tank] null = รวมทุกถังสำหรับฝั่งใช้; ระบุแล้วคิดเฉพาะถังนั้น (แนะนำ `reserve`)
({double machineWithdraw, double vehicleUsage, double remaining})
fuelMachineReconcileForDay(
  String dayKey,
  Iterable<AppTransaction> transactions, {
  String? tank,
}) {
  final day = dayKey.trim();
  final filterTank = tank == null ? null : normalizeFuelTank(tank);
  var machineWithdraw = 0.0;
  var vehicleUsage = 0.0;
  for (final t in transactions) {
    if (t.date.trim() != day) continue;
    if (!_isFuelExpenseRow(t)) continue;
    final liters = fuelTxLiters(t);
    if (liters <= 0) continue;
    if (isFuelWithdrawRow(t)) {
      if (fuelWithdrawPurposeCode(t) == 'machine') machineWithdraw += liters;
      continue;
    }
    if (isFuelTransferRow(t) &&
        (t.workType ?? '').trim().toLowerCase() == 'machine') {
      // นับเฉพาะฝั่งออกจากถังหลัก — ไม่นับคู่รับเข้าสำรองซ้ำ
      if (!isFuelStockInRow(t)) machineWithdraw += liters;
      continue;
    }
    if (isFuelMacroVehicleUsageRow(t)) {
      if (filterTank != null && fuelUsageTankOf(t) != filterTank) continue;
      vehicleUsage += liters;
    }
  }
  final remaining = machineWithdraw - vehicleUsage;
  return (
    machineWithdraw: machineWithdraw,
    vehicleUsage: vehicleUsage,
    remaining: remaining > 0 ? remaining : 0,
  );
}

/// จัดรูปตัวเลขลิตร — ตัด `.0` ทิ้งเมื่อเป็นจำนวนเต็ม
String formatFuelLiters(double liters) {
  if (liters % 1 == 0) return liters.toStringAsFixed(0);
  return liters.toStringAsFixed(2);
}

/// ตรวจว่าบันทึกการใช้ได้เมื่อเทียบกับคงเหลือถัง
///
/// [available] = คงเหลือถัง + ลิตรของแถวเดิมที่กำลังแก้ (ถังเดียวกัน)
/// ถ้าไม่เพิ่มปริมาณจากแถวเดิม อนุญาตแม้ [available] ติดลบ
bool fuelUsageStockAllowsSave({
  required double liters,
  required double available,
  required double priorLitersSameTank,
}) {
  if (liters <= priorLitersSameTank + 1e-9) return true;
  return liters <= available + 1e-9;
}

FuelStockBalance _fuelBalanceAdd(
  FuelStockBalance b, {
  required String tank,
  required bool benzine,
  required double delta,
}) {
  final reserve = fuelTankIsReserve(tank);
  if (benzine) {
    return FuelStockBalance(
      mainDiesel: b.mainDiesel,
      reserveDiesel: b.reserveDiesel,
      mainBenzine: reserve ? b.mainBenzine : b.mainBenzine + delta,
      reserveBenzine: reserve ? b.reserveBenzine + delta : b.reserveBenzine,
    );
  }
  return FuelStockBalance(
    mainDiesel: reserve ? b.mainDiesel : b.mainDiesel + delta,
    reserveDiesel: reserve ? b.reserveDiesel + delta : b.reserveDiesel,
    mainBenzine: b.mainBenzine,
    reserveBenzine: b.reserveBenzine,
  );
}

/// อัปเดตคงเหลือจากแถวเดียวโดยไม่สแกนทั้งลิสต์
FuelStockBalance? applyFuelBalanceDelta(
  FuelStockBalance current,
  AppTransaction t, {
  bool reverse = false,
}) {
  if (!_isFuelExpenseRow(t)) return current;
  final day = t.date.trim();
  if (day.compareTo(kFuelStockCutoverYmd) < 0) return current;
  final liters = fuelTxLiters(t);
  if (liters <= 0) return current;
  final signed = reverse ? -liters : liters;
  final tank = fuelUsageTankOf(t);
  final benzine = fuelTypeIsBenzine(t.fuelType);

  if (isFuelStockInRow(t)) {
    return _fuelBalanceAdd(
      current,
      tank: tank,
      benzine: benzine,
      delta: signed,
    );
  }
  if (isFuelWithdrawRow(t)) {
    // เบิกเครื่องจักรแบบเก่าต้องดูว่าวันนั้นมี Transfer หรือไม่
    // — ใช้สแกนเต็มใน computeFuelStockBalance แทน
    if (fuelWithdrawPurposeCode(t) == 'machine') return null;
    return _fuelBalanceAdd(
      current,
      tank: tank,
      benzine: benzine,
      delta: -signed,
    );
  }
  if (isFuelSandSieveRow(t) ||
      isFuelTransferRow(t) ||
      isFuelMacroVehicleUsageRow(t)) {
    // Transfer stock_in ถูกจับที่ isFuelStockInRow แล้ว
    // VehicleUsage หักเฉพาะถังที่ติดป้าย
    return _fuelBalanceAdd(
      current,
      tank: tank,
      benzine: benzine,
      delta: -signed,
    );
  }
  return current;
}

/// id คงที่ของแถวใช้น้ำมันร่อนทรายอัตโนมัติรายวัน
String fuelSandSieveTxId(String dateYmd) => '${dateYmd.trim()}_fuel_sand_sieve';
