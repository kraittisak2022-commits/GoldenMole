import '../models/models.dart';
import 'order_status.dart' show stableSorted;

class SourceStats {
  int orderCount = 0;
  double net = 0;
  double quantity = 0;
}

class ProductQuantity {
  ProductQuantity({required this.name, required this.unit});
  final String name;
  final String unit;
  double quantity = 0;
  double amount = 0;
}

class PeriodStats {
  const PeriodStats({
    required this.orderCount,
    required this.productSales,
    required this.deliveryFees,
    required this.discounts,
    required this.net,
    required this.driverWages,
    required this.paid,
    required this.outstanding,
    required this.quantity,
    required this.trips,
    required this.quantityByProduct,
    required this.bySource,
  });
  final int orderCount;
  final double productSales;
  final double deliveryFees;
  final double discounts;
  final double net;
  final double driverWages;
  final double paid;

  /// Unpaid and credit totals still to collect.
  final double outstanding;
  final double quantity;
  final int trips;
  final List<ProductQuantity> quantityByProduct;
  final Map<OrderSource, SourceStats> bySource;
}

PeriodStats periodStats(List<Order> orders) {
  final live = orders.where((o) => !o.cancelled).toList();
  final byProduct = <String, ProductQuantity>{};
  for (final o in live) {
    for (final it in o.items) {
      final key = it.productId ?? it.name;
      final row = byProduct.putIfAbsent(key, () => ProductQuantity(name: it.name, unit: it.unit));
      row.quantity += it.quantity;
      row.amount += it.amount;
    }
  }
  double sum(double Function(Order o) f) => live.fold(0, (s, o) => s + f(o));
  final bySource = {for (final s in OrderSource.values) s: SourceStats()};
  for (final o in live) {
    final row = bySource[o.source]!;
    row.orderCount += 1;
    row.net += o.total;
    row.quantity += o.items.fold<double>(0, (s, it) => s + it.quantity);
  }
  final quantityByProduct = stableSorted(byProduct.values, (a, b) => b.amount.compareTo(a.amount));
  return PeriodStats(
    orderCount: live.length,
    productSales: sum((o) => o.subtotal),
    deliveryFees: sum((o) => o.deliveryTotal),
    discounts: sum((o) => o.discountAmount),
    net: sum((o) => o.total),
    driverWages: sum((o) => o.driverWage),
    paid: sum((o) => o.paymentStatus == PaymentStatus.paid ? o.total : 0),
    outstanding: sum((o) => o.paymentStatus == PaymentStatus.paid ? 0 : o.total),
    quantity: quantityByProduct.fold(0, (s, p) => s + p.quantity),
    trips: live.fold(0, (s, o) => s + o.trips),
    quantityByProduct: quantityByProduct,
    bySource: bySource,
  );
}
