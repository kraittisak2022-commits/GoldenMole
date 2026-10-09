import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/bill/bill_data.dart';
import 'package:mobile_stone_sand/bill/bill_document.dart';
import 'package:mobile_stone_sand/bill/bill_export.dart';
import 'package:mobile_stone_sand/logic/format.dart';
import 'package:mobile_stone_sand/models/models.dart';

const _order = Order(
  id: 'o1',
  orderNo: 'DO6910-0001',
  orderDate: '2026-10-09',
  customerId: 'c1',
  customer: CustomerSnapshot(name: 'ร้านทดสอบ', phone: '0812345678', address: 'วังเหนือ'),
  fulfillment: Fulfillment.delivery,
  deliveryAddress: 'บ้านเลขที่ 1',
  truckSize: 5,
  trips: 1,
  feePerTrip: 500,
  subtotal: 2000,
  deliveryTotal: 500,
  total: 2500,
  verifyToken: 'tok123',
  items: [
    OrderItem(id: 'i1', productId: 'p1', name: 'หินคลุก', unit: 'คิว', unitPrice: 400, quantity: 5, amount: 2000),
  ],
);

const _payment = PaymentSettings(
  promptPayId: '0812345678',
  bankText: 'โอนแล้วส่งสลิปทางไลน์',
  bankName: 'กสิกรไทย',
  bankAccountNo: '123-4-56789-0',
  bankAccountName: 'หจก. ทดสอบ',
  qrPayload: '00020101021130730016A0000006770101120115010753700088205021916151060181105030020307PIRASIT'
      '53037645802TH620807040000630443A3',
);

Future<void> _pump(WidgetTester tester, Widget sheet, GlobalKey key) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: FittedBox(child: RepaintBoundary(key: key, child: sheet)),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('order bill: original + copy spread, PromptPay and verify QR', (tester) async {
    final key = GlobalKey();
    final bill = billFromOrder(_order, DocKind.delivery);
    Widget doc(BillCopy c) => BillDocument(
          bill: bill,
          copy: c,
          company: CompanySettings.defaults,
          payment: _payment,
          printedAt: DateTime(2026, 10, 9, 10, 30),
        );
    await _pump(tester, BillSpread(left: doc(BillCopy.original), right: doc(BillCopy.copy)), key);

    expect(tester.takeException(), isNull);
    expect(find.text('ใบส่งของ'), findsNWidgets(2));
    expect(find.text('ต้นฉบับ / ORIGINAL'), findsOneWidget);
    expect(find.text('สำเนา / COPY'), findsOneWidget);
    expect(find.text('(สองพันห้าร้อยบาทถ้วน)'), findsNWidgets(2));
    expect(find.text('สแกนจ่ายด้วยพร้อมเพย์'), findsNWidgets(2));
    expect(find.text('สแกนเพื่อตรวจสอบความถูกต้องของเอกสาร'), findsNWidgets(2));
    expect(find.text('ยังไม่ชำระ'), findsNothing);
    expect(find.text('ช่องทางรับเงิน'), findsNWidgets(2));
    expect(find.text('123-4-56789-0'), findsNWidgets(2));
    expect(find.text('หจก. ทดสอบ'), findsNWidgets(2));
    expect(find.text('สแกน QR เพื่อชำระ'), findsNWidgets(2));
    expect(find.text('อ้างอิง DO69100001'), findsNWidgets(2));
    // Under the shop QR and under the PromptPay QR, on both copies
    expect(find.text('ยอด 2,500.00 บาท'), findsNWidgets(4));
    // Both signers on both copies, dated with the order date until it is delivered
    expect(find.text('วันที่ 09/10/2569', findRichText: true), findsNWidgets(4));

    await tester.runAsync(() async {
      final png = await captureBoundary(key, pixelRatio: 0.5);
      expect(png.sublist(1, 4), utf8.encode('PNG'));
      final pdf = await billPdf(png, landscape: true, title: bill.docNo);
      expect(utf8.decode(pdf.sublist(0, 5)), '%PDF-');
    });
  });

  testWidgets('paid receipt hides PromptPay and shows the paid stamp; cancelled shows VOID', (tester) async {
    final key = GlobalKey();
    final paid = _order.copyWith(paymentStatus: PaymentStatus.paid, cancelled: true);
    await _pump(
      tester,
      BillA4Page(
        child: BillDocument(
          bill: billFromOrder(paid, DocKind.receipt),
          copy: BillCopy.original,
          company: CompanySettings.defaults,
          payment: _payment,
          size: BillSize.a4,
        ),
      ),
      key,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('ใบเสร็จรับเงิน'), findsOneWidget);
    expect(find.text('สแกนจ่ายด้วยพร้อมเพย์'), findsNothing);
    expect(find.text('ช่องทางรับเงิน'), findsNothing);
    expect(find.text('ชำระเงินแล้ว'), findsOneWidget);
    expect(find.text('ยกเลิก / VOID'), findsOneWidget);
  });

  testWidgets('statement with many orders still lays out', (tester) async {
    final key = GlobalKey();
    final orders = [
      for (var i = 0; i < 25; i++) _order.copyWith(id: 'o$i', orderNo: 'DO6910-${'$i'.padLeft(4, '0')}'),
    ];
    final s = Statement(
      id: 's1',
      statementNo: 'BL6910-0001',
      source: OrderSource.shop,
      customerId: 'c1',
      customer: const CustomerSnapshot(name: 'ร้านทดสอบ'),
      periodFrom: '2026-10-01',
      periodTo: '2026-10-31',
      total: 2500.0 * orders.length,
      status: 'open',
      verifyToken: 'st',
      orderIds: [for (final o in orders) o.id],
    );
    await _pump(
      tester,
      BillA4Page(
        child: BillDocument(
          bill: billFromStatement(s, orders),
          copy: BillCopy.original,
          company: CompanySettings.defaults,
          payment: _payment,
          size: BillSize.a4,
        ),
      ),
      key,
    );
    expect(tester.takeException(), isNull);
    expect(find.text(DocKind.statement.th), findsOneWidget);
    expect(find.text('จำนวน 25 รายการ'), findsOneWidget);
  });
}
