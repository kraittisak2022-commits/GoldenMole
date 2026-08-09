import '../models/app_transaction.dart';
import 'daily_module_transactions.dart';

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
/// ตั้งแต่วันนี้หักลบจากถังปกติ · พ.ศ. 5 ส.ค. 2569 = ค.ศ. 2026-08-05
const String kFuelStockCutoverYmd = '2026-08-05';

/// `subCategory` ของแถวรับน้ำมันเข้าถัง (รถน้ำมันมาเติม)
const String kFuelStockInSubCategory = 'StockIn';

/// `subCategory` ของแถวเบิกน้ำมันออกจากถัง
const String kFuelWithdrawSubCategory = 'Withdraw';

/// `subCategory` ของคู่แถวโอนหลัก→สำรอง
const String kFuelTransferSubCategory = 'Transfer';

/// `subCategory` ของการใช้น้ำมันเครื่องร่อนทราย (อัตโนมัติ)
const String kFuelSandSieveSubCategory = 'SandSieve';

/// อัตราใช้น้ำมันเครื่องร่อนทราย (ลิตร/ชั่วโมง)
const double kFuelSandSieveLitersPerHour = 18;

/// วัตถุประสงค์การเบิกน้ำมันออกจากถัง
enum FuelWithdrawPurpose { machine, car, generator, other }

String fuelWithdrawPurposeCodeOf(FuelWithdrawPurpose purpose) {
  switch (purpose) {
    case FuelWithdrawPurpose.machine:
      return 'machine';
    case FuelWithdrawPurpose.car:
      return 'car';
    case FuelWithdrawPurpose.generator:
      return 'generator';
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
  return (t.vehicleId ?? '').trim().isEmpty;
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

/// รหัสวัตถุประสงค์ของแถวเบิกน้ำมัน (`machine` | `car` | `generator` | `other`)
String? fuelWithdrawPurposeCode(AppTransaction t) {
  if (!isFuelWithdrawRow(t)) return null;
  final code = (t.workType ?? '').trim().toLowerCase();
  return code.isEmpty ? null : code;
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
}

class _FuelDayBucket {
  double stockIn = 0;
  double withdraw = 0;
  double machineWithdraw = 0;
  double vehicleUsage = 0;
}

/// คงเหลือแยกถังหลัก/สำรอง
///
/// ต่อวันต่อถังต่อชนิดน้ำมัน:
/// `delta = stockIn − withdraw − max(0, vehicleUsage − machineWithdraw)`
///
/// รายการก่อน [kFuelStockCutoverYmd] ไม่ถูกนับ — ยอดก่อนหน้า = 0
/// แถวไม่มี `fuelTank` → ถือเป็นถังหลัก
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

  for (final t in transactions) {
    if (!_isFuelExpenseRow(t)) continue;
    final day = t.date.trim();
    if (day.compareTo(kFuelStockCutoverYmd) < 0) continue;
    final liters = fuelTxLiters(t);
    if (liters <= 0) continue;
    final tank = normalizeFuelTank(t.fuelTank);
    final bucket = bucketFor(day, tank, fuelTypeIsBenzine(t.fuelType));
    if (isFuelStockInRow(t)) {
      bucket.stockIn += liters;
      continue;
    }
    if (isFuelWithdrawRow(t)) {
      bucket.withdraw += liters;
      if (fuelWithdrawPurposeCode(t) == 'machine') {
        bucket.machineWithdraw += liters;
      }
      continue;
    }
    if (isFuelSandSieveRow(t) || isFuelTransferRow(t)) {
      // Transfer stock_out / SandSieve — หักเต็มจากถังนั้น
      bucket.withdraw += liters;
      // เติมเครื่องจักรผ่านโอนหลัก→สำรอง: นับโควตา machine บนถังหลัก
      if (isFuelTransferRow(t) &&
          (t.workType ?? '').trim().toLowerCase() == 'machine') {
        bucket.machineWithdraw += liters;
      }
      continue;
    }
    if (isFuelVehicleUsageRow(t)) {
      bucket.vehicleUsage += liters;
      continue;
    }
    // catch-all stock_out ที่ไม่ใช่ vehicle
    final mov = (t.fuelMovement ?? '').trim().toLowerCase();
    if (mov == 'stock_out') {
      bucket.withdraw += liters;
    }
  }

  var mainDiesel = openingDiesel;
  var mainBenzine = openingBenzine;
  var reserveDiesel = openingReserveDiesel;
  var reserveBenzine = openingReserveBenzine;
  for (final entry in buckets.entries) {
    final b = entry.value;
    final excess = b.vehicleUsage - b.machineWithdraw;
    final delta = b.stockIn - b.withdraw - (excess > 0 ? excess : 0);
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
    if (filterTank != null && normalizeFuelTank(t.fuelTank) != filterTank) {
      continue;
    }
    final liters = fuelTxLiters(t);
    if (liters <= 0) continue;
    if (isFuelWithdrawRow(t)) {
      if (fuelWithdrawPurposeCode(t) == 'machine') machineWithdraw += liters;
      continue;
    }
    if (isFuelTransferRow(t) &&
        (t.workType ?? '').trim().toLowerCase() == 'machine') {
      machineWithdraw += liters;
      continue;
    }
    if (isFuelVehicleUsageRow(t)) vehicleUsage += liters;
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

/// id คงที่ของแถวใช้น้ำมันร่อนทรายอัตโนมัติรายวัน
String fuelSandSieveTxId(String dateYmd) => '${dateYmd.trim()}_fuel_sand_sieve';
