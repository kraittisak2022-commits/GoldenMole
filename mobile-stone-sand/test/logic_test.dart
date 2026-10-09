import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/logic/customer_search.dart';
import 'package:mobile_stone_sand/logic/driver_pay.dart';
import 'package:mobile_stone_sand/logic/format.dart';
import 'package:mobile_stone_sand/logic/geo.dart';
import 'package:mobile_stone_sand/logic/latlng.dart';
import 'package:mobile_stone_sand/logic/menu_hints.dart';
import 'package:mobile_stone_sand/logic/order_status.dart';
import 'package:mobile_stone_sand/logic/promptpay.dart';
import 'package:mobile_stone_sand/logic/stats.dart';
import 'package:mobile_stone_sand/models/models.dart';

const base = Order(
  id: 'o1',
  orderNo: 'DO6910-0001',
  source: OrderSource.shop,
  orderDate: '2026-10-08',
  customerId: 'c1',
  customer: CustomerSnapshot(name: 'สมชาย ใจดี', phone: '0931234567'),
  fulfillment: Fulfillment.delivery,
  deliveryAddress: 'บ้านทุ่งฮั้ว หมู่ 3',
  pinLat: 19.2,
  pinLng: 99.6,
  zoneId: 'thung-hua',
  roadDistanceKm: 1.2,
  truckSize: 5,
  trips: 2,
  feePerTrip: 300,
  subtotal: 2000,
  deliveryTotal: 600,
  total: 2600,
  paymentMethod: PaymentMethod.cod,
  paymentStatus: PaymentStatus.unpaid,
  deliveryStatus: DeliveryStatus.waiting,
  verifyToken: 't',
  items: [
    OrderItem(productId: 'small-stone', name: 'หินเล็กคละ', unit: 'คิว', unitPrice: 400, quantity: 5, amount: 2000),
  ],
);

