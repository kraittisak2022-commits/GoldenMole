import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/auth/auth_scope.dart';
import 'package:mobile_stone_sand/data/db.dart';
import 'package:mobile_stone_sand/screens/login_screen.dart';
import 'package:mobile_stone_sand/screens/orders_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('OrderRange', () {
    test('parses web params and defaults to month', () {
      expect(OrderRange.parse('7d'), OrderRange.d7);
      expect(OrderRange.parse('3m'), OrderRange.m3);
      expect(OrderRange.parse('all'), OrderRange.all);
      expect(OrderRange.parse(null), OrderRange.month);
      expect(OrderRange.parse('bogus'), OrderRange.month);
    });

    test('from dates', () {
      final now = DateTime(2026, 3, 5);
      expect(OrderRange.today.from(now), '2026-03-05');
      expect(OrderRange.d7.from(now), '2026-02-27');
      expect(OrderRange.month.from(now), '2026-03-01');
      expect(OrderRange.m3.from(now), '2026-01-01');
      expect(OrderRange.all.from(now), isNull);
    });
  });

  testWidgets('login screen shows the form and validates empty fields', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Prefs.setForTest(await SharedPreferences.getInstance());
    final auth = AuthController();
    await tester.pumpWidget(AuthScope(
      controller: auth,
      child: const MaterialApp(home: LoginScreen()),
    ));
    expect(find.text('ระบบจัดการออเดอร์ หิน-ทราย'), findsOneWidget);
    expect(find.text('สำหรับเจ้าหน้าที่เท่านั้น'), findsOneWidget);
    expect(find.text('ชื่อผู้ใช้'), findsOneWidget);
    expect(find.text('รหัสผ่าน'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
    await tester.pumpAndSettle();
    expect(find.text('กรุณากรอกชื่อผู้ใช้และรหัสผ่าน'), findsOneWidget);
    expect(auth.isAuthenticated, isFalse);
  });
}
