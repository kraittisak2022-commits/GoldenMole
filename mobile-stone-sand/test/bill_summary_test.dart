import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/logic/bill_summary.dart';
import 'package:mobile_stone_sand/models/models.dart';
import 'package:mobile_stone_sand/screens/bill_summary_screen.dart';

Order _o({
  Fulfillment fulfillment = Fulfillment.delivery,
  String? driverId = 'drv-a',
  String? driverPayoutId,
  double driverWage = 500,
  double deliveryTotal = 800,
  double deliveryDiscount = 100,
  double total = 5700,
  PaymentMethod paymentMethod = PaymentMethod.cash,
  PaymentStatus paymentStatus = PaymentStatus.paid,
  DeliveryStatus deliveryStatus = DeliveryStatus.delivered,
  bool cleared = true,
  bool cancelled = false,
  String? statementId,
}) =>
    Order(
      id: 'o1',
      orderNo: 'TS6910-0001',
      orderDate: '2026-10-09',
      customerId: 'c1',
      customer: const CustomerSnapshot(name: 'ลูกค้า'),
      trips: 2,
      fulfillment: fulfillment,
      driverId: driverId,
      driverPayoutId: driverPayoutId,
      driverWage: driverWage,
      deliveryTotal: deliveryTotal,
      deliveryDiscount: deliveryDiscount,
      total: total,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      deliveryStatus: deliveryStatus,
      cleared: cleared,
      cancelled: cancelled,
      statementId: statementId,
    );

void main() {
  group('summarizeBill', () {
    test('splits the bill into goods and delivery, and estimates ค่ารถ until paid', () {
      final s = summarizeBill(_o());
      expect(s.revenue, 5700);
      expect(s.deliveryFee, 700);
      expect(s.goods, 5000);
      expect(s.driverCost, 500);
      expect(s.driverCostEstimated, isTrue);
      expect(s.net, 5200);
      expect(s.deliveryMargin, 200);
    });

    test('uses the amount paid once the driver is paid out', () {
      final s = summarizeBill(_o(driverPayoutId: 'dpo-1', driverWage: 900));
      expect(s.driverCostEstimated, isFalse);
      expect(s.net, 4800);
      expect(s.deliveryMargin, -200);
    });

    test('pickup has no driver cost; unpaid money is receivable', () {
      final s = summarizeBill(_o(
        fulfillment: Fulfillment.pickup,
        deliveryStatus: DeliveryStatus.pickup,
        driverId: null,
        deliveryTotal: 0,
        deliveryDiscount: 0,
        total: 5000,
        paymentStatus: PaymentStatus.unpaid,
        cleared: false,
      ));
      expect(s.driverCost, 0);
      expect(s.net, 5000);
      expect(s.receivable, 5000);
      expect(s.received, 0);
    });

    test('cancelled orders are zero and left out of the totals', () {
      final cancelled = summarizeBill(_o(cancelled: true));
      expect(cancelled.revenue, 0);
      final t = totalBills([summarizeBill(_o()), cancelled]);
      expect(t.count, 1);
      expect(t.net, 5200);
      expect(t.driverCostPending, 500);
    });
  });

  test('billStage walks driver, delivery, money and driver pay in order', () {
    expect(billStage(_o(driverId: null, deliveryStatus: DeliveryStatus.waiting)), BillStage.needDriver);
    expect(billStage(_o(deliveryStatus: DeliveryStatus.waiting)), BillStage.waitDelivery);
    expect(billStage(_o(deliveryStatus: DeliveryStatus.dispatched)), BillStage.onTheWay);
    expect(
      billStage(_o(paymentMethod: PaymentMethod.cod, paymentStatus: PaymentStatus.unpaid, cleared: false)),
      BillStage.driverCash,
    );
    expect(
      billStage(_o(paymentMethod: PaymentMethod.credit, paymentStatus: PaymentStatus.credit, cleared: false)),
      BillStage.unbilled,
    );
    expect(
      billStage(_o(
        paymentMethod: PaymentMethod.credit,
        paymentStatus: PaymentStatus.credit,
        cleared: false,
        statementId: 's1',
      )),
      BillStage.billed,
    );
    expect(billStage(_o(paymentStatus: PaymentStatus.unpaid, cleared: false)), BillStage.awaitPayment);
    expect(billStage(_o()), BillStage.payDriver);
    expect(billStage(_o(driverPayoutId: 'dpo-1')), BillStage.done);
  });

  test('marks the first unfinished step as current', () {
    final steps = summarizeBill(_o(paymentStatus: PaymentStatus.unpaid, cleared: false)).steps;
    expect(steps.map((s) => s.state), [BillStepState.done, BillStepState.done, BillStepState.current, BillStepState.todo]);
  });

  testWidgets('bill card shows the split, the stage and its next action on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final order = _o(paymentMethod: PaymentMethod.cod, paymentStatus: PaymentStatus.unpaid, cleared: false);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BillTile(order: order, summary: summarizeBill(order), driverName: 'สมชาย ใจดีมากเป็นพิเศษ'),
        ),
      ),
    ));
    expect(find.text('รอรับเงินจากคนขับ'), findsOneWidget);
    expect(find.text('ไปเคลียร์ค่ารถ'), findsOneWidget);
    expect(find.text('คงเหลือเข้าร้าน'), findsOneWidget);
    expect(find.textContaining('≈'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('netMargin rounds and skips zero revenue', () {
    expect(netMargin(5200, 5700), 91);
    expect(netMargin(0, 0), isNull);
  });

  test('CSV export has a BOM, Thai headers and quoted cells', () {
    final order = _o();
    final csv = billSummaryCsv([(order: order, summary: summarizeBill(order), driverName: 'สมชาย, ใจดี')]);
    expect(csv.startsWith('\uFEFFเลขที่,วันที่,ลูกค้า,'), isTrue);
    final row = csv.split('\n')[1];
    expect(row, startsWith('TS6910-0001,2026-10-09,ลูกค้า,จัดส่ง,"สมชาย, ใจดี",5700,5000,700,'));
    expect(row, endsWith(BillStage.payDriver.label));
  });

  testWidgets('summary hero shows what the shop keeps and fits a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final totals = totalBills([summarizeBill(_o()), summarizeBill(_o(paymentStatus: PaymentStatus.unpaid, cleared: false))]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: SummaryHero(totals: totals, periodLabel: 'เดือนนี้')),
      ),
    ));
    expect(find.text('คงเหลือเข้าร้าน · เดือนนี้'), findsOneWidget);
    expect(find.textContaining('จาก 2 บิล'), findsOneWidget);
    expect(find.text('ค้างรับ'), findsOneWidget);
    expect(find.text('หักค่ารถคนขับ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
