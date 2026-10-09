import '../logic/customer_search.dart';
import '../logic/format.dart';
import '../logic/ids.dart';
import '../models/models.dart';
import 'db.dart';
import 'scope.dart';

List<Customer> _map(Object? data) =>
    (data as List).map((r) => Customer.fromRow(Map<String, dynamic>.from(r as Map))).toList();

Future<List<Customer>> listCustomers() => guard(() async {
      final data = await demoFilter(db.from('ss_customers').select('*')).order('name');
      return _map(data);
    });

Future<List<Customer>> searchCustomers(String query, {int limit = 8}) async {
  final q = query.trim();
  if (q.isEmpty) return [];
  return guard(() async {
    final digits = digitsOnly(q);
    final escaped = q.replaceAll(RegExp('[%,()]'), ' ');
    final filters = ['name.ilike.%$escaped%', 'aliases.ilike.%$escaped%'];
    if (digits.length >= 3) filters.add('phone.ilike.%$digits%');
    final data = await db
        .from('ss_customers')
        .select('*')
        .or(filters.join(','))
        .order('name')
        .limit(limit + 4);
    // A second .or() would collide with the search filter, so demo rows are dropped here.
    return (data as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .where((r) => isVisibleDemo(r['demo_session']))
        .take(limit)
        .map(Customer.fromRow)
        .toList();
  });
}

Future<Customer?> getCustomer(String id) => guard(() async {
      final data = await db.from('ss_customers').select('*').eq('id', id).maybeSingle();
      return data == null ? null : Customer.fromRow(data);
    });

Future<Customer> saveCustomer(Customer input, {bool isNew = false}) async {
  final row = {
    'name': input.name.trim(),
    'aliases': formatAliases(input.aliases),
    'phone': digitsOnly(input.phone),
    'address': input.address.trim(),
    'zone_id': (input.zoneId ?? '').isEmpty ? null : input.zoneId,
    'tax_id': input.taxId.trim(),
    'lat': input.lat,
    'lng': input.lng,
    'is_credit': input.isCredit,
    'note': input.note.trim(),
  };
  final saved = await guard(() async {
    final data = isNew || input.id.isEmpty
        ? await db
            .from('ss_customers')
            .insert({'id': newId('cus'), ...row, 'demo_session': demoSession()})
            .select('*')
            .single()
        : await db.from('ss_customers').update(row).eq('id', input.id).select('*').single();
    return Customer.fromRow(data);
  });
  notifyDataChanged();
  return saved;
}

Future<void> deleteCustomer(String id) async {
  await guard(
    () => db.from('ss_customers').delete().eq('id', id),
    'ลูกค้ารายนี้มีออเดอร์หรือใบวางบิลอยู่ ต้องลบออเดอร์และใบวางบิลของลูกค้าก่อน',
  );
  notifyDataChanged();
}
