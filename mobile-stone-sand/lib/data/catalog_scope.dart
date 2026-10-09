import 'package:flutter/widgets.dart';

import '../models/models.dart';
import 'catalog_repo.dart';
import 'db.dart';
import 'drivers_repo.dart';

/// Products, tambon zones, drivers and settings shared by every screen.
class CatalogController extends ChangeNotifier {
  List<Product> products = const [];
  List<Zone> zones = const [];
  List<Driver> drivers = const [];
  AppSettings settings = const AppSettings();
  bool loading = true;
  String error = '';

  Future<void> reload() async {
    loading = true;
    error = '';
    notifyListeners();
    try {
      final results = await Future.wait([
        listProducts(),
        listZones(),
        listDrivers(includeInactive: true),
        getSettings(),
      ]);
      products = results[0] as List<Product>;
      zones = results[1] as List<Zone>;
      drivers = results[2] as List<Driver>;
      settings = results[3] as AppSettings;
    } catch (e) {
      error = errorText(e, 'โหลดข้อมูลหลักไม่สำเร็จ');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Zone? zoneById(String? id) => id == null ? null : _find(zones, (z) => z.id == id);
  Zone? zoneByName(String? name) => name == null ? null : _find(zones, (z) => z.name == name);
  Driver? driverById(String? id) => id == null ? null : _find(drivers, (d) => d.id == id);

  static T? _find<T>(List<T> list, bool Function(T) test) {
    for (final x in list) {
      if (test(x)) return x;
    }
    return null;
  }
}

class CatalogScope extends InheritedNotifier<CatalogController> {
  const CatalogScope({super.key, required CatalogController controller, required super.child})
      : super(notifier: controller);

  static CatalogController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CatalogScope>()!.notifier!;

  static CatalogController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CatalogScope>()!.notifier!;
}
