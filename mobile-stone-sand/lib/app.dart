import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'theme/app_theme.dart';

class StoneSandApp extends StatelessWidget {
  const StoneSandApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ระบบจัดการออเดอร์ หิน-ทราย',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('th', 'TH'),
      supportedLocales: const [Locale('th', 'TH'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(body: Center(child: Text('หิน-ทราย'))),
    );
  }
}
