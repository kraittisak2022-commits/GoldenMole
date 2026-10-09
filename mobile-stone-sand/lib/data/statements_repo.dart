import '../models/models.dart';
import 'db.dart';
import 'scope.dart';

const _statementSelect = '*, links:ss_statement_orders(order_id)';

Future<List<Statement>> listStatements({String? customerId}) => guard(() async {
      var q = scoped(db.from('ss_statements').select(_statementSelect));
      if (customerId != null) q = q.eq('customer_id', customerId);
      final data = await q.order('created_at', ascending: false).limit(300);
      return (data as List).map((r) => Statement.fromRow(Map<String, dynamic>.from(r as Map))).toList();
    });

Future<Statement?> getStatement(String id) => guard(() async {
      final data = await scoped(db.from('ss_statements').select(_statementSelect)).eq('id', id).maybeSingle();
      return data == null ? null : Statement.fromRow(data);
    });

Future<Statement> createStatement({
  required OrderSource source,
  required String customerId,
  required List<String> orderIds,
  required String from,
  required String to,
  required String note,
  required String by,
}) async {
  final data = await guard(() => db.rpc('ss_create_statement', params: {
        'p_customer_id': customerId,
        'p_order_ids': orderIds,
        'p_from': from,
        'p_to': to,
        'p_note': note,
        'p_by': by,
        'p_source': source.name,
      }));
  final s = await getStatement(data is Map ? '${data['id']}' : '');
  if (s == null) throw const AppException('ไม่พบใบวางบิล');
  notifyDataChanged();
  return s;
}

/// [method]: 'cash' | 'transfer'
Future<Statement> clearStatement(String id, String method, String by) async {
  await guard(() => db.rpc('ss_clear_statement', params: {'p_statement_id': id, 'p_method': method, 'p_by': by}));
  final s = await getStatement(id);
  if (s == null) throw const AppException('ไม่พบใบวางบิล');
  notifyDataChanged();
  return s;
}

/// Works on cleared statements too: their orders go back to outstanding.
Future<void> deleteStatement(String id, String by) async {
  await guard(() => db.rpc('ss_delete_statement', params: {'p_statement_id': id, 'p_by': by}));
  notifyDataChanged();
}
