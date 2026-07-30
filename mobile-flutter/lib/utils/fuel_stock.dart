import '../models/app_transaction.dart';
import 'daily_module_transactions.dart';

/// ความจุถังสต็อกน้ำมันที่หน้างาน (ลิตร)
const double kFuelTankCapacityLiters = 9000;

/// `subCategory` ของแถวรับน้ำมันเข้าถัง (รถน้ำมันมาเติม)
const String kFuelStockInSubCategory = 'StockIn';

/// `subCategory` ของแถวเบิกน้ำมันออกจากถัง
const String kFuelWithdrawSubCategory = 'Withdraw';

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
      return 'เติมเครื่องจักร';
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

/// รหัสวัตถุประสงค์ของแถวเบิกน้ำมัน (`machine` | `car` | `generator` | `other`)
String? fuelWithdrawPurposeCode(AppTransaction t) {
  if (!isFuelWithdrawRow(t)) return null;
  final code = (t.workType ?? '').trim().toLowerCase();
  return code.isEmpty ? null : code;
}

class FuelStockBalance {
  const FuelStockBalance({required this.diesel, required this.benzine});

  final double diesel;
  final double benzine;

  double forFuelType(String? fuelType) =>
      fuelTypeIsBenzine(fuelType) ? benzine : diesel;
}

class _FuelDayBucket {
  double stockIn = 0;
  double withdraw = 0;
  double machineWithdraw = 0;
  double vehicleUsage = 0;
}

/// คงเหลือในถัง = ยกมา + รับเข้า − เบิกออก − ส่วนที่เติมรถเกินโควตา «เติมเครื่องจักร» ของวันนั้น
///
/// น้ำมันที่ลงบันทึกการใช้รถแม็คโครถือว่าเบิกไปแล้วในกล่อง «เติมเครื่องจักร»
/// จึงหักกลบกันรายวันเพื่อไม่ให้ตัดสต็อกซ้ำ ส่วนที่เกินโควตายังตัดสต็อกตามจริง
FuelStockBalance computeFuelStockBalance(
  Iterable<AppTransaction> transactions, {
  double openingDiesel = 0,
  double openingBenzine = 0,
}) {
  final buckets = <String, _FuelDayBucket>{};
  _FuelDayBucket bucketFor(String date, bool benzine) => buckets.putIfAbsent(
    '$date|${benzine ? 'B' : 'D'}',
    () => _FuelDayBucket(),
  );

  for (final t in transactions) {
    if (!_isFuelExpenseRow(t)) continue;
    final liters = fuelTxLiters(t);
    if (liters <= 0) continue;
    final bucket = bucketFor(t.date.trim(), fuelTypeIsBenzine(t.fuelType));
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
    if (isFuelVehicleUsageRow(t)) {
      bucket.vehicleUsage += liters;
    }
  }

  var diesel = openingDiesel;
  var benzine = openingBenzine;
  for (final entry in buckets.entries) {
    final b = entry.value;
    final excess = b.vehicleUsage - b.machineWithdraw;
    final delta = b.stockIn - b.withdraw - (excess > 0 ? excess : 0);
    if (entry.key.endsWith('|B')) {
      benzine += delta;
    } else {
      diesel += delta;
    }
  }
  return FuelStockBalance(diesel: diesel, benzine: benzine);
}

/// ยอดกระทบกันของวันเดียว — เบิกเพื่อเครื่องจักร vs ที่ลงบันทึกใช้รถแล้ว
({double machineWithdraw, double vehicleUsage, double remaining})
fuelMachineReconcileForDay(
  String dayKey,
  Iterable<AppTransaction> transactions,
) {
  final day = dayKey.trim();
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
