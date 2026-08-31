import '../models/app_transaction.dart';
import '../models/employee.dart';
import 'count_record_vehicle_defaults.dart';
import 'daily_module_transactions.dart';

class VehicleCatalogRow {
  const VehicleCatalogRow({
    required this.id,
    required this.name,
    this.defaultDriverId,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String? defaultDriverId;
  final int sortOrder;

  factory VehicleCatalogRow.fromMap(Map<String, dynamic> row) {
    return VehicleCatalogRow(
      id: (row['id'] ?? '').toString().trim(),
      name: (row['name'] ?? '').toString().trim(),
      defaultDriverId: () {
        final d = (row['default_driver_id'] ?? '').toString().trim();
        return d.isEmpty ? null : d;
      }(),
      sortOrder: () {
        final v = row['sort_order'];
        if (v is num) return v.toInt();
        return int.tryParse('$v') ?? 0;
      }(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'default_driver_id': defaultDriverId,
        'sort_order': sortOrder,
      };
}

class VehicleCatalog {
  const VehicleCatalog(this.rows);

  final List<VehicleCatalogRow> rows;

  static const empty = VehicleCatalog([]);

  List<String> get names =>
      rows.map((r) => r.name).where((n) => n.isNotEmpty).toList();

  Map<String, String> get defaultDriversByName {
    final out = <String, String>{};
    for (final r in rows) {
      final d = (r.defaultDriverId ?? '').trim();
      if (r.name.isEmpty || d.isEmpty) continue;
      out[r.name] = d;
    }
    return out;
  }

  VehicleCatalogRow? findByNameOrId(String raw) {
    final key = raw.trim();
    if (key.isEmpty) return null;
    for (final r in rows) {
      if (r.id == key || r.name == key) return r;
    }
    // เทียบแบบไม่สนช่องว่างเท่านั้น — ไม่ใช้ contains (กันชื่อซ้อน/คันคู่)
    for (final r in rows) {
      if (vehicleIdsLikelyMatch(r.name, key) ||
          vehicleIdsLikelyMatch(r.id, key)) {
        return r;
      }
    }
    return null;
  }
}

bool _looksLikeCatalogVehicleId(String raw) {
  final s = raw.trim();
  return s.startsWith('v_') && s.length >= 4;
}

String employeeDisplayName(Employee e) {
  final nick = e.nickname.trim();
  if (nick.isNotEmpty) return nick;
  return e.name.trim();
}

String? driverDisplayNameForId(String driverId, Iterable<Employee> employees) {
  final id = driverId.trim();
  if (id.isEmpty) return null;
  for (final e in employees) {
    if (e.id.trim() == id) {
      final n = employeeDisplayName(e);
      return n.isEmpty ? null : n;
    }
  }
  return null;
}

/// ติดรหัส/ชื่อรถและคนขับก่อนบันทึกลงฐาน
AppTransaction stampVehicleAndDriverNames(
  AppTransaction t, {
  VehicleCatalog catalog = VehicleCatalog.empty,
  Iterable<Employee> employees = const [],
}) {
  final rawVehicle = transactionVehicleLabel(t);
  final hit = catalog.findByNameOrId(rawVehicle.isEmpty
      ? (t.vehicleId ?? '')
      : rawVehicle);
  var vehicleId = (t.vehicleId ?? '').trim();
  var vehicleName = (t.vehicleName ?? '').trim();
  if (hit != null) {
    vehicleId = hit.id;
    vehicleName = hit.name;
  } else if (vehicleName.isEmpty &&
      vehicleId.isNotEmpty &&
      !_looksLikeCatalogVehicleId(vehicleId)) {
    vehicleName = vehicleId;
  }

  final driverId = (t.driverId ?? '').trim();
  var driverName = (t.driverName ?? '').trim();
  if (driverName.isEmpty && driverId.isNotEmpty) {
    driverName = driverDisplayNameForId(driverId, employees) ?? '';
  }

  if (vehicleId == (t.vehicleId ?? '').trim() &&
      vehicleName == (t.vehicleName ?? '').trim() &&
      driverName == (t.driverName ?? '').trim()) {
    return t;
  }
  return t.copyWith(
    vehicleId: vehicleId.isEmpty ? t.vehicleId : vehicleId,
    vehicleName: vehicleName.isEmpty ? t.vehicleName : vehicleName,
    driverName: driverName.isEmpty ? t.driverName : driverName,
  );
}
