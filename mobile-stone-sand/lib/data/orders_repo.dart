import '../calc/pricing.dart';
import '../logic/order_draft.dart';
import '../models/models.dart';
import 'db.dart';
import 'scope.dart';

const _orderSelect =
    '*, items:ss_order_items(*), stmt:ss_statement_orders(statement_id), cust:ss_customers(aliases)';

List<Order> _map(Object? data) =>
    (data as List).map((r) => Order.fromRow(Map<String, dynamic>.from(r as Map))).toList();

Future<List<Order>> listOrders({
  String? from,
  String? to,
  String? customerId,
  OrderSource? source,
  List<DeliveryStatus>? deliveryStatuses,
  int limit = 500,
}) =>
    guard(() async {
      var q = scoped(db.from('ss_orders').select(_orderSelect));
      if (from != null && from.isNotEmpty) q = q.gte('order_date', from);
      if (to != null && to.isNotEmpty) q = q.lte('order_date', to);
      if (customerId != null) q = q.eq('customer_id', customerId);
      if (source != null) q = q.eq('source', source.name);
      if (deliveryStatuses != null && deliveryStatuses.isNotEmpty) {
        q = q.inFilter('delivery_status', deliveryStatuses.map((s) => s.name).toList()).eq('cancelled', false);
      }
      final data = await q
          .order('order_date', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);
      return _map(data);
    });

/// Not cleared and not cancelled, oldest first (outstanding balances and monthly statements).
Future<List<Order>> listUnclearedOrders({String? customerId}) => guard(() async {
      var q = scoped(db.from('ss_orders').select(_orderSelect)).eq('cleared', false).eq('cancelled', false);
      if (customerId != null) q = q.eq('customer_id', customerId);
      final data = await q.order('order_date').order('created_at').limit(2000);
      return _map(data);
    });

/// Delivery orders with a driver whose ค่ารถ has not been paid yet, oldest first.
Future<List<Order>> listDriverUnpaidOrders() => guard(() async {
      final data = await scoped(db.from('ss_orders').select(_orderSelect))
          .isFilter('demo_session', null)
          .eq('fulfillment', 'delivery')
          .eq('cancelled', false)
          .not('driver_id', 'is', null)
          .isFilter('driver_payout_id', null)
          .order('order_date')
          .order('created_at')
          .limit(2000);
      return _map(data);
    });

Future<Order?> getOrder(String id) => guard(() async {
      final data = await scoped(db.from('ss_orders').select(_orderSelect)).eq('id', id).maybeSingle();
      return data == null ? null : Order.fromRow(data);
    });

Future<List<Order>> getOrdersByIds(List<String> ids) async {
  if (ids.isEmpty) return [];
  return guard(() async {
    final data = await scoped(db.from('ss_orders').select(_orderSelect))
        .inFilter('id', ids)
        .order('order_date')
        .order('created_at');
    return _map(data);
  });
}

Map<String, dynamic> _itemRow(OrderItem it, {bool recompute = false}) => {
      'product_id': it.productId,
      'name': it.name,
      'unit': it.unit,
      'unit_price': it.unitPrice,
      'quantity': it.quantity,
      'amount': recompute ? lineAmount(it.unitPrice, it.quantity) : it.amount,
      'discount_per_unit': it.discountPerUnit,
    };

Future<Order> _reload(Object? data) async {
  final id = data is Map ? '${data['id']}' : '';
  final order = await getOrder(id);
  if (order == null) throw const AppException('ไม่พบออเดอร์');
  notifyDataChanged();
  return order;
}

Future<Order> createOrder(OrderDraft d, String by) async {
  final totals = draftTotals(
    items: d.items,
    fulfillment: d.fulfillment,
    feePerCubic: d.feePerCubic,
    feePerTrip: d.feePerTrip,
    trips: d.trips,
    remoteSurcharge: d.remoteSurcharge,
    deliveryDiscount: d.deliveryDiscount,
    discountType: d.discountType,
    discountValue: d.discountValue,
  );
  final delivery = d.fulfillment == Fulfillment.delivery;
  final paymentStatus = d.paidNow
      ? PaymentStatus.paid
      : d.paymentMethod == PaymentMethod.credit
          ? PaymentStatus.credit
          : PaymentStatus.unpaid;
  final order = {
    'source': d.source.name,
    'order_date': d.orderDate,
    'customer_id': d.customer.id,
    'customer_snapshot': d.customer.toSnapshot().toJson(),
    'fulfillment': d.fulfillment.name,
    'delivery_address': delivery ? d.deliveryAddress.trim() : '',
    'pin_lat': delivery ? d.pinLat : null,
    'pin_lng': delivery ? d.pinLng : null,
    'zone_id': delivery ? d.zoneId : null,
    'road_distance_km': delivery ? d.roadDistanceKm : null,
    'truck_size': delivery ? d.truckSize : null,
    'trips': delivery ? d.trips : 0,
    'driver_id': delivery ? d.driverId : null,
    'fee_per_cubic': delivery ? d.feePerCubic : 0,
    'fee_per_trip': delivery ? d.feePerTrip : 0,
    'remote_surcharge': delivery ? d.remoteSurcharge : 0,
    'delivery_discount': totals.deliveryDiscount,
    'discount_type': d.discountType.name,
    'discount_value': d.discountValue,
    'subtotal': totals.subtotal,
    'delivery_total': totals.deliveryTotal,
    'discount_amount': totals.discountAmount,
    'total': totals.total,
    'payment_method': d.paymentMethod.name,
    'payment_status': paymentStatus.name,
    'delivery_status': delivery ? DeliveryStatus.waiting.name : DeliveryStatus.pickup.name,
    'driver_wage': delivery ? d.driverWage : 0,
    'note': d.note.trim(),
    'demo_session': demoSession(),
  };
  final items = d.items.where((it) => it.quantity > 0).map(_itemRow).toList();
  final data = await guard(
    () => db.rpc('ss_create_order', params: {'p_order': order, 'p_items': items, 'p_by': by}),
  );
  final created = await getOrder(data is Map ? '${data['id']}' : '');
  if (created == null) throw const AppException('บันทึกออเดอร์แล้วแต่โหลดข้อมูลไม่ได้');
  notifyDataChanged();
  return created;
}

