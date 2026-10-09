import 'dart:math' as math;

const _epsilon = 2.220446049250313e-16;

double round2(num n) => jsRound((n + _epsilon) * 100) / 100;

/// JS `Math.round`: halves round towards +infinity.
double jsRound(num n) => (n + 0.5).floorToDouble();

double lineAmount(num unitPrice, num quantity) {
  if (!(unitPrice > 0) || !(quantity > 0)) return 0;
  return round2(unitPrice * quantity);
}

/// บาทต่อคิว off one line, capped at the unit price.
double lineDiscount(num unitPrice, num quantity, [num discountPerUnit = 0]) {
  if (!(discountPerUnit > 0) || !(quantity > 0)) return 0;
  return round2(math.min(discountPerUnit, math.max(0, unitPrice)) * quantity);
}

class PriceLine {
  const PriceLine({required this.unitPrice, required this.quantity, this.discountPerUnit = 0});
  final num unitPrice;
  final num quantity;
  final num discountPerUnit;
}

enum DiscountType {
  baht,
  percent;

  static DiscountType parse(Object? v) => v == 'percent' ? percent : baht;
}

/// Total คิว ordered; the per-คิว delivery fee is charged on this.
double totalCubic(Iterable<num> quantities) =>
    round2(quantities.fold<double>(0, (s, q) => s + (q > 0 ? q : 0)));

class TotalsInput {
  const TotalsInput({
    required this.items,
    this.feePerCubic = 0,
    required this.feePerTrip,
    required this.trips,
    required this.remoteSurcharge,
    this.deliveryDiscount = 0,
    required this.discountType,
    required this.discountValue,
  });
  final List<PriceLine> items;

  /// Delivery fee per คิว ordered (the tambon rate).
  final num feePerCubic;
  final num feePerTrip;
  final num trips;
  final num remoteSurcharge;
  final num deliveryDiscount;
  final DiscountType discountType;
  final num discountValue;
}

class Totals {
  const Totals({
    required this.subtotal,
    required this.deliveryTotal,
    required this.itemDiscount,
    required this.deliveryDiscount,
    required this.billDiscount,
    required this.discountAmount,
    required this.total,
    required this.totalQuantity,
  });
  final double subtotal;

  /// The full delivery fee, before ส่วนลดค่าส่ง.
  final double deliveryTotal;
  final double itemDiscount;
  final double deliveryDiscount;
  final double billDiscount;
  final double discountAmount;
  final double total;
  final double totalQuantity;
}

double _nz(num? v) => (v == null || v.isNaN) ? 0 : v.toDouble();

/// Per-คิว discounts come off each line first. Percent discounts then apply to the discounted
/// product subtotal only; baht discounts can also cover delivery. The total never goes below zero.
Totals computeTotals(TotalsInput input) {
  final subtotal = round2(input.items.fold<double>(0, (s, it) => s + lineAmount(it.unitPrice, it.quantity)));
  final totalQuantity = totalCubic(input.items.map((it) => it.quantity));
  final trips = math.max(0, _nz(input.trips).floor());
  final deliveryTotal = round2(math.max(0, _nz(input.feePerCubic)) * totalQuantity +
      math.max(0, _nz(input.feePerTrip)) * trips +
      math.max(0, _nz(input.remoteSurcharge)));
  final gross = subtotal + deliveryTotal;
  final itemDiscount = round2(input.items
      .fold<double>(0, (s, it) => s + lineDiscount(it.unitPrice, it.quantity, it.discountPerUnit)));
  final deliveryDiscount =
      round2(math.min(math.max(0, _nz(input.deliveryDiscount)), deliveryTotal));
  final value = math.max(0, _nz(input.discountValue));
  final billValue = input.discountType == DiscountType.percent
      ? ((subtotal - itemDiscount) * math.min(value, 100)) / 100
      : value;
  final discountAmount = round2(math.min(itemDiscount + deliveryDiscount + billValue, gross));
  return Totals(
    subtotal: subtotal,
    deliveryTotal: deliveryTotal,
    itemDiscount: itemDiscount,
    deliveryDiscount: deliveryDiscount,
    billDiscount: round2(discountAmount - itemDiscount - deliveryDiscount),
    discountAmount: discountAmount,
    total: round2(gross - discountAmount),
    totalQuantity: totalQuantity,
  );
}
