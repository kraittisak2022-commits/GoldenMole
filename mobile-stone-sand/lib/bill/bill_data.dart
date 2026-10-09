import '../calc/pricing.dart';
import '../logic/format.dart';
import '../models/models.dart';

class BillLine {
  const BillLine({
    this.date,
    required this.description,
    this.detail,
    this.quantity,
    this.unit,
    this.unitPrice,
    required this.amount,
  });
  final String? date;
  final String description;
  final String? detail;
  final double? quantity;
  final String? unit;
  final double? unitPrice;
  final double amount;
}

class BillDelivery {
  const BillDelivery({required this.address, required this.zone, required this.truck, required this.driver});
  final String address;
  final String zone;
  final String truck;
  final String driver;
}

class BillData {
  const BillData({
    required this.kind,
    required this.docNo,
    required this.refs,
    this.period,
    required this.date,
    required this.customer,
    this.delivery,
    required this.lines,
    required this.gross,
    this.discountLabel,
    required this.discountAmount,
    required this.total,
    this.paymentMethod,
    required this.paid,
    this.paidAt,
    this.signDate,
    this.note,
    required this.cancelled,
    required this.verifyToken,
    this.issuedBy,
    this.demo = false,
  });

  final DocKind kind;
  final String docNo;
  final List<({String label, String value})> refs;
  final ({String from, String to})? period;
  final String date;
  final CustomerSnapshot customer;
  final BillDelivery? delivery;
  final List<BillLine> lines;

  /// Product lines plus delivery before discount.
  final double gross;
  final String? discountLabel;
  final double discountAmount;
  final double total;

  /// Order bills carry a [PaymentMethod]; statements 'cash' | 'transfer' as text.
  final String? paymentMethod;
  final bool paid;
  final String? paidAt;

  /// Pre-filled date under the signatures; blank lines when null.
  final String? signDate;
  final String? note;
  final bool cancelled;
  final String verifyToken;
  final String? issuedBy;
  final bool demo;
}

BillData billFromOrder(Order o, DocKind kind, {Zone? zone, Driver? driver}) {
  final lines = o.items.map((it) {
    final off = lineDiscount(it.unitPrice, it.quantity, it.discountPerUnit);
    return BillLine(
      description: it.name,
      detail: off != 0
          ? 'ลด${it.unit}ละ ${formatNumber(it.discountPerUnit)} บาท (-${formatNumber(off)})'
          : null,
      quantity: it.quantity,
      unit: it.unit,
      unitPrice: it.unitPrice,
      amount: it.amount,
    );
  }).toList();
  final itemDiscount =
      o.items.fold<double>(0, (s, it) => s + lineDiscount(it.unitPrice, it.quantity, it.discountPerUnit));
  final billDiscountPart = o.discountAmount - itemDiscount - o.deliveryDiscount > 0.004;
  if (o.fulfillment == Fulfillment.delivery && o.trips > 0) {
    lines.add(BillLine(
      description: 'ค่าขนส่ง${zone != null ? ' ต.${zone.name}' : ''}',
      detail: o.truckSize != null ? 'รถ ${o.truckSize} คิว' : null,
      quantity: o.trips.toDouble(),
      unit: 'เที่ยว',
      unitPrice: o.feePerTrip,
      amount: o.feePerTrip * o.trips,
    ));
    if (o.remoteSurcharge > 0) {
      lines.add(BillLine(description: 'ค่าขนส่งเพิ่ม (พื้นที่ห่างไกล)', amount: o.remoteSurcharge));
    }
  }

  final refs = <({String label, String value})>[];
  if (kind == DocKind.receipt) {
    refs.add((label: 'อ้างอิงใบส่งของ', value: o.orderNo));
  } else if (o.receiptNo != null && o.receiptNo!.isNotEmpty) {
    refs.add((label: 'ใบเสร็จ', value: o.receiptNo!));
  }

  String? discountLabel;
  if (o.discountAmount != 0) {
    discountLabel = [
      itemDiscount != 0 ? 'ส่วนลดต่อคิว' : '',
      o.deliveryDiscount != 0 ? 'ส่วนลดค่าส่ง' : '',
      billDiscountPart
          ? 'ส่วนลด${o.discountType == DiscountType.percent ? ' ${formatNumber(o.discountValue)}% (ค่าสินค้า)' : ''}'
          : '',
    ].where((s) => s.isNotEmpty).join(' + ');
  }

  return BillData(
    kind: kind,
    docNo: kind == DocKind.receipt && (o.receiptNo ?? '').isNotEmpty ? o.receiptNo! : o.orderNo,
    refs: refs,
    date: kind == DocKind.receipt && (o.paidAt ?? '').isNotEmpty ? o.paidAt! : o.orderDate,
    customer: o.customer,
    delivery: o.fulfillment == Fulfillment.delivery
        ? BillDelivery(
            address: o.deliveryAddress,
            zone: zone?.name ?? '',
            truck: o.truckSize != null ? 'รถ ${o.truckSize} คิว × ${o.trips} เที่ยว' : '',
            driver: driver?.name ?? '',
          )
        : null,
    lines: lines,
    gross: o.subtotal + o.deliveryTotal,
    discountLabel: discountLabel,
    discountAmount: o.discountAmount,
    total: o.total,
    paymentMethod: o.paymentMethod.name,
    paid: o.paymentStatus == PaymentStatus.paid,
    paidAt: o.paidAt,
    signDate: kind == DocKind.delivery ? (o.deliveredAt ?? o.orderDate) : null,
    note: o.note,
    cancelled: o.cancelled,
    verifyToken: o.verifyToken,
    issuedBy: o.createdBy,
    demo: o.demo,
  );
}

BillData billFromStatement(Statement s, List<Order> orders) {
  final lines = orders
      .map((o) => BillLine(
            description: '${o.orderNo}${(o.receiptNo ?? '').isNotEmpty ? ' / ${o.receiptNo}' : ''}',
            detail: [
              o.items.map((it) => '${it.name} ${formatNumber(it.quantity)} ${it.unit}').join(', '),
              o.fulfillment == Fulfillment.delivery ? 'ส่ง ${o.trips} เที่ยว' : 'มารับเอง',
            ].join(' · '),
            date: o.orderDate,
            amount: o.total,
          ))
      .toList();
  final total = orders.fold<double>(0, (sum, o) => sum + o.total);
  return BillData(
    kind: DocKind.statement,
    docNo: s.statementNo,
    refs: const [],
    period: (from: s.periodFrom, to: s.periodTo),
    date: s.createdAt,
    customer: s.customer,
    lines: lines,
    gross: total,
    discountAmount: 0,
    total: s.total,
    paymentMethod: s.paymentMethod,
    paid: s.isCleared,
    paidAt: s.clearedAt,
    note: s.note,
    cancelled: false,
    verifyToken: s.verifyToken,
    issuedBy: s.createdBy,
    demo: s.demo,
  );
}

String paymentMethodLabel(String? method) => switch (method) {
      'cash' => PaymentMethod.cash.label,
      'transfer' => PaymentMethod.transfer.label,
      'cod' => PaymentMethod.cod.label,
      'credit' => PaymentMethod.credit.label,
      _ => '',
    };
