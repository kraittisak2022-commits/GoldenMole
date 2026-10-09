import '../models/models.dart';
import 'db.dart';
import 'scope.dart';

const _statementSelect =
    '*, links:ss_statement_orders(order_id),'
    ' payments:ss_payments!ss_payments_statement_id_fkey(id, amount, method, paid_at, note, created_by)';

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

/// Records part (or the rest) of a statement; it clears once payments reach its total.
/// [method]: 'cash' | 'transfer'
Future<Statement> payStatement({
  required String id,
  required double amount,
  required String method,
  required String note,
  required String by,
}) async {
  await guard(
    () => db.rpc(
      'ss_pay_statement',
      params: {'p_statement_id': id, 'p_amount': amount, 'p_method': method, 'p_note': note, 'p_by': by},
    ),
  );
  final s = await getStatement(id);
  if (s == null) throw const AppException('ไม่พบใบวางบิล');
  notifyDataChanged();
  return s;
}

Future<void> deleteStatementPayment(String paymentId, String by) async {
  await guard(() => db.rpc('ss_delete_statement_payment', params: {'p_payment_id': paymentId, 'p_by': by}));
  notifyDataChanged();
}

/// Works on cleared statements too: their orders go back to outstanding.
Future<void> deleteStatement(String id, String by) async {
  await guard(() => db.rpc('ss_delete_statement', params: {'p_statement_id': id, 'p_by': by}));
  notifyDataChanged();
}
