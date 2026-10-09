import '../logic/ids.dart';
import '../models/models.dart';
import 'db.dart';

Future<List<Product>> listProducts() => guard(() async {
      final data = await db.from('ss_products').select('*').order('sort_order');
      return (data as List).map((r) => Product.fromRow(Map<String, dynamic>.from(r as Map))).toList();
    });

Future<void> saveProduct({
  required String id,
  required String name,
  required ProductCategory category,
  required double pricePerUnit,
  required bool active,
}) =>
    guard(() => db.from('ss_products').update({
          'name': name.trim(),
          'category': category.name,
          'price_per_unit': pricePerUnit,
          'active': active,
        }).eq('id', id));

Future<void> createProduct({
  required String name,
  required ProductCategory category,
  required String unit,
  required double pricePerUnit,
  required int sortOrder,
}) =>
    guard(() => db.from('ss_products').insert({
          'id': newId('prd'),
          'name': name.trim(),
          'category': category.name,
          'unit': unit.trim().isEmpty ? 'คิว' : unit.trim(),
          'price_per_unit': pricePerUnit,
          'sort_order': sortOrder,
          'active': true,
        }));

/// Past orders keep their own copy of the product name and price.
Future<void> deleteProduct(String id) => guard(() => db.from('ss_products').delete().eq('id', id));

Future<List<Zone>> listZones() => guard(() async {
      final data = await db.from('ss_zones').select('*').order('sort_order');
      return (data as List).map((r) => Zone.fromRow(Map<String, dynamic>.from(r as Map))).toList();
    });

/// fee_min holds the customer's baht/คิว. fee_max is no longer used for pricing; it is kept equal to
/// fee_min to satisfy CHECK (fee_max >= fee_min).
Future<void> saveZone({
  required String id,
  required String name,
  required double feePerCubic,
}) =>
    guard(() => db
        .from('ss_zones')
        .update({'name': name.trim(), 'fee_min': feePerCubic, 'fee_max': feePerCubic}).eq('id', id));

Future<void> createZone({
  required String name,
  required double feePerCubic,
  required int sortOrder,
}) =>
    guard(() => db.from('ss_zones').insert({
          'id': newId('zone'),
          'name': name.trim(),
          'fee_min': feePerCubic,
          'fee_max': feePerCubic,
          'sort_order': sortOrder,
        }));

Future<void> deleteZone(String id) => guard(
      () => db.from('ss_zones').delete().eq('id', id),
      'มีลูกค้าหรือออเดอร์ที่ใช้ตำบลนี้อยู่ ลบไม่ได้',
    );

Future<AppSettings> getSettings() => guard(() async {
      final data = await db.from('ss_settings').select('key, value');
      final byKey = <String, Map<String, dynamic>>{};
      for (final r in data as List) {
        final m = r as Map;
        if (m['value'] is Map) byKey['${m['key']}'] = Map<String, dynamic>.from(m['value'] as Map);
      }
      return AppSettings(
        company: CompanySettings.fromJson(byKey['company']),
        delivery: DeliverySettings.fromJson(byKey['delivery']),
        payment: PaymentSettings.fromJson(byKey['payment']),
      );
    });

/// [key]: 'company' | 'delivery' | 'payment'
Future<void> saveSetting(String key, Map<String, dynamic> value) => guard(() => db.from('ss_settings').upsert({
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }));
