import 'dart:math' as math;

import '../calc/delivery_fee.dart';
import '../models/models.dart';
import 'order_status.dart' show stableSorted;

class DriverTripRate {
  const DriverTripRate({required this.base, required this.extra, required this.perTrip});

  static const none = DriverTripRate(base: 0, extra: 0, perTrip: 0);

  /// Rate for the truck size; trucks of unknown size get the normal 5-คิว rate. 0 = not set.
  final double base;

  /// Distance surcharge per trip at the driver's baht/km rate for the truck size.
  final double extra;

  /// base + extra, or 0 while the base rate is not set.
  final double perTrip;
}

DriverTripRate driverTripRate(Zone? zone, int? truckSize, double? roadDistanceKm, DeliverySettings delivery) {
  if (zone == null) return DriverTripRate.none;
  final base = truckSize == 3 ? zone.driverFee3 : zone.driverFee;
  final extra =
      distanceSurcharge(roadDistanceKm, nearKm: delivery.nearKm, perKm: perKmFor(truckSize, delivery)).toDouble();
  return DriverTripRate(base: base, extra: extra, perTrip: base > 0 ? base + extra : 0);
}

/// zone = tambon rate for the truck size; stored = wage saved on the order; customerFee = what the customer paid for delivery.
enum DriverPaySource { zone, stored, customerFee }

class DriverPayBreakdown {
  const DriverPayBreakdown({required this.amount, required this.source, required this.rate});
  final double amount;
  final DriverPaySource source;
  final DriverTripRate rate;
}

/// Delivery charged to the customer on the order, after its delivery discount.
double customerDeliveryFee(Order o) => math.max(0, o.deliveryTotal - o.deliveryDiscount);

/// Default amount to pay the driver: (tambon rate for the truck size + distance surcharge) × trips.
/// While the tambon has no rate for that truck size it uses the wage stored on the order,
/// and failing that the delivery fee the customer paid for the order.
DriverPayBreakdown driverPayBreakdown(Order o, Zone? zone, DeliverySettings delivery) {
  final rate = driverTripRate(zone, o.truckSize, o.roadDistanceKm, delivery);
  if (rate.perTrip > 0) return DriverPayBreakdown(amount: rate.perTrip * o.trips, source: DriverPaySource.zone, rate: rate);
  if (o.driverWage > 0) return DriverPayBreakdown(amount: o.driverWage, source: DriverPaySource.stored, rate: rate);
  return DriverPayBreakdown(amount: customerDeliveryFee(o), source: DriverPaySource.customerFee, rate: rate);
}

double suggestedDriverPay(Order o, Zone? zone, DeliverySettings delivery) =>
    driverPayBreakdown(o, zone, delivery).amount;

/// The driver keeps his pay out of the COD money he collected: he hands the rest to the shop,
/// or the shop pays him what the COD money did not cover.
({double handover, double topUp}) settleWithDriver(double pay, double cod) =>
    (handover: math.max(0, cod - pay), topUp: math.max(0, pay - cod));

/// Cash the driver collected from the customer (เก็บเงินปลายทาง) and still has to hand to the shop.
/// An order billed on a statement is paid through เคลียร์บิล instead, so the driver owes nothing for it.
double codToCollect(Order o) =>
    o.paymentMethod == PaymentMethod.cod && o.paymentStatus != PaymentStatus.paid && o.statementId == null
        ? o.total
        : 0;

class DriverDue {
  DriverDue({required this.driverId, required this.oldestDate});
  final String driverId;
  int count = 0;
  int trips = 0;
  double total = 0;
  double cash = 0;
  String oldestDate;
}

List<DriverDue> summarizeDriverDues(
  List<Order> orders,
  Zone? Function(String? zoneId) zoneOf,
  DeliverySettings delivery,
) {
  final map = <String, DriverDue>{};
  for (final o in orders) {
    final id = o.driverId;
    if (id == null || id.isEmpty) continue;
    final row = map.putIfAbsent(id, () => DriverDue(driverId: id, oldestDate: o.orderDate));
    row.count += 1;
    row.trips += o.trips;
    row.total += suggestedDriverPay(o, zoneOf(o.zoneId), delivery);
    row.cash += codToCollect(o);
    if (o.orderDate.compareTo(row.oldestDate) < 0) row.oldestDate = o.orderDate;
  }
  return stableSorted(map.values, (a, b) => b.total.compareTo(a.total));
}
