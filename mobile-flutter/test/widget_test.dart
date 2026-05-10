import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await dotenv.load(
      mergeWith: {
        'SUPABASE_URL': 'https://example.supabase.co',
        'SUPABASE_ANON_KEY': 'sb_publishable_placeholder_key_for_widget_tests',
      },
    );
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
  });

  testWidgets('app bootstraps to login', (WidgetTester tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MobileApp(navigatorKey: navKey));
    await tester.pump();
    // BootstrapSplash uses a repeating animation — never "settles".
    const tick = Duration(milliseconds: 50);
    for (var i = 0; i < 120; i++) {
      await tester.pump(tick);
      if (find.text('เข้าสู่ระบบ').evaluate().isNotEmpty) break;
    }
    expect(find.text('เข้าสู่ระบบ'), findsWidgets);
  });
}
