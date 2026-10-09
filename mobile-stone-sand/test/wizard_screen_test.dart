import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/auth/auth_scope.dart';
import 'package:mobile_stone_sand/auth/session.dart';
import 'package:mobile_stone_sand/data/catalog_scope.dart';
import 'package:mobile_stone_sand/data/db.dart';
import 'package:mobile_stone_sand/data/scope.dart';
import 'package:mobile_stone_sand/logic/wizard_state.dart';
import 'package:mobile_stone_sand/models/models.dart';
import 'package:mobile_stone_sand/screens/new_order/new_order_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final catalog = CatalogController()
    ..loading = false
    ..products = const [
      Product(
        id: 'p1',
        name: 'หินคลุก',
        category: ProductCategory.stone,
        unit: 'คิว',
        pricePerUnit: 400,
        sortOrder: 1,
        active: true,
      ),
    ];
  await tester.pumpWidget(AuthScope(
    controller: AuthController(),
    child: CatalogScope(
      controller: catalog,
      child: const MaterialApp(home: NewOrderScreen()),
    ),
  ));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Prefs.setForTest(await SharedPreferences.getInstance());
  });

  testWidgets('source then products, with validation and running total', (tester) async {
    await _pump(tester);
    expect(find.text('ประเภทออเดอร์'), findsOneWidget);

    await tester.tap(find.text('ออเดอร์ร้านวัสดุก่อสร้าง'));
    await tester.pumpAndSettle();
    expect(find.text('เลือกสินค้า'), findsOneWidget);

    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();
    expect(find.text('เลือกสินค้าอย่างน้อย 1 รายการ'), findsOneWidget);

    await tester.tap(find.text('หิน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 คิว'));
    await tester.pumpAndSettle();
    expect(find.text('1,200.00'), findsWidgets);

    final saved = jsonDecode(Prefs.instance.getString(draftKey)!) as Map<String, dynamic>;
    expect(saved['step'], 1);
    expect((saved['state'] as Map)['source'], 'shop');
  });

  testWidgets('custom per-trip amount, capped at 5', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('ออเดอร์ร้านวัสดุก่อสร้าง'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('หิน'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('อื่นๆ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'เช่น 2 หรือ 2.5'), '2.5');
    await tester.pumpAndSettle();
    expect(find.text('1,000.00'), findsWidgets);

    await tester.enterText(find.byType(TextField).last, '6');
    await tester.pumpAndSettle();
    expect(find.text('ใส่ได้ไม่เกิน 5 คิวต่อเที่ยว (รถใหญ่สุด 5 คิว)'), findsOneWidget);
  });

  testWidgets('an account locked to one source only picks the date', (tester) async {
    saveSession(const StoneSandSession(
      id: 'u1',
      username: 'pit',
      displayName: 'ท่าทราย',
      role: 'Admin',
      orderSource: OrderSource.pit,
      loginAt: '2999-01-01T00:00:00Z',
    ));
    addTearDown(() => setLockedSource(null));
    await _pump(tester);
    expect(find.textContaining('ออเดอร์ท่าทราย · เลือกวันที่'), findsOneWidget);
    expect(find.text('ออเดอร์ร้านวัสดุก่อสร้าง'), findsNothing);
  });

  testWidgets('resumes the saved draft', (tester) async {
    Prefs.instance.setString(
      draftKey,
      jsonEncode({
        'step': 1,
        'state': const WizardState(source: OrderSource.pit).toJson(),
      }),
    );
    await _pump(tester);
    expect(find.text('เลือกสินค้า'), findsOneWidget);
    expect(find.text('ออเดอร์ท่าทราย'), findsOneWidget);
  });
}
