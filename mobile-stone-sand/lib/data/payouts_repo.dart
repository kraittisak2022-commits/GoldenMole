import '../models/models.dart';
import 'db.dart';
import 'scope.dart';

const _payoutSelect =
    '*, orders:ss_orders!ss_orders_driver_payout_id_fkey(id, order_no, order_date, source, customer_snapshot, trips, driver_wage),'
    ' cash:ss_payments!ss_payments_driver_payout_id_fkey(amount, order:ss_orders!ss_payments_order_id_fkey(source))';

bool _visible(Object? source) {
  final s = OrderSource.tryParse(source);
  return s != null ? canSeeSource(s) : lockedSource() == null;
}

double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? 0}') ?? 0;

DriverPayout _mapPayout(Map<String, dynamic> row) {
  // A payout can mix both sources; a limited account sees only its own part of it.
  final limited = lockedSource() != null;
  final orders = ((row['orders'] as List?) ?? const [])
      .whereType<Map>()
      .where((o) => _visible(o['source']))
      .map((o) => DriverPayoutOrder(
            id: '${o['id']}',
            orderNo: '${o['order_no']}',
            orderDate: '${o['order_date']}',
            customerName: '${(o['customer_snapshot'] as Map?)?['name'] ?? ''}',
            trips: _n(o['trips']).toInt(),
            amount: _n(o['driver_wage']),
          ))
      .toList()
    ..sort((a, b) => a.orderNo.compareTo(b.orderNo));
  final cash = ((row['cash'] as List?) ?? const [])
      .whereType<Map>()
      .where((p) => _visible((p['order'] as Map?)?['source']));
  return DriverPayout(
    id: '${row['id']}',
    payoutNo: '${row['payout_no']}',
    driverId: '${row['driver_id']}',
    driverName: '${row['driver_name'] ?? ''}',
    total: limited ? orders.fold(0, (s, o) => s + o.amount) : _n(row['total']),
    cashCollected: cash.fold(0, (s, p) => s + _n(p['amount'])),
    method: '${row['method']}',
    note: '${row['note'] ?? ''}',
    createdBy: row['created_by'] as String?,
    createdAt: '${row['created_at']}',
    orders: orders,
  );
}

Future<List<DriverPayout>> listDriverPayouts() => guard(() async {
      final data = await db
          .from('ss_driver_payouts')
          .select(_payoutSelect)
          .order('created_at', ascending: false)
          .limit(300);
      return (data as List)
          .map((r) => _mapPayout(Map<String, dynamic>.from(r as Map)))
          .where((p) => lockedSource() == null || p.orders.isNotEmpty)
          .toList();
    });

/// [cashExpected]: COD money shown on screen; the server refuses if it no longer matches.
Future<String> createDriverPayout({
  required String driverId,
  required List<({String orderId, double amount})> lines,
  required String method,
  required String note,
  required String by,
  required double cashExpected,
}) async {
  final data = await guard(() => db.rpc('ss_create_driver_payout', params: {
        'p_driver_id': driverId,
        'p_lines': lines.map((l) => {'order_id': l.orderId, 'amount': l.amount}).toList(),
        'p_method': method,
        'p_note': note.trim(),
        'p_by': by,
        'p_cash_expected': cashExpected,
      }));
  notifyDataChanged();
  return data is Map ? '${data['payout_no']}' : '';
}

/// The driver hands over all the COD money now; his fee for these orders stays unpaid until the
/// monthly driver clearing. Returns the amount received.
Future<double> receiveDriverCod({
  required String driverId,
  required List<String> orderIds,
  required String note,
  required String by,
  required double cashExpected,
}) async {
  final data = await guard(() => db.rpc('ss_receive_driver_cod', params: {
        'p_driver_id': driverId,
        'p_order_ids': orderIds,
        'p_note': note.trim(),
        'p_by': by,
        'p_cash_expected': cashExpected,
      }));
  notifyDataChanged();
  return _n(data);
}

/// Its orders go back to "ค่ารถยังไม่จ่าย"; COD money taken through it goes back to unpaid.
Future<void> deleteDriverPayout(String id, String by) async {
  await guard(() => db.rpc('ss_delete_driver_payout', params: {'p_payout_id': id, 'p_by': by}));
  notifyDataChanged();
}
