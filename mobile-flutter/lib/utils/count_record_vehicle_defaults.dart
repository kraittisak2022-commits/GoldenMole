import '../models/app_transaction.dart';
import '../models/employee.dart';
import 'daily_module_transactions.dart';

/// คีย์รถ (compact) → ชื่อเล่นคนขับประจำรถ
const _kVehicleDriverNicknameByKey = <String, String>{
  'โอเว่น': 'พี่นุ',
  'ลุงศักดิ์': 'เดี่ยว',
  'พี่โก': 'พี่ถุ่ย',
  'พ่อเลี้ยงตุ๋ย': 'พี่เอก',
  'ดรัมนายกพนม': 'ใหญ่',
  'สิบล้อนายกพนม': 'พี่สัน',
  'โอ๊ต': 'พี่ฤทธิ์',
};

/// ลำดับรถเริ่มต้นเมื่อความถี่เท่ากัน (มาทำงานบ่อยสุดก่อน)
const _kVehicleSortPriorityByKey = <String, int>{
  'โอเว่น': 0,
  'ลุงศักดิ์': 1,
  'พี่โก': 2,
  'พ่อเลี้ยงตุ๋ย': 3,
  'ดรัมนายกพนม': 4,
  'สิบล้อนายกพนม': 5,
  'โอ๊ต': 6,
};

String compactVehicleLabel(String raw) {
  return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
}

String? vehicleDefaultKey(String vehicleId) {
  final compact = compactVehicleLabel(vehicleId);
  if (compact.isEmpty) return null;

  if (isSixOrTenWheelVehicleName(vehicleId) &&
      compact.contains('นายกพนม')) {
    return 'สิบล้อนายกพนม';
  }
  if (compact.contains('โอเว่น')) return 'โอเว่น';
  if (compact.contains('ลุงศักดิ์') || compact.contains('ลุงศักด')) {
    return 'ลุงศักดิ์';
  }
  if (compact.contains('พ่อเลี้ยงตุ๋ย') ||
      compact.contains('พ่อเลี้ยง')) {
    return 'พ่อเลี้ยงตุ๋ย';
  }
  if (compact.contains('พี่โก')) return 'พี่โก';
  if (compact.contains('โอ๊ต') || compact.contains('โอต')) return 'โอ๊ต';
  if (compact.contains('นายกพนม')) return 'ดรัมนายกพนม';
  return null;
}

String? defaultDriverNicknameForVehicle(String vehicleId) {
  final key = vehicleDefaultKey(vehicleId);
  if (key == null) return null;
  return _kVehicleDriverNicknameByKey[key];
}

int defaultVehicleSortPriority(String vehicleId) {
  final key = vehicleDefaultKey(vehicleId);
  if (key == null) return 999;
  return _kVehicleSortPriorityByKey[key] ?? 999;
}

bool vehicleIdsLikelyMatch(String a, String b) {
  final ca = compactVehicleLabel(a);
  final cb = compactVehicleLabel(b);
  if (ca.isEmpty || cb.isEmpty) return false;
  if (ca == cb) return true;
  return ca.contains(cb) || cb.contains(ca);
}

String? findDriverIdByNickname(
  Iterable<Employee> drivers,
  String nickname,
) {
  final target = nickname.trim();
  if (target.isEmpty) return null;

  Employee? exact;
  Employee? partial;
  for (final e in drivers) {
    final nick = e.nickname.trim();
    final name = e.name.trim();
    if (nick == target || name == target) {
      exact = e;
      break;
    }
    if (nick.contains(target) ||
        target.contains(nick) ||
        name.contains(target) ||
        target.contains(name)) {
      partial ??= e;
    }
  }
  final hit = exact ?? partial;
  return hit?.id;
}

String? inferDriverIdFromTripHistory({
  required String vehicleId,
  required Iterable<AppTransaction> tripHistory,
  required Iterable<Employee> drivers,
}) {
  final counts = <String, int>{};
  for (final t in tripHistory) {
    if (!transactionMatchesVehicleTripModuleList(t)) continue;
    final v = (t.vehicleId ?? '').trim();
    if (v.isEmpty || !vehicleIdsLikelyMatch(v, vehicleId)) continue;
    final driverId = (t.driverId ?? '').trim();
    if (driverId.isEmpty) continue;
    counts[driverId] = (counts[driverId] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;

  String? bestId;
  var bestCount = -1;
  for (final entry in counts.entries) {
    if (entry.value > bestCount) {
      bestCount = entry.value;
      bestId = entry.key;
    }
  }
  if (bestId != null && drivers.any((e) => e.id == bestId)) {
    return bestId;
  }
  return null;
}

String? resolveCountRecordDefaultDriverId({
  required String vehicleId,
  required Iterable<Employee> drivers,
  required Iterable<AppTransaction> tripHistory,
}) {
  final vehicle = vehicleId.trim();
  if (vehicle.isEmpty) return null;

  final mappedNick = defaultDriverNicknameForVehicle(vehicle);
  if (mappedNick != null) {
    final mappedId = findDriverIdByNickname(drivers, mappedNick);
    if (mappedId != null) return mappedId;
  }

  return inferDriverIdFromTripHistory(
    vehicleId: vehicle,
    tripHistory: tripHistory,
    drivers: drivers,
  );
}

String driverDisplayLabel(Employee e) =>
    e.nickname.trim().isNotEmpty ? e.nickname.trim() : e.name.trim();

/// เรียงคนขับ — คนขับประจำรถ (default) ขึ้นก่อน
List<Employee> orderDriversForVehicle({
  required String vehicleId,
  required List<Employee> drivers,
  required Iterable<AppTransaction> tripHistory,
}) {
  if (drivers.length <= 1) return List<Employee>.from(drivers);
  final defaultId = resolveCountRecordDefaultDriverId(
    vehicleId: vehicleId,
    drivers: drivers,
    tripHistory: tripHistory,
  );
  if (defaultId == null) return List<Employee>.from(drivers);

  final sorted = List<Employee>.from(drivers);
  sorted.sort((a, b) {
    if (a.id == defaultId) return -1;
    if (b.id == defaultId) return 1;
    return driverDisplayLabel(a).compareTo(driverDisplayLabel(b));
  });
  return sorted;
}

String driverDropdownLabel({
  required Employee driver,
  required String? defaultDriverId,
}) {
  final label = driverDisplayLabel(driver);
  if (defaultDriverId != null && driver.id == defaultDriverId) {
    return '$label (ค่าเริ่มต้น)';
  }
  return label;
}

int countVehicleTripHistory(
  String vehicleId,
  Iterable<AppTransaction> tripHistory,
) {
  var count = 0;
  for (final t in tripHistory) {
    if (!transactionMatchesVehicleTripModuleList(t)) continue;
    final v = (t.vehicleId ?? '').trim();
    if (v.isEmpty || !vehicleIdsLikelyMatch(v, vehicleId)) continue;
    count++;
  }
  return count;
}

List<String> sortCountRecordVehicles({
  required List<String> cars,
  required Iterable<AppTransaction> tripHistory,
}) {
  if (cars.length <= 1) return List<String>.from(cars);

  final sorted = List<String>.from(cars);
  sorted.sort((a, b) {
    final fa = countVehicleTripHistory(a, tripHistory);
    final fb = countVehicleTripHistory(b, tripHistory);
    if (fa != fb) return fb.compareTo(fa);

    final pa = defaultVehicleSortPriority(a);
    final pb = defaultVehicleSortPriority(b);
    if (pa != pb) return pa.compareTo(pb);

    return a.compareTo(b);
  });
  return sorted;
}
