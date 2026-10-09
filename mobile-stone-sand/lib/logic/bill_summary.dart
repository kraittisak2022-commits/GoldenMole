import '../models/models.dart';
import 'driver_pay.dart' show customerDeliveryFee, suggestedDriverPay;
import 'order_status.dart' show BadgeTone, outstanding;

/// Where an order is held up, in the order the desk works through them.
enum BillStage {
  needDriver('รอเลือกคนขับ', BadgeTone.danger),
  waitDelivery('รอจัดส่ง', BadgeTone.warning),
  onTheWay('กำลังส่ง', BadgeTone.warning),
  driverCash('รอรับเงินจากคนขับ', BadgeTone.warning),
  unbilled('รอวางบิล', BadgeTone.info),
  billed('รอลูกค้าจ่ายตามใบวางบิล', BadgeTone.info),
  awaitPayment('รอรับเงิน', BadgeTone.warning),
  payDriver('รอเคลียร์ค่ารถ', BadgeTone.info),
  done('ปิดงานแล้ว', BadgeTone.success),
  cancelled('ยกเลิก', BadgeTone.neutral);

  const BillStage(this.label, this.tone);
  final String label;
  final BadgeTone tone;

  bool get isOpen => this != done && this != cancelled;
}

enum BillStepState { done, current, todo, skip }

class BillStep {
  const BillStep(this.key, this.label, this.state);
  final String key;
  final String label;
  final BillStepState state;
}

class BillSummary {
  const BillSummary({
    required this.revenue,
    required this.goods,
    required this.deliveryFee,
    required this.driverCost,
    required this.driverCostEstimated,
    required this.received,
    required this.receivable,
    required this.stage,
    required this.steps,
  });

  /// ยอดบิล: what the customer is charged.
  final double revenue;

  /// ค่าสินค้า after all discounts other than the delivery discount.
  final double goods;

  /// ค่าส่งที่เก็บลูกค้า after the delivery discount.
  final double deliveryFee;

  /// ค่ารถที่จ่ายคนขับ: the paid amount, or the default amount while unpaid.
  final double driverCost;

  /// [driverCost] is a forecast because the driver has not been paid yet.
  final bool driverCostEstimated;
  final double received;
  final double receivable;
  final BillStage stage;
  final List<BillStep> steps;

  /// เงินที่เหลือเข้าร้าน.
  double get net => revenue - driverCost;

  /// ค่าส่งที่เก็บลูกค้า − ค่ารถคนขับ; negative means delivery runs at a loss.
  double get deliveryMargin => deliveryFee - driverCost;
}

BillStage? _moneyStage(Order o) {
  if (o.cleared || o.paymentStatus == PaymentStatus.paid) return null;
  if (o.statementId != null) return BillStage.billed;
  if (o.paymentMethod == PaymentMethod.cod && o.fulfillment == Fulfillment.delivery) return BillStage.driverCash;
  if (o.paymentStatus == PaymentStatus.credit) return BillStage.unbilled;
  return BillStage.awaitPayment;
}

BillStage billStage(Order o) {
  if (o.cancelled) return BillStage.cancelled;
  final delivery = o.fulfillment == Fulfillment.delivery;
  if (delivery && o.driverId == null) return BillStage.needDriver;
  if (delivery && o.deliveryStatus == DeliveryStatus.waiting) return BillStage.waitDelivery;
  if (delivery && o.deliveryStatus == DeliveryStatus.dispatched) return BillStage.onTheWay;
  final money = _moneyStage(o);
  if (money != null) return money;
  if (delivery && o.driverPayoutId == null) return BillStage.payDriver;
  return BillStage.done;
}

List<BillStep> _steps(Order o) {
  final delivery = o.fulfillment == Fulfillment.delivery;
  final delivered = !delivery || o.deliveryStatus == DeliveryStatus.delivered;
  final paid = o.cleared || o.paymentStatus == PaymentStatus.paid;
  final states = [
    BillStepState.done,
    delivered ? BillStepState.done : BillStepState.todo,
    paid ? BillStepState.done : BillStepState.todo,
    !delivery ? BillStepState.skip : (o.driverPayoutId != null ? BillStepState.done : BillStepState.todo),
  ];
  if (!o.cancelled) {
    final next = states.indexOf(BillStepState.todo);
    if (next >= 0) states[next] = BillStepState.current;
  }
  return [
    BillStep('order', 'เปิดบิล', states[0]),
    BillStep('delivery', delivery ? 'จัดส่ง' : 'รับสินค้า', states[1]),
    BillStep('payment', 'รับเงิน', states[2]),
    BillStep('driver', 'จ่ายค่ารถ', states[3]),
  ];
}