Future<Order> _rpcOrder(String fn, Map<String, dynamic> args) async {
  final data = await guard(() => db.rpc(fn, params: args));
  return _reload(data);
}

/// [method]: 'cash' | 'transfer' | 'cod'
Future<Order> markOrderPaid(String id, String method, String by) =>
    _rpcOrder('ss_mark_order_paid', {'p_order_id': id, 'p_method': method, 'p_by': by});

Future<Order> markOrderUnpaid(String id, String by) =>
    _rpcOrder('ss_mark_order_unpaid', {'p_order_id': id, 'p_by': by});

Future<Order> setDeliveryStatus(String id, DeliveryStatus status, String by) =>
    _rpcOrder('ss_set_delivery_status', {'p_order_id': id, 'p_status': status.name, 'p_by': by});

class OrderEdit {
  const OrderEdit({
    required this.orderDate,
    required this.items,
    required this.truckSize,
    required this.trips,
    required this.feePerCubic,
    required this.feePerTrip,
    required this.remoteSurcharge,
    required this.deliveryDiscount,
    required this.discountType,
    required this.discountValue,
    required this.paymentMethod,
    required this.deliveryAddress,
    required this.note,
  });
  final String orderDate;
  final List<OrderItem> items;
  final int? truckSize;
  final int trips;
  final double feePerCubic;
  final double feePerTrip;
  final double remoteSurcharge;
  final double deliveryDiscount;
  final DiscountType discountType;
  final double discountValue;
  final PaymentMethod paymentMethod;
  final String deliveryAddress;
  final String note;
}

Totals editTotals(OrderEdit e, Fulfillment fulfillment) => draftTotals(
      items: e.items.where((it) => it.quantity > 0).toList(),
      fulfillment: fulfillment,
      feePerCubic: e.feePerCubic,
      feePerTrip: e.feePerTrip,
      trips: e.trips,
      remoteSurcharge: e.remoteSurcharge,
      deliveryDiscount: e.deliveryDiscount,
      discountType: e.discountType,
      discountValue: e.discountValue,
    );

Future<Order> updateOrder(Order current, OrderEdit e, String by) {
  final items = e.items.where((it) => it.quantity > 0).toList();
  final totals = editTotals(e, current.fulfillment);
  final order = {
    'order_date': e.orderDate,
    'delivery_address': e.deliveryAddress.trim(),
    'truck_size': e.truckSize,
    'trips': e.trips,
    'fee_per_cubic': e.feePerCubic,
    'fee_per_trip': e.feePerTrip,
    'remote_surcharge': e.remoteSurcharge,
    'delivery_discount': totals.deliveryDiscount,
    'discount_type': e.discountType.name,
    'discount_value': e.discountValue,
    'subtotal': totals.subtotal,
    'delivery_total': totals.deliveryTotal,
    'discount_amount': totals.discountAmount,
    'total': totals.total,
    'payment_method': e.paymentMethod.name,
    'note': e.note.trim(),
  };
  final rows = items.map((it) => _itemRow(it, recompute: true)).toList();
  return _rpcOrder('ss_update_order', {'p_order_id': current.id, 'p_order': order, 'p_items': rows, 'p_by': by});
}

/// Also drops it from its statement (an emptied statement is deleted).
Future<void> deleteOrder(String id) async {
  await guard(() => db.rpc('ss_delete_order', params: {'p_order_id': id}));
  notifyDataChanged();
}

const _keep = Object();

Future<Order> updateOrderFields(
  String id,
  String by,
  Order current, {
  Object? driverId = _keep,
  double? driverWage,
  String? note,
  bool? cancelled,
}) async {
  final row = <String, dynamic>{};
  final events = <String>[];
  if (!identical(driverId, _keep)) {
    row['driver_id'] = driverId as String?;
    events.add('driver');
  }
  if (driverWage != null) {
    row['driver_wage'] = driverWage;
    events.add('wage:${_plain(driverWage)}');
  }
  if (note != null) row['note'] = note;
  if (cancelled != null) {
    row['cancelled'] = cancelled;
    events.add(cancelled ? 'cancelled' : 'restored');
  }
  if (events.isNotEmpty) {
    final at = DateTime.now().toUtc().toIso8601String();
    row['status_log'] = [
      ...current.statusLog.map((e) => e.toJson()),
      ...events.map((event) => {'at': at, 'by': by, 'event': event}),
    ];
  }
  await guard(() => db.from('ss_orders').update(row).eq('id', id));
  final order = await getOrder(id);
  if (order == null) throw const AppException('ไม่พบออเดอร์');
  notifyDataChanged();
  return order;
}

/// JS prints whole numbers without ".0" (wage:500, not wage:500.0).
String _plain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
