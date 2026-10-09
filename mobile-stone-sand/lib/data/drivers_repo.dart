import '../logic/ids.dart';
import '../models/models.dart';
import 'db.dart';

Future<List<Driver>> listDrivers({bool includeInactive = false}) => guard(() async {
      var q = db.from('ss_drivers').select('*');
      if (!includeInactive) q = q.eq('active', true);
      final data = await q.order('sort_order').order('name');
      return (data as List).map((r) => Driver.fromRow(Map<String, dynamic>.from(r as Map))).toList();
    });

Future<void> saveDriver({
  String? id,
  required String name,
  required String village,
  required RouteGroup routeGroup,
  required int truckSize,
  required int truckCount,
  required List<DriverContact> contacts,
  required String contactNote,
  required double wagePerTrip,
  required bool active,
}) {
  final row = {
    'name': name.trim(),
    'village': village.trim(),
    'route_group': routeGroup.name,
    'truck_size': truckSize,
    'truck_count': truckCount,
    'contacts': contacts.where((c) => c.phone.trim().isNotEmpty).map((c) => c.toJson()).toList(),
    'contact_note': contactNote.trim(),
    'wage_per_trip': wagePerTrip,
    'active': active,
  };
  return guard(() => id != null
      ? db.from('ss_drivers').update(row).eq('id', id)
      : db.from('ss_drivers').insert({'id': newId('drv'), 'sort_order': 100, ...row}));
}

Future<void> deleteDriver(String id) => guard(
      () => db.from('ss_drivers').delete().eq('id', id),
      'คนขับคนนี้มีออเดอร์อยู่ ลบไม่ได้ ใช้การปิด "รับงาน" แทน หรือเปลี่ยนคนขับในออเดอร์เหล่านั้นก่อน',
    );
