import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/auth/auth_scope.dart';
import 'package:mobile_stone_sand/data/catalog_scope.dart';
import 'package:mobile_stone_sand/models/models.dart';
import 'package:mobile_stone_sand/screens/customers_screen.dart';
import 'package:mobile_stone_sand/screens/driver_pay_screen.dart';
import 'package:mobile_stone_sand/screens/drivers_screen.dart';
import 'package:mobile_stone_sand/screens/settings_screen.dart';

const _snap = CustomerSnapshot(name: 'ร้านทดสอบ');

const _wageOrder = Order(
  id: 'o1',
  orderNo: 'DO6801-0001',
  orderDate: '2025-01-05',
  customerId: 'c1',
  customer: _snap,
  trips: 2,
  driverId: 'd1',
  deliveryTotal: 1000,
  driverWage: 600,
  total: 3000,
  paymentStatus: PaymentStatus.paid,
);

const _codOrder = Order(
  id: 'o2',
  orderNo: 'DO6801-0002',
  orderDate: '2025-01-06',
  customerId: 'c2',
  customer: CustomerSnapshot(name: 'ลูกค้าปลายทาง'),
  trips: 1,
  driverId: 'd1',
  deliveryTotal: 500,
  total: 3000,
  paymentMethod: PaymentMethod.cod,
);

Widget _host(Widget child, {CatalogController? catalog}) => AuthScope(
      controller: AuthController(),
      child: CatalogScope(
        controller: catalog ?? (CatalogController()..loading = false),
        child: MaterialApp(home: child),
      ),
    );

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  test('customerBalances adds both sources per customer and skips cancelled orders', () {
    final balances = customerBalances([
      _codOrder,
      _codOrder.copyWith(id: 'o3', source: OrderSource.pit),
      _wageOrder.copyWith(cancelled: true),
    ]);
    expect(balances['c2'], 6000);
    expect(balances.containsKey('c1'), isFalse);
  });

  testWidgets('payout nets COD cash against the wage and needs confirmation', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_host(const PayoutScreen(driverId: 'd1', driverName: 'สมชาย', orders: [_wageOrder, _codOrder])));

    expect(find.text('คนขับต้องส่งเงินให้ร้าน'), findsOneWidget);
    expect(find.text('1,900.00'), findsOneWidget);
    expect(find.text('-3,000.00'), findsOneWidget);
    expect(find.text('คนขับส่งเงินส่วนต่างด้วย'), findsOneWidget);

    FilledButton submit() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'ยืนยันเคลียร์ค่ารถ'));
    expect(submit().onPressed, isNull);
    await tester.tap(find.text('หักค่ารถให้คนขับแล้ว · รับเงิน 1,900.00 บาท'));
    await tester.tap(find.text('คนขับส่งเงินสด'));
    await tester.pump();
    expect(submit().onPressed, isNotNull);

    await tester.tap(find.text('ได้รับเงินสด 3,000.00 บาท จากคนขับแล้ว'));
    await tester.pump();
    expect(find.text('คนขับส่งเงินส่วนต่างด้วย'), findsNothing);
    expect(find.text('-3,000.00'), findsNothing);
    expect(find.text('ค่ารถ 1,100.00 ยังไม่จ่าย รอเคลียร์ค่ารถทีเดียวในรอบเดือน'), findsOneWidget);
    final later = find.widgetWithText(FilledButton, 'ยืนยันรับเงิน 3,000.00 (ค่ารถรอเคลียร์รอบเดือน)');
    expect(tester.widget<FilledButton>(later).onPressed, isNotNull);

    await tester.tap(find.text('DO6801-0002'));
    await tester.pump();
    expect(find.text('คนขับต้องส่งเงินให้ร้าน'), findsNothing);
    expect(find.text('600.00'), findsOneWidget);
    expect(find.text('จ่ายค่ารถด้วย'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'ยืนยันจ่ายค่ารถ'), findsOneWidget);
  });

  testWidgets('driver form requires a name', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_host(const DriverFormScreen()));
    expect(find.text('เพิ่มคนขับ'), findsOneWidget);
    await tester.tap(find.text('บันทึก'));
    await tester.pump();
    expect(find.text('กรุณาใส่ชื่อคนขับ'), findsOneWidget);
  });

  testWidgets('customer form checks the phone length', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_host(const CustomerFormScreen()));
    await tester.enterText(find.byType(TextField).first, 'ร้านใหม่');
    await tester.enterText(find.byType(TextField).at(2), '0812');
    await tester.tap(find.text('บันทึก'));
    await tester.pump();
    expect(find.text('เบอร์โทรควรมี 9-10 หลัก'), findsOneWidget);
  });

  testWidgets('settings shows a fee sample and validates PromptPay', (tester) async {
    _tallView(tester);
    final catalog = CatalogController()
      ..loading = false
      ..products = const [
        Product(
          id: 'p1',
          name: 'หินคลุก',
          category: ProductCategory.stone,
          unit: 'คิว',
          pricePerUnit: 400,
          sortOrder: 10,
          active: true,
        ),
      ]
      ..zones = const [Zone(id: 'z1', name: 'วังแก้ว', feeMin: 500, feeMax: 1000, sortOrder: 10)];
    await tester.pumpWidget(_host(const Scaffold(body: SettingsScreen()), catalog: catalog));

    expect(find.text('ราคาสินค้า (ต่อคิว)'), findsOneWidget);
    expect(find.text('ตัวอย่าง ต.วังแก้ว: 1 กม. = 500 · 5 กม. = 650 · 8 กม. = 900 · 12 กม. = 1,000'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('หมายเลขพร้อมเพย์'), 200, scrollable: find.byType(Scrollable).first);
    final pp = find.descendant(of: find.byType(PaymentSection), matching: find.byType(TextField)).first;
    await tester.enterText(pp, '123');
    await tester.pump();
    expect(find.text('รูปแบบไม่ถูกต้อง'), findsOneWidget);
    await tester.enterText(pp, '0812345678');
    await tester.pump();
    expect(find.text('รูปแบบไม่ถูกต้อง'), findsNothing);
  });
}
