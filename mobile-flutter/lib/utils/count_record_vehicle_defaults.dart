import '../models/app_transaction.dart';
import '../models/employee.dart';
import 'daily_module_transactions.dart';

String compactVehicleLabel(String raw) {
  return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
}

bool vehicleIdsLikelyMatch(String a, String b) {
  final ca = compactVehicleLabel(a);
  final cb = compactVehicleLabel(b);
  if (ca.isEmpty || cb.isEmpty) return false;
  if (ca == cb) return true;
  return ca.contains(cb) || cb.contains(ca);
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

/// คนขับเริ่มต้น: 1) จากเว็บ (vehicleDefaultDrivers) 2) จากประวัติเที่ยว
String? resolveCountRecordDefaultDriverId({
  required String vehicleId,
  required Iterable<Employee> drivers,
  required Iterable<AppTransaction> tripHistory,
  Map<String, String>? vehicleDefaultDrivers,
}) {
  final vehicle = vehicleId.trim();
  if (vehicle.isEmpty) return null;

  final configuredId = vehicleDefaultDrivers?[vehicle]?.trim();
  if (configuredId != null &&
      configuredId.isNotEmpty &&
      drivers.any((e) => e.id == configuredId)) {
    return configuredId;
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
  Map<String, String>? vehicleDefaultDrivers,
}) {
  if (drivers.length <= 1) return List<Employee>.from(drivers);
  final defaultId = resolveCountRecordDefaultDriverId(
    vehicleId: vehicleId,
    drivers: drivers,
    tripHistory: tripHistory,
    vehicleDefaultDrivers: vehicleDefaultDrivers,
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

/// เรียงรถ: ความถี่เที่ยวก่อน แล้วตามลำดับในรายการจากเว็บ (cars)
List<String> sortCountRecordVehicles({
  required List<String> cars,
  required Iterable<AppTransaction> tripHistory,
}) {
  if (cars.length <= 1) return List<String>.from(cars);

  final index = {for (var i = 0; i < cars.length; i++) cars[i]: i};
  final sorted = List<String>.from(cars);
  sorted.sort((a, b) {
    final fa = countVehicleTripHistory(a, tripHistory);
    final fb = countVehicleTripHistory(b, tripHistory);
    if (fa != fb) return fb.compareTo(fa);

    return (index[a] ?? 0).compareTo(index[b] ?? 0);
  });
  return sorted;
}