/// [zone] is the order's tambon: while the driver is unpaid, his cost is estimated from its rate.
BillSummary summarizeBill(Order o, {Zone? zone, DeliverySettings delivery = DeliverySettings.defaults}) {
  final stage = billStage(o);
  final steps = _steps(o);
  if (o.cancelled) {
    return BillSummary(
      revenue: 0,
      goods: 0,
      deliveryFee: 0,
      driverCost: 0,
      driverCostEstimated: false,
      received: 0,
      receivable: 0,
      stage: stage,
      steps: steps,
    );
  }
  final deliveryFee = customerDeliveryFee(o);
  final hasDriver = o.fulfillment == Fulfillment.delivery && o.driverId != null;
  final paidOut = o.driverPayoutId != null;
  final receivable = outstanding(o);
  return BillSummary(
    revenue: o.total,
    goods: o.total - deliveryFee,
    deliveryFee: deliveryFee,
    driverCost: !hasDriver ? 0 : (paidOut ? o.driverWage : suggestedDriverPay(o, zone, delivery)),
    driverCostEstimated: hasDriver && !paidOut,
    received: o.total - receivable,
    receivable: receivable,
    stage: stage,
    steps: steps,
  );
}

class BillTotals {
  int count = 0;
  double revenue = 0;
  double goods = 0;
  double deliveryFee = 0;
  double driverCost = 0;

  /// Part of [driverCost] not paid out yet.
  double driverCostPending = 0;
  double net = 0;
  double received = 0;
  double receivable = 0;
}

BillTotals totalBills(Iterable<BillSummary> rows) {
  final t = BillTotals();
  for (final r in rows) {
    if (r.stage == BillStage.cancelled) continue;
    t.count += 1;
    t.revenue += r.revenue;
    t.goods += r.goods;
    t.deliveryFee += r.deliveryFee;
    t.driverCost += r.driverCost;
    if (r.driverCostEstimated) t.driverCostPending += r.driverCost;
    t.net += r.net;
    t.received += r.received;
    t.receivable += r.receivable;
  }
  return t;
}

/// Share of the bill the shop keeps, as a whole percent; null when there is no revenue.
int? netMargin(double net, double revenue) => revenue > 0 ? (net / revenue * 100).round() : null;

String _csvCell(Object v) {
  final s = v is double ? (v == v.roundToDouble() ? '${v.toInt()}' : '$v') : '$v';
  return RegExp(r'[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// Spreadsheet export; the BOM makes Excel read the Thai text as UTF-8.
String billSummaryCsv(Iterable<({Order order, BillSummary summary, String driverName})> rows) {
  const header = [
    'เลขที่',
    'วันที่',
    'ลูกค้า',
    'รับสินค้า',
    'คนขับ',
    'ยอดบิล',
    'ค่าสินค้า',
    'ค่าส่งเก็บลูกค้า',
    'ค่ารถคนขับ',
    'ค่ารถ (ประมาณ)',
    'คงเหลือเข้าร้าน',
    'กำไรค่าส่ง',
    'รับเงินแล้ว',
    'ค้างรับ',
    'ขั้นตอน',
  ];
  final lines = [
    for (final (:order, :summary, :driverName) in rows)
      [
        order.orderNo,
        order.orderDate,
        order.customer.name,
        order.fulfillment == Fulfillment.delivery ? 'จัดส่ง' : 'มารับเอง',
        driverName,
        summary.revenue,
        summary.goods,
        summary.deliveryFee,
        summary.driverCost,
        summary.driverCostEstimated ? 'ใช่' : '',
        summary.net,
        summary.deliveryMargin,
        summary.received,
        summary.receivable,
        summary.stage.label,
      ].map(_csvCell).join(','),
  ];
  return '\uFEFF${[header.join(','), ...lines].join('\n')}';
}