void main() {
  group('date helpers', () {
    test('moves across month and year ends', () {
      expect(shiftIsoDate('2026-10-31', 1), '2026-11-01');
      expect(shiftIsoDate('2026-01-01', -1), '2025-12-31');
    });

    test('gives the calendar month of a date', () {
      expect(monthRange('2026-02-14'), (from: '2026-02-01', to: '2026-02-28'));
      expect(monthRange('2028-02-03'), (from: '2028-02-01', to: '2028-02-29'));
    });

    test('writes the weekday and Buddhist year', () {
      expect(formatDateLongTh('2026-10-08'), 'พฤหัสบดี 8 ตุลาคม 2569');
    });
  });

  group('parseDocNo', () {
    test('parses the three document types', () {
      expect(parseDocNo('DO2610-0001'), (kind: DocKind.delivery, year: 2026, month: 10, seq: 1));
      expect(parseDocNo('TS2610-0007'), (kind: DocKind.delivery, year: 2026, month: 10, seq: 7));
      expect(parseDocNo('RE2610-0042')?.kind, DocKind.receipt);
      expect(parseDocNo('BL2612-1234'), (kind: DocKind.statement, year: 2026, month: 12, seq: 1234));
    });

    test('rejects malformed numbers', () {
      expect(parseDocNo('XX2610-0001'), isNull);
      expect(parseDocNo('DO2613-0001'), isNull);
      expect(parseDocNo('DO2610-01'), isNull);
    });
  });

  group('format helpers', () {
    test('formats Buddhist-year dates', () => expect(formatDateTh('2026-10-08'), '08/10/2569'));
    test('formats Thai phone numbers', () {
      expect(formatPhone('0931234567'), '093-123-4567');
      expect(formatPhone('054 123 456'), '05-412-3456');
    });
    test('formats money', () {
      expect(formatMoney(1234.5), '1,234.50');
      expect(formatNumber(1250), '1,250');
      expect(formatNumber(1.5), '1.5');
    });
  });

  group('matchesFilter', () {
    test('classifies payment and delivery state', () {
      expect(matchesFilter(base, OrderFilter.unpaid), true);
      expect(matchesFilter(base, OrderFilter.waiting), true);
      expect(matchesFilter(base, OrderFilter.uncleared), true);
      expect(matchesFilter(base, OrderFilter.credit), false);
      expect(matchesFilter(base.copyWith(paymentStatus: PaymentStatus.credit), OrderFilter.credit), true);
      expect(
        matchesFilter(base.copyWith(paymentStatus: PaymentStatus.credit, cleared: true), OrderFilter.credit),
        false,
      );
    });

    test('hides cancelled orders from status filters', () {
      final c = base.copyWith(cancelled: true);
      expect(matchesFilter(c, OrderFilter.unpaid), false);
      expect(matchesFilter(c, OrderFilter.all), true);
      expect(matchesFilter(c, OrderFilter.cancelled), true);
      expect(outstanding(c), 0);
    });
  });

  group('matchesSearch', () {
    test('finds by name, doc number and phone digits', () {
      expect(matchesSearch(base, 'สมชาย'), true);
      expect(matchesSearch(base, 'do6910'), true);
      expect(matchesSearch(base, '093-123'), true);
      expect(matchesSearch(base, 'สมหญิง'), false);
    });

    test('finds by the customer ชื่อเรียก', () {
      expect(matchesSearch(base.copyWith(customerAliases: ['เสี่ยบาส']), 'บาส'), true);
    });
  });

  group('summarizeOutstanding', () {
    test('groups per customer and separates orders already on a statement', () {
      final rows = summarizeOutstanding([
        base,
        base.copyWith(id: 'o2', total: 1000, orderDate: '2026-10-01', statementId: 'stm-1'),
        base.copyWith(id: 'o3', cleared: true),
        base.copyWith(id: 'o4', customerId: 'c2', total: 500),
      ]);
      expect(rows, hasLength(2));
      expect(rows[0].customerId, 'c1');
      expect(rows[0].total, 3600);
      expect(rows[0].count, 2);
      expect(rows[0].unbilledTotal, 2600);
      expect(rows[0].unbilledCount, 1);
      expect(rows[0].oldestDate, '2026-10-01');
      expect(rows[1].customerId, 'c2');
      expect(rows[1].total, 500);
    });

    test('keeps ร้านวัสดุ and ท่าทราย orders of the same customer in separate rows', () {
      final rows = summarizeOutstanding([base, base.copyWith(id: 'o2', source: OrderSource.pit, total: 800)]);
      expect(rows.map((r) => [r.customerId, r.source, r.total]).toList(), [
        ['c1', OrderSource.shop, 2600],
        ['c1', OrderSource.pit, 800],
      ]);
    });
  });

  group('driverMessage', () {
    test('includes the map link and cash to collect', () {
      final msg = driverMessage(
        base,
        const Zone(id: 'thung-hua', name: 'ทุ่งฮั้ว', feeMin: 300, feeMax: 400, sortOrder: 1),
        null,
      );
      expect(msg, contains('https://www.google.com/maps?q=19.200000,99.600000'));
      expect(msg, contains('เก็บเงินปลายทาง'));
      expect(msg, contains('ตำบล: ทุ่งฮั้ว'));
      expect(msg, contains('093-123-4567'));
    });
  });

  group('driver pay', () {
    Order make({
      String id = 'o1',
      String? driverId = 'drv-a',
      String orderDate = '2026-10-05',
      int trips = 1,
      double driverWage = 0,
      double deliveryTotal = 600,
      double total = 2000,
      PaymentMethod paymentMethod = PaymentMethod.cash,
      PaymentStatus paymentStatus = PaymentStatus.unpaid,
    }) =>
        Order(
          id: id,
          orderNo: id,
          orderDate: orderDate,
          customerId: 'c',
          customer: const CustomerSnapshot(),
          driverId: driverId,
          trips: trips,
          driverWage: driverWage,
          deliveryTotal: deliveryTotal,
          total: total,
          paymentMethod: paymentMethod,
          paymentStatus: paymentStatus,
        );

    test('uses the wage set on the order, else the delivery fee', () {
      expect(suggestedDriverPay(make(driverWage: 450)), 450);
      expect(suggestedDriverPay(make(deliveryTotal: 1200)), 1200);
    });

    test('codToCollect', () {
      expect(codToCollect(make(paymentMethod: PaymentMethod.cod, total: 3060)), 3060);
      expect(codToCollect(make(paymentMethod: PaymentMethod.cod, paymentStatus: PaymentStatus.paid)), 0);
      expect(codToCollect(make(paymentMethod: PaymentMethod.credit, paymentStatus: PaymentStatus.credit)), 0);
    });

    test('groups by driver with count, trips, suggested pay, COD cash and oldest date', () {
      final dues = summarizeDriverDues([
        make(id: 'o1', trips: 2, deliveryTotal: 1000, orderDate: '2026-10-07', paymentMethod: PaymentMethod.cod, total: 1800),
        make(id: 'o2', trips: 1, driverWage: 300, orderDate: '2026-10-03'),
        make(id: 'o3', driverId: 'drv-b', trips: 1, deliveryTotal: 2500),
      ]);
      expect(dues.map((d) => [d.driverId, d.count, d.trips, d.total, d.cash, d.oldestDate]).toList(), [
        ['drv-b', 1, 1, 2500, 0, '2026-10-05'],
        ['drv-a', 2, 3, 1300, 1800, '2026-10-03'],
      ]);
      expect(summarizeDriverDues([make(driverId: null)]), isEmpty);
    });
  });

  group('periodStats', () {
    Order make({
      bool cancelled = false,
      double total = 1200,
      int trips = 0,
      PaymentStatus paymentStatus = PaymentStatus.paid,
      OrderSource source = OrderSource.shop,
    }) =>
        Order(
          id: 'x',
          orderNo: 'x',
          orderDate: '2026-10-01',
          customerId: 'c',
          customer: const CustomerSnapshot(),
          cancelled: cancelled,
          subtotal: 1000,
          deliveryTotal: 300,
          discountAmount: 100,
          total: total,
          driverWage: 200,
          trips: trips,
          paymentStatus: paymentStatus,
          source: source,
          items: const [
            OrderItem(productId: 'fill-sand', name: 'ทรายถม', unit: 'คิว', unitPrice: 220, quantity: 5, amount: 1100),
          ],
        );

    test('sums live orders and ignores cancelled ones', () {
      final s = periodStats([make(), make(paymentStatus: PaymentStatus.credit), make(cancelled: true)]);
      expect(s.orderCount, 2);
      expect(s.net, 2400);
      expect(s.deliveryFees, 600);
      expect(s.driverWages, 400);
      expect(s.paid, 1200);
      expect(s.quantityByProduct.single.quantity, 10);
      expect(s.quantityByProduct.single.amount, 2200);
    });

    test('totals คิว, trips and money still to collect', () {
      final s = periodStats([
        make(trips: 2),
        make(trips: 1, paymentStatus: PaymentStatus.unpaid),
        make(trips: 3, cancelled: true),
      ]);
      expect(s.quantity, 10);
      expect(s.trips, 3);
      expect(s.outstanding, 1200);
    });

    test('splits live orders by source', () {
      final s = periodStats([
        make(source: OrderSource.pit),
        make(source: OrderSource.pit, total: 500),
        make(),
        make(),
        make(source: OrderSource.pit, cancelled: true),
      ]);
      expect([s.bySource[OrderSource.pit]!.orderCount, s.bySource[OrderSource.pit]!.net], [2, 1700]);
      expect([s.bySource[OrderSource.shop]!.orderCount, s.bySource[OrderSource.shop]!.net], [2, 2400]);
    });
  });

  group('menuHints', () {
    test('shows counts once they are known', () {
      final h = menuHints(const MenuCounts(
        ordersToday: 3,
        waitingDelivery: 0,
        customers: 1250,
        openStatements: 2,
        driverUnpaid: 5,
        drivers: 4,
        products: 6,
      ));
      expect(h['/'], 'วันนี้ 3 ออเดอร์');
      expect(h['/orders'], 'รอส่ง 0 ออเดอร์');
      expect(h['/customers'], '1,250 ราย');
      expect(h['/statements'], 'รอเก็บเงิน 2 ใบ');
      expect(h['/drivers'], '4 คัน');
    });

    test('falls back to a description while loading', () {
      expect(menuHints(const MenuCounts())['/customers'], 'ข้อมูลลูกค้า');
    });
  });

  group('customer search', () {
    const name = 'ร้านสินทวีวังเหนือ';
    const aliases = ['เสี่ยบาส', 'บาส'];
    const phone = '0931234567';

    test('parseAliases splits, trims and drops blanks and repeats', () {
      expect(parseAliases(' เสี่ยบาส , บาส\nเฮียบาส,, บาส '), ['เสี่ยบาส', 'บาส', 'เฮียบาส']);
      expect(parseAliases(''), isEmpty);
    });

    test('finds a shop by any of its other names', () {
      expect(matchesCustomer(name, aliases, phone, 'เสี่ยบาส'), true);
      expect(matchesCustomer(name, aliases, phone, 'สินทวี'), true);
      expect(matchesCustomer(name, aliases, phone, '123'), true);
      expect(matchesCustomer(name, aliases, phone, 'สมชาย'), false);
    });

    test('names the alias only when the main name did not match', () {
      expect(matchedAlias(name, aliases, 'เสี่ย'), 'เสี่ยบาส');
      expect(matchedAlias(name, aliases, 'สินทวี'), isNull);
    });
  });

  group('promptpay', () {
    test('crc16 matches the CRC-16/CCITT-FALSE check value', () => expect(crc16('123456789'), '29B1'));

    test('normalises phone and tax id', () {
      expect(promptPayTarget('065-812-4686'), (tag: '01', value: '0066658124686'));
      expect(promptPayTarget('0523566002017'), (tag: '02', value: '0523566002017'));
      expect(promptPayTarget('12345'), isNull);
    });

    test('builds a static payload for a phone number', () {
      final p = promptPayPayload('0801234567')!;
      const body = '000201010211' '29370016A00000067701011101130066801234567' '5303764' '5802TH' '6304';
      expect(p.substring(0, p.length - 4), body);
      expect(p.substring(p.length - 4), crc16(body));
    });

    test('adds a dynamic amount', () {
      final p = promptPayPayload('0523566002017', 1500)!;
      expect(p, contains('010212'));
      expect(p, contains('29370016A000000677010111' '02130523566002017'));
      expect(p, contains('54071500.00'));
      expect(p.substring(p.length - 4), crc16(p.substring(0, p.length - 4)));
    });

    test('rejects unknown ids', () => expect(promptPayPayload('abc'), isNull));
  });

  group('parseLatLng', () {
    test('reads plain coordinates', () {
      expect(parseLatLng('19.1453, 99.6187'), const LatLngValue(19.1453, 99.6187));
      expect(parseLatLng('19.1453 99.6187'), const LatLngValue(19.1453, 99.6187));
    });

    test('reads Google Maps URLs', () {
      expect(parseLatLng('https://www.google.com/maps/@19.1453,99.6187,15z'), const LatLngValue(19.1453, 99.6187));
      expect(parseLatLng('https://maps.google.com/?q=19.1453,99.6187'), const LatLngValue(19.1453, 99.6187));
      expect(
        parseLatLng(
          'https://www.google.com/maps/place/x/@19.1,99.6,17z/data=!3m1!4b1!4m5!3m4!1s0x0:0x0!8m2!3d19.1453!4d99.6187',
        ),
        const LatLngValue(19.1453, 99.6187),
      );
    });

    test('rejects text and short links', () {
      expect(parseLatLng('บ้านทุ่งฮั้ว'), isNull);
      expect(parseLatLng('https://maps.app.goo.gl/abc123'), isNull);
      expect(parseLatLng('200, 99'), isNull);
    });
  });

  group('geo helpers', () {
    late GeoData geo;
    setUpAll(() {
      String read(String f) => File('assets/geo/$f').readAsStringSync();
      geo = GeoData.parse(read('district.json'), read('tambons.json'), read('main-roads.json'));
    });

    test('finds the tambon of known places', () {
      expect(geo.findTambon(19.14533, 99.61872)?.name, matches(RegExp('วังเหนือ|วังซ้าย')));
      expect(geo.findTambon(18.9898, 99.61652)?.name, 'ร่องเคาะ');
    });

    test('returns null outside อ.วังเหนือ', () {
      expect(geo.isInDistrict(18.2888, 99.4908), false);
      expect(geo.findTambon(18.2888, 99.4908), isNull);
    });

    test('measures ~0 km on highway 120 in town', () {
      final d = geo.distanceToMainRoad(19.14407, 99.62455);
      expect(d, isNotNull);
      expect(d!.km, lessThan(0.5));
    });

    test('every tambon centre is within reach of a main road', () {
      for (final c in [
        ('ทุ่งฮั้ว', 19.2373, 99.6087),
        ('วังแก้ว', 19.3411, 99.6244),
        ('วังทอง', 19.0675, 99.714),
        ('ร่องเคาะ', 18.9835, 99.5963),
      ]) {
        final d = geo.distanceToMainRoad(c.$2, c.$3);
        expect(d, isNotNull, reason: c.$1);
        expect(d!.km, lessThan(10), reason: c.$1);
      }
    });
  });
}
