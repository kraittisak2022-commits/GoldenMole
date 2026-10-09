import '../models/models.dart';
import 'driver_pay.dart' show codToCollect;
import 'format.dart';

enum OrderFilter {
  all('ทั้งหมด'),
  unpaid('ยังไม่จ่าย'),
  credit('ค้างเครดิต'),
  waiting('กำลังจัดส่ง'),
  delivered('ส่งแล้ว'),
  uncleared('ยังไม่เคลียร์บิล'),
  cancelled('ยกเลิก');

  const OrderFilter(this.label);
  final String label;

  static OrderFilter parse(String? v) =>
      OrderFilter.values.firstWhere((f) => f.name == v, orElse: () => OrderFilter.all);
}

bool matchesFilter(Order o, OrderFilter f) {
  if (f == OrderFilter.cancelled) return o.cancelled;
  if (o.cancelled) return f == OrderFilter.all;
  switch (f) {
    case OrderFilter.unpaid:
      return o.paymentStatus == PaymentStatus.unpaid;
    case OrderFilter.credit:
      return o.paymentStatus == PaymentStatus.credit && !o.cleared;
    case OrderFilter.waiting:
      return o.deliveryStatus == DeliveryStatus.waiting || o.deliveryStatus == DeliveryStatus.dispatched;
    case OrderFilter.delivered:
      return o.deliveryStatus == DeliveryStatus.delivered;
    case OrderFilter.uncleared:
      return !o.cleared;
    default:
      return true;
  }
}

bool matchesSearch(Order o, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final digits = q.replaceAll(RegExp(r'\D'), '');
  return o.customer.name.toLowerCase().contains(q) ||
      o.customerAliases.any((a) => a.toLowerCase().contains(q)) ||
      o.orderNo.toLowerCase().contains(q) ||
      (o.receiptNo ?? '').toLowerCase().contains(q) ||
      (digits.length >= 3 && digitsOnly(o.customer.phone).contains(digits));
}

enum BadgeTone { neutral, success, warning, info, danger, violet }

typedef BadgeInfo = ({BadgeTone tone, String label});

BadgeInfo paymentBadge(Order o) {
  if (o.paymentStatus == PaymentStatus.paid) return (tone: BadgeTone.success, label: 'จ่ายแล้ว');
  if (o.paymentStatus == PaymentStatus.credit) {
    return o.cleared
        ? (tone: BadgeTone.success, label: 'เคลียร์แล้ว')
        : (tone: BadgeTone.info, label: 'ค้างเครดิต');
  }
  return (tone: BadgeTone.warning, label: 'ยังไม่จ่าย');
}

BadgeInfo deliveryBadge(Order o) {
  final tone = o.deliveryStatus == DeliveryStatus.delivered
      ? BadgeTone.success
      : o.deliveryStatus == DeliveryStatus.pickup
          ? BadgeTone.neutral
          : BadgeTone.warning;
  return (tone: tone, label: o.deliveryStatus.label);
}

/// Text the sales desk pastes into LINE for the driver.
String driverMessage(Order o, Zone? zone, Driver? driver) {
  final lines = <String>[
    'ออเดอร์ ${o.orderNo}${driver != null ? ' · ${driver.name}' : ''}',
    'ลูกค้า: ${o.customer.name}${o.customer.phone.isNotEmpty ? ' ${formatPhone(o.customer.phone)}' : ''}',
    'สินค้า: ${o.items.map((it) => '${it.name} ${formatNumber(it.quantity)} ${it.unit}').join(', ')}',
  ];
  if (o.truckSize != null) lines.add('รถ ${o.truckSize} คิว × ${o.trips} เที่ยว');
  if (zone != null) lines.add('ตำบล: ${zone.name}');
  if (o.deliveryAddress.isNotEmpty) lines.add('ที่อยู่: ${o.deliveryAddress}');
  if (o.pinLat != null && o.pinLng != null) lines.add('แผนที่: ${googleMapsUrl(o.pinLat!, o.pinLng!)}');
  final cod = codToCollect(o);
  if (cod != 0) lines.add('เก็บเงินปลายทาง: ${formatMoney(cod)} บาท');
  if (o.note.isNotEmpty) lines.add('หมายเหตุ: ${o.note}');
  if (o.driverToken.isNotEmpty && o.fulfillment == Fulfillment.delivery && !o.cancelled) {
    lines
      ..add('')
      ..add(cod != 0
          ? 'หากส่งแล้ว กดลิงก์นี้เพื่อยืนยันส่งสำเร็จและแจ้งยอดเงินที่เก็บ:'
          : 'หากส่งแล้ว กดลิงก์นี้เพื่อยืนยันส่งสำเร็จ:')
      ..add(driverJobUrl(o.driverToken));
  }
  return lines.join('\n');
}

