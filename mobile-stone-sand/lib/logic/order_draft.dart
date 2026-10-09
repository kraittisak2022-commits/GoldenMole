import '../calc/pricing.dart';
import '../models/models.dart';

class OrderDraft {
  const OrderDraft({
    required this.source,
    required this.orderDate,
    required this.customer,
    required this.items,
    required this.fulfillment,
    required this.deliveryAddress,
    required this.pinLat,
    required this.pinLng,
    required this.zoneId,
    required this.roadDistanceKm,
    required this.truckSize,
    required this.trips,
    required this.driverId,
    required this.feePerTrip,
    required this.remoteSurcharge,
    required this.deliveryDiscount,
    required this.discountType,
    required this.discountValue,
    required this.paymentMethod,
    required this.paidNow,
    required this.driverWage,
    required this.note,
  });

  final OrderSource source;

  /// YYYY-MM-DD; null lets the database use today (Bangkok).
  final String? orderDate;
  final Customer customer;
  final List<OrderItem> items;
  final Fulfillment fulfillment;
  final String deliveryAddress;
  final double? pinLat;
  final double? pinLng;
  final String? zoneId;
  final double? roadDistanceKm;
  final int? truckSize;
  final int trips;
  final String? driverId;
  final double feePerTrip;
  final double remoteSurcharge;
  final double deliveryDiscount;
  final DiscountType discountType;
  final double discountValue;
  final PaymentMethod paymentMethod;
  final bool paidNow;
  final double driverWage;
  final String note;
}

/// Totals for a draft or an edit; pickup orders carry no delivery charges.
Totals draftTotals({
  required List<OrderItem> items,
  required Fulfillment fulfillment,
  required num feePerTrip,
  required num trips,
  required num remoteSurcharge,
  required num deliveryDiscount,
  required DiscountType discountType,
  required num discountValue,
}) {
  final delivery = fulfillment == Fulfillment.delivery;
  return computeTotals(TotalsInput(
    items: items.map((it) => it.priceLine).toList(),
    feePerTrip: delivery ? feePerTrip : 0,
    trips: delivery ? trips : 0,
    remoteSurcharge: delivery ? remoteSurcharge : 0,
    deliveryDiscount: delivery ? deliveryDiscount : 0,
    discountType: discountType,
    discountValue: discountValue,
  ));
}
