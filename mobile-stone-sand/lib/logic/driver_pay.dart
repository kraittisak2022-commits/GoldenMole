import '../models/models.dart';
import 'order_status.dart' show stableSorted;

/// Default amount to pay the driver: the wage set on the order, else the delivery fee charged.
double suggestedDriverPay(Order o) => o.driverWage > 0 ? o.driverWage : o.deliveryTotal;

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

List<DriverDue> summarizeDriverDues(List<Order> orders) {
  final map = <String, DriverDue>{};
  for (final o in orders) {
    final id = o.driverId;
    if (id == null || id.isEmpty) continue;
    final row = map.putIfAbsent(id, () => DriverDue(driverId: id, oldestDate: o.orderDate));
    row.count += 1;
    row.trips += o.trips;
    row.total += suggestedDriverPay(o);
    row.cash += codToCollect(o);
    if (o.orderDate.compareTo(row.oldestDate) < 0) row.oldestDate = o.orderDate;
  }
  return stableSorted(map.values, (a, b) => b.total.compareTo(a.total));
}
