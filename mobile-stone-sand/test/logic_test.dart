import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/logic/customer_search.dart';
import 'package:mobile_stone_sand/logic/driver_pay.dart';
import 'package:mobile_stone_sand/logic/format.dart';
import 'package:mobile_stone_sand/logic/geo.dart';
import 'package:mobile_stone_sand/logic/latlng.dart';
import 'package:mobile_stone_sand/logic/menu_hints.dart';
import 'package:mobile_stone_sand/logic/order_status.dart';
import 'package:mobile_stone_sand/logic/places.dart';
import 'package:mobile_stone_sand/logic/promptpay.dart';
import 'package:mobile_stone_sand/logic/road_route.dart';
import 'package:mobile_stone_sand/logic/stats.dart';
import 'package:mobile_stone_sand/models/models.dart';

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180;
  final a = math.pow(math.sin(rad(lat2 - lat1) / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(rad(lng2 - lng1) / 2), 2);
  return 6371 * 2 * math.asin(math.sqrt(a));
}

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

  group('DeliveryStatus.parse', () {
    test('reads legacy waiting as dispatched', () {
      expect(DeliveryStatus.parse('waiting'), DeliveryStatus.dispatched);
      expect(DeliveryStatus.parse('dispatched'), DeliveryStatus.dispatched);
      expect(DeliveryStatus.parse('delivered'), DeliveryStatus.delivered);
      expect(DeliveryStatus.parse('pickup'), DeliveryStatus.pickup);
      expect(DeliveryStatus.dispatched.label, 'กำลังจัดส่ง');
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

    test('deducts partial payments once per statement', () {
      Statement stm(String id, String status, double paid) => Statement.fromRow({
            'id': id,
            'status': status,
            'total': 1500,
            'payments': [
              {'id': 'p-$id', 'amount': paid, 'method': 'cash', 'paid_at': '2026-10-05T03:00:00Z'},
            ],
          });
      final paid = statementPaidMap([stm('stm-1', 'open', 700), stm('stm-2', 'cleared', 999)]);
      expect(paid, {'stm-1': 700});
      final rows = summarizeOutstanding([
        base.copyWith(id: 'o1', total: 1000, statementId: 'stm-1'),
        base.copyWith(id: 'o2', total: 500, statementId: 'stm-1'),
        base.copyWith(id: 'o3', total: 200),
      ], paid);
      expect([rows.single.total, rows.single.unbilledTotal, rows.single.count], [1000, 200, 3]);
    });

    test('statement balance is the total less payments, 0 once cleared', () {
      final s = Statement.fromRow({
        'id': 's1',
        'status': 'open',
        'total': 5200,
        'payments': [
          {'id': 'p2', 'amount': 1000, 'method': 'transfer', 'paid_at': '2026-10-09T03:00:00Z'},
          {'id': 'p1', 'amount': 2000, 'method': 'cash', 'paid_at': '2026-10-02T03:00:00Z'},
        ],
      });
      expect([s.paidAmount, s.balance], [3000, 2200]);
      expect(s.payments.map((p) => p.id), ['p1', 'p2']);
      expect(Statement.fromRow({'status': 'cleared', 'total': 5200}).balance, 0);
    });
  });

  group('driverMessage', () {
    test('includes the map link and cash to collect', () {
      final msg = driverMessage(
        base,
        const Zone(id: 'thung-hua', name: 'ทุ่งฮั้ว', feePerCubic: 40, sortOrder: 1),
        null,
      );
      expect(msg, contains('https://www.google.com/maps?q=19.200000,99.600000'));
      expect(msg, contains('เก็บเงินปลายทาง'));
      expect(msg, contains('ตำบล: ทุ่งฮั้ว'));
      expect(msg, contains('093-123-4567'));
      expect(msg, isNot(contains('/d/')));
    });

    test('ends with the driver confirm link', () {
      final lines = driverMessage(base.copyWith(driverToken: 'abc123'), null, null).split('\n');
      expect(lines.last, 'https://order.goldenmole.pro/d/abc123');
      expect(lines[lines.length - 2], contains('แจ้งยอดเงินที่เก็บ'));
      expect(lines[lines.length - 3], '');
    });

    test('skips cash to collect when the order is billed on a statement', () {
      final msg = driverMessage(base.copyWith(driverToken: 'abc123', statementId: 's1'), null, null);
      expect(msg, isNot(contains('เก็บเงินปลายทาง')));
      expect(msg, isNot(contains('แจ้งยอดเงิน')));
      expect(msg, contains('/d/abc123'));
    });

    test('has no confirm link for cancelled orders', () {
      expect(driverMessage(base.copyWith(driverToken: 'abc123', cancelled: true), null, null), isNot(contains('/d/')));
    });

    test('labels the driver cash report in the history', () {
      const e = StatusLogEntry(at: '2026-10-09T08:00:00Z', by: 'คนขับ อ้ายโก (ลิงก์)', event: 'driver_cash:2130.00');
      expect(orderLogLabel(e, (_) => null), 'คนขับแจ้งเก็บเงินปลายทาง 2,130.00 บาท');
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
      String? zoneId,
      int? truckSize,
      double? roadDistanceKm,
      double deliveryDiscount = 0,
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
          deliveryDiscount: deliveryDiscount,
          total: total,
          paymentMethod: paymentMethod,
          paymentStatus: paymentStatus,
          zoneId: zoneId,
          truckSize: truckSize,
          roadDistanceKm: roadDistanceKm,
        );

    const delivery = DeliverySettings(nearKm: 1, driverPerKm5: 50, driverPerKm3: 30);
    const wangNuea = Zone(id: 'wang-nuea', name: 'วังเหนือ', feePerCubic: 0, driverFee: 700, driverFee3: 500, sortOrder: 1);
    const unset = Zone(id: 'unset', name: 'ใหม่', feePerCubic: 40, sortOrder: 2);
    Zone? zoneOf(String? id) => {'wang-nuea': wangNuea, 'unset': unset}[id];

    test('trip rate = tambon rate for the truck size + distance surcharge', () {
      final r5 = driverTripRate(wangNuea, 5, 3.2, delivery);
      expect([r5.base, r5.extra, r5.perTrip], [700, 150, 850]);
      final r3 = driverTripRate(wangNuea, 3, 0.8, delivery);
      expect([r3.base, r3.extra, r3.perTrip], [500, 0, 500]);
      // unknown truck size pays the 5-คิว rate
      expect(driverTripRate(wangNuea, null, null, delivery).perTrip, 700);
      // no base rate: nothing per trip, even with a surcharge
      expect(driverTripRate(unset, 5, 5, delivery).perTrip, 0);
      expect(driverTripRate(null, 5, 5, delivery).perTrip, 0);
    });

    test('pays the tambon rate × trips, else the stored wage, else the delivery fee after discount', () {
      final z = driverPayBreakdown(make(zoneId: 'wang-nuea', truckSize: 5, roadDistanceKm: 2.5, trips: 2), wangNuea, delivery);
      expect([z.amount, z.source], [1600, DriverPaySource.zone]);
      expect(suggestedDriverPay(make(zoneId: 'unset', driverWage: 450), unset, delivery), 450);
      final c = driverPayBreakdown(make(deliveryTotal: 1200, deliveryDiscount: 200), null, delivery);
      expect([c.amount, c.source], [1000, DriverPaySource.customerFee]);
    });

    test('settles the driver pay against the COD cash he holds', () {
      expect(settleWithDriver(700, 3000), (handover: 2300.0, topUp: 0.0));
      expect(settleWithDriver(1400, 500), (handover: 0.0, topUp: 900.0));
      expect(settleWithDriver(700, 700), (handover: 0.0, topUp: 0.0));
    });

    test('codToCollect', () {
      expect(codToCollect(make(paymentMethod: PaymentMethod.cod, total: 3060)), 3060);
      expect(codToCollect(make(paymentMethod: PaymentMethod.cod, paymentStatus: PaymentStatus.paid)), 0);
      expect(codToCollect(make(paymentMethod: PaymentMethod.credit, paymentStatus: PaymentStatus.credit)), 0);
      // billed on a statement: collected through เคลียร์บิล, not from the driver
      expect(codToCollect(make(paymentMethod: PaymentMethod.cod).copyWith(statementId: 'stm-1')), 0);
    });

    test('groups by driver with count, trips, suggested pay, COD cash and oldest date', () {
      final dues = summarizeDriverDues([
        make(id: 'o1', trips: 2, deliveryTotal: 1000, orderDate: '2026-10-07', paymentMethod: PaymentMethod.cod, total: 1800),
        make(id: 'o2', trips: 1, driverWage: 300, orderDate: '2026-10-03'),
        make(id: 'o3', driverId: 'drv-b', trips: 1, deliveryTotal: 2500),
        make(id: 'o4', driverId: 'drv-b', trips: 2, zoneId: 'wang-nuea', truckSize: 3, deliveryTotal: 0),
      ], zoneOf, delivery);
      expect(dues.map((d) => [d.driverId, d.count, d.trips, d.total, d.cash, d.oldestDate]).toList(), [
        ['drv-b', 2, 3, 3500, 0, '2026-10-05'],
        ['drv-a', 2, 3, 1300, 1800, '2026-10-03'],
      ]);
      expect(summarizeDriverDues([make(driverId: null)], zoneOf, delivery), isEmpty);
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
      expect(h['/orders'], 'กำลังจัดส่ง 0 ออเดอร์');
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

    const shopQr = '00020101021130730016A0000006770101120115010753700088205021916151060181105030020307PIRASIT'
        '53037645802TH620807040000630443A3';
    const head = '00020101021130730016A0000006770101120115010753700088205021916151060181105030020307PIRASIT'
        '53037645802TH';

    test("replaces the shop QR's reference 3 with the bill number and re-signs it", () {
      final p = billQrPayload(shopQr, ref: 'DO2610-0005');
      expect(p.substring(0, p.length - 4), '${head}6214' '0710DO26100005' '6304');
      expect(isThaiQrPayload(p), isTrue);
    });

    test('adds the amount to pay as a one-time QR', () {
      final p = billQrPayload(shopQr, ref: 'DO2610-0005', amount: 2130);
      expect(
        p.substring(0, p.length - 4),
        '000201010212'
        '30730016A0000006770101120115010753700088205021916151060181105030020307PIRASIT'
        '5303764' '54072130.00' '5802TH' '6214' '0710DO26100005' '6304',
      );
      expect(isThaiQrPayload(p), isTrue);
      expect(billQrPayload(shopQr, ref: 'DO1', amount: 0), contains('010211'));
    });

    test('adds reference 3 to a QR without additional data', () {
      final p = billQrPayload(promptPayPayload('0801234567')!, ref: 'BL2610-0004');
      expect(p, contains('5802TH' '6214' '0710BL26100004' '6304'));
      expect(isThaiQrPayload(p), isTrue);
    });

    test('leaves the payload alone when it is not a Thai QR or there is nothing to set', () {
      expect(billQrPayload('https://example.com', ref: 'DO1', amount: 50), 'https://example.com');
      expect(billQrPayload(shopQr, ref: '--'), shopQr);
      expect(qrReference('do2610-0005'), 'DO26100005');
    });
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

    test('returns the nearest point on the main road', () {
      final d = geo.distanceToMainRoad(19.2373, 99.6087)!;
      final pt = d.point!;
      expect(haversineKm(19.2373, 99.6087, pt[1], pt[0]), closeTo(d.km, 0.05));
    });
  });

  group('places near a pin', () {
    late Places places;
    setUpAll(() => places = Places.parse(File('assets/geo/places.json').readAsStringSync()));

    test('names the village at its centre', () {
      final p = places.describe(19.26998, 99.51045);
      expect(p.village?.name, 'บ้านหม้อ');
      expect(p.village?.km, 0);
    });

    test('names a soi the pin sits on', () {
      final p = places.describe(19.20684, 99.51763);
      expect(p.road?.name, matches(RegExp(r'ซอย\s*14')));
      expect(p.road!.m, lessThanOrEqualTo(10));
    });

    test('finds nothing far outside the district', () {
      final p = places.describe(18.2888, 99.4908);
      expect(p.village, isNull);
      expect(p.road, isNull);
      expect(p.text, '');
    });

    test('formats the address text', () {
      const p = PinPlace(village: (name: 'บ้านหม้อ', km: 0.3), road: (name: 'ซอย 4', m: 40));
      expect(p.text, 'ใกล้บ้านหม้อ · ซอย 4');
    });
  });

  group('road route', () {
    test('decodes a Google encoded polyline', () {
      final pts = decodePolyline(r'_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(pts, hasLength(3));
      expect(pts[0].lat, closeTo(38.5, 1e-9));
      expect(pts[0].lng, closeTo(-120.2, 1e-9));
      expect(pts[1].lat, closeTo(40.7, 1e-9));
      expect(pts[1].lng, closeTo(-120.95, 1e-9));
      expect(pts[2].lat, closeTo(43.252, 1e-9));
      expect(pts[2].lng, closeTo(-126.453, 1e-9));
    });

    test('rejects a truncated polyline', () {
      expect(() => decodePolyline('_p~iF~ps|U_'), throwsFormatException);
    });

    test('midpoint is halfway along the path', () {
      final mid = pathMidpoint(const [LatLngValue(19, 99.5), LatLngValue(19, 99.6), LatLngValue(19.1, 99.6)])!;
      final first = haversineKm(19, 99.5, 19, 99.6);
      final total = first + haversineKm(19, 99.6, 19.1, 99.6);
      expect(mid.lng, closeTo(99.6, 1e-9));
      expect(first + haversineKm(19, 99.6, mid.lat, mid.lng), closeTo(total / 2, 0.05));
      expect(pathMidpoint(const []), isNull);
    });
  });
}