/// Human text for one status_log event (`kind:arg`); unknown events fall back to a driver name or the raw text.
String orderLogLabel(StatusLogEntry e, String? Function(String id) driverName) {
  final i = e.event.indexOf(':');
  final kind = i < 0 ? e.event : e.event.substring(0, i);
  final arg = i < 0 ? '' : e.event.substring(i + 1);
  switch (kind) {
    case 'created':
      return 'สร้างออเดอร์';
    case 'paid':
      final m = PaymentMethod.values.where((p) => p.name == arg);
      return 'รับเงินแล้ว (${m.isEmpty ? arg : m.first.label})';
    case 'unpaid':
      return 'ยกเลิกการรับเงิน';
    case 'delivery':
      final s = DeliveryStatus.values.where((d) => d.name == arg);
      return 'สถานะจัดส่ง: ${s.isEmpty ? arg : s.first.label}';
    case 'cleared':
      return 'เคลียร์บิลกับใบวางบิล $arg';
    case 'driver':
      return 'เปลี่ยนคนขับ';
    case 'wage':
      return 'ค่าจ้างคนขับ ${formatNumber(num.tryParse(arg) ?? 0)} บาท';
    case 'cancelled':
      return 'ยกเลิกออเดอร์';
    case 'edited':
      return 'แก้ไขออเดอร์';
    case 'uncleared':
      return 'ลบใบวางบิล $arg (กลับเป็นยังไม่เคลียร์)';
    case 'restored':
      return 'กู้คืนออเดอร์';
    case 'wage_paid':
      return 'จ่ายค่ารถให้คนขับแล้ว ($arg)';
    case 'wage_unpaid':
      return 'ลบรายการจ่ายค่ารถ $arg (กลับเป็นค่ารถยังไม่จ่าย)';
    case 'driver_cash':
      return 'คนขับแจ้งเก็บเงินปลายทาง ${formatMoney(num.tryParse(arg) ?? 0)} บาท';
    default:
      return driverName(arg) ?? e.event;
  }
}

double outstanding(Order o) => o.cancelled || o.cleared ? 0 : o.total;

/// One row per customer and order source: a statement never mixes ร้านวัสดุ and ท่าทราย orders.
class CustomerOutstanding {
  CustomerOutstanding({
    required this.customerId,
    required this.source,
    required this.name,
    required this.phone,
    required this.oldestDate,
  });
  final String customerId;
  final OrderSource source;
  final String name;
  final String phone;
  double total = 0;
  int count = 0;

  /// Uncleared orders not yet on any statement.
  double unbilledTotal = 0;
  int unbilledCount = 0;
  String oldestDate;
}

/// Partial payments already received on open statements, by statement id.
Map<String, double> statementPaidMap(List<Statement> statements) => {
  for (final s in statements)
    if (!s.isCleared && s.paidAmount > 0) s.id: s.paidAmount,
};

List<CustomerOutstanding> summarizeOutstanding(List<Order> orders, [Map<String, double> paidByStatement = const {}]) {
  final map = <String, CustomerOutstanding>{};
  final deducted = <String>{};
  for (final o in orders) {
    final amount = outstanding(o);
    if (amount == 0) continue;
    final key = '${o.customerId}:${o.source.name}';
    final row = map.putIfAbsent(
      key,
      () => CustomerOutstanding(
        customerId: o.customerId,
        source: o.source,
        name: o.customer.name,
        phone: o.customer.phone,
        oldestDate: o.orderDate,
      ),
    );
    row.total += amount;
    row.count += 1;
    final sid = o.statementId;
    if (sid != null && deducted.add(sid)) row.total -= paidByStatement[sid] ?? 0;
    if (o.statementId == null) {
      row.unbilledTotal += amount;
      row.unbilledCount += 1;
    }
    if (o.orderDate.compareTo(row.oldestDate) < 0) row.oldestDate = o.orderDate;
  }
  final list = map.values.toList();
  // Stable sort, like Array.prototype.sort.
  return _stableSort(list, (a, b) => b.total.compareTo(a.total));
}

List<T> _stableSort<T>(List<T> list, int Function(T a, T b) cmp) {
  final indexed = list.asMap().entries.toList()
    ..sort((a, b) {
      final c = cmp(a.value, b.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return indexed.map((e) => e.value).toList();
}

List<T> stableSorted<T>(Iterable<T> items, int Function(T a, T b) cmp) => _stableSort(items.toList(), cmp);
