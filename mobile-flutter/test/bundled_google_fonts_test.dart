import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('bundled Kanit loads offline without network fetch', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Text(
            'ทดสอบฟอนต์ Kanit',
            style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ทดสอบฟอนต์ Kanit'), findsOneWidget);
  });

  testWidgets('bundled Kanit weights 400/600/700/800 resolve', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Text('r', style: GoogleFonts.kanit()),
              Text('s', style: GoogleFonts.kanit(fontWeight: FontWeight.w600)),
              Text('b', style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
              Text(
                'x',
                style: GoogleFonts.kanit(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  });
}
