import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/widgets/count_record_counters.dart';

Widget _wrap({
  required Widget child,
  double width = 328,
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: Size(width, 740),
      textScaler: TextScaler.linear(textScale),
    ),
    child: MaterialApp(
      theme: ThemeData(brightness: brightness, useMaterial3: true),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: width - 16, child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'CountStatsStrip renders trip mode without overflow on narrow phone (320px/360px) and keeps period/cubic summary visible',
    (tester) async {
      var cubicTapped = false;
      var goalTapped = false;
      var shareTapped = false;

      // Typical phone card inner width (~312-328px on 360px screen with outer card padding)
      await tester.pumpWidget(
        _wrap(
          width: 320,
          child: CountStatsStrip(
            isTrip: true,
            totals: const (total: 83, morning: 83, afternoon: 0),
            goal: 20,
            cubicPerTrip: 3,
            onCubicTap: () => cubicTapped = true,
            onGoalTap: () => goalTapped = true,
            onShareTap: () => shareTapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('รวม'), findsOneWidget);
      expect(find.text('83'), findsOneWidget);
      expect(find.text('เที่ยว'), findsOneWidget);
      expect(find.text('×3 คิว/เที่ยว'), findsOneWidget);
      expect(find.text('เช้า 83 · บ่าย 0 · รวม 249 คิว'), findsOneWidget);

      // Period summary must have real visible width (not squished to 0px!)
      final periodRect = tester.getRect(
        find.text('เช้า 83 · บ่าย 0 · รวม 249 คิว'),
      );
      expect(periodRect.width, greaterThan(40));

      await tester.tap(find.text('×3 คิว/เที่ยว'));
      await tester.pump();
      expect(cubicTapped, isTrue);

      await tester.tap(find.byTooltip('เป้า 20 เที่ยว/คัน'));
      await tester.pump();
      expect(goalTapped, isTrue);

      await tester.tap(find.byTooltip('แชร์สรุปประจำวัน'));
      await tester.pump();
      expect(shareTapped, isTrue);
    },
  );

  testWidgets(
    'CountStatsStrip handles large numbers and 1.3x text scale on 320px width without overflow',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          width: 320,
          textScale: 1.3,
          child: CountStatsStrip(
            isTrip: true,
            totals: const (total: 1283, morning: 640, afternoon: 643),
            goal: 25,
            cubicPerTrip: 3.5,
            onCubicTap: () {},
            onGoalTap: () {},
            onShareTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('1283'), findsOneWidget);
      expect(find.text('×3.5 คิว/เที่ยว'), findsOneWidget);
    },
  );

  testWidgets(
    'CountStatsStrip renders single-row layout cleanly on tablet width (768px dark) and sand mode',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          width: 768,
          brightness: Brightness.dark,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CountStatsStrip(
                isTrip: true,
                totals: const (total: 83, morning: 50, afternoon: 33),
                goal: 20,
                cubicPerTrip: 3,
                onCubicTap: () {},
                onGoalTap: () {},
                onShareTap: () {},
              ),
              const SizedBox(height: 12),
              CountStatsStrip(
                isTrip: false,
                totals: const (total: 14, morning: 8, afternoon: 6),
                goal: 0,
                onShareTap: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('เช้า 50 · บ่าย 33 · รวม 249 คิว'), findsOneWidget);
      expect(find.text('เช้า 8 · บ่าย 6'), findsOneWidget);
    },
  );
}
