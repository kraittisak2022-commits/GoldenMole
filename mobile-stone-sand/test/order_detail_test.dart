import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/data/catalog_scope.dart';
import 'package:mobile_stone_sand/logic/order_status.dart';
import 'package:mobile_stone_sand/models/models.dart';
import 'package:mobile_stone_sand/screens/order_edit_screen.dart';

const _order = Order(
  id: 'o1',
  orderNo: 'DO6910-0001',
  orderDate: '2026-10-09',
  customerId: 'c1',
  customer: CustomerSnapshot(name: 'ร้านทดสอบ'),
  fulfillment: Fulfillment.pickup,
  subtotal: 800,
  total: 800,
  items: [
    OrderItem(id: 'i1', productId: 'p1', name: 'หินคลุก', unit: 'คิว', unitPrice: 400, quantity: 2, amount: 800),
  ],
);

StatusLogEntry _e(String event) => StatusLogEntry(at: '2026-10-09T03:00:00Z', by: 'admin', event: event);

void main() {
  group('orderLogLabel', () {
    String label(String event) => orderLogLabel(_e(event), (id) => id == 'd1' ? 'สมชาย' : null);

    test('known events', () {
      expect(label('created'), 'สร้างออเดอร์');
      expect(label('paid:transfer'), 'รับเงินแล้ว (โอนเงิน)');
      expect(label('delivery:dispatched'), 'สถานะจัดส่ง: กำลังจัดส่ง');
      expect(label('wage:1500'), 'ค่าจ้างคนขับ 1,500 บาท');
      expect(label('cleared:BL6910-0002'), 'เคลียร์บิลกับใบวางบิล BL6910-0002');
      expect(label('wage_unpaid:DP6910-0001'), 'ลบรายการจ่ายค่ารถ DP6910-0001 (กลับเป็นค่ารถยังไม่จ่าย)');
    });

    test('unknown events fall back to a driver name, then the raw text', () {
      expect(label('assigned:d1'), 'สมชาย');
      expect(label('mystery'), 'mystery');
    });
  });

  testWidgets('edit screen recomputes totals and requires an item', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final catalog = CatalogController()..loading = false;
    await tester.pumpWidget(CatalogScope(
      controller: catalog,
      child: const MaterialApp(home: OrderEditScreen(order: _order, by: 'admin')),
    ));

    expect(find.text('ยอดสุทธิใหม่'), findsOneWidget);
    expect(find.text('800.00'), findsWidgets);

    await tester.enterText(find.widgetWithText(TextField, '2'), '3');
    await tester.pump();
    expect(find.text('1,200.00'), findsWidgets);
    expect(find.text('เดิม 800.00 บาท'), findsOneWidget);

    await tester.tap(find.byTooltip('ลบ หินคลุก'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึก'));
    await tester.pump();
    expect(find.text('ต้องมีสินค้าอย่างน้อย 1 รายการ'), findsOneWidget);
  });
}
