import 'format.dart';

class MenuCounts {
  const MenuCounts({
    this.ordersToday,
    this.waitingDelivery,
    this.customers,
    this.openStatements,
    this.driverUnpaid,
    this.drivers,
    this.products,
  });
  final int? ordersToday;
  final int? waitingDelivery;
  final int? customers;
  final int? openStatements;
  final int? driverUnpaid;
  final int? drivers;
  final int? products;
}

/// Caption under each menu card, keyed by route; a count still loading falls back to a description.
Map<String, String> menuHints(MenuCounts c) {
  String n(int? v, String Function(String v) text, String fallback) =>
      v == null ? fallback : text(formatNumber(v));
  return {
    '/': n(c.ordersToday, (v) => 'วันนี้ $v ออเดอร์', 'สรุปยอดวันนี้'),
    '/orders': n(c.waitingDelivery, (v) => 'รอส่ง $v ออเดอร์', 'ติดตามออเดอร์'),
    '/customers': n(c.customers, (v) => '$v ราย', 'ข้อมูลลูกค้า'),
    '/statements': n(c.openStatements, (v) => 'รอเก็บเงิน $v ใบ', 'ใบวางบิล'),
    '/driver-pay': n(c.driverUnpaid, (v) => 'รอจ่าย $v ออเดอร์', 'ค่าจ้างคนขับ'),
    '/bill-summary': 'กำไรและสถานะแต่ละบิล',
    '/drivers': n(c.drivers, (v) => '$v คัน', 'รถและคนขับ'),
    '/settings': n(c.products, (v) => 'สินค้า $v รายการ', 'สินค้า ราคา ค่าส่ง'),
    '/new': 'เปิดออเดอร์ใหม่',
  };
}
