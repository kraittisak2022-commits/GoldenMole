import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/theme/daily_palette.dart';
import 'package:mobile_flutter/utils/fuel_stock.dart';
import 'package:mobile_flutter/widgets/fuel_macro_tank_picker.dart';
import 'package:mobile_flutter/widgets/fuel_sub_mode_picker.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      extensions: [
        brightness == Brightness.dark ? DailyColors.dark : DailyColors.light,
      ],
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets('displays main and reserve tank options and invokes onSelect', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? picked;
    await tester.pumpWidget(
      _wrap(
        FuelMacroTankPicker(
          mainDieselLiters: 2450,
          reserveDieselLiters: 420,
          dateLabel: '19/11/2569',
          onSelect: (tank) => picked = tank,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ถังหลัก'), findsOneWidget);
    expect(find.text('ถังสำรอง'), findsOneWidget);
    expect(find.textContaining('2450'), findsOneWidget);
    expect(find.textContaining('420'), findsOneWidget);
    expect(find.textContaining('1000'), findsOneWidget);

    await tester.tap(find.text('ถังหลัก'));
    await tester.pump();
    expect(picked, kFuelTankMain);

    await tester.tap(find.text('ถังสำรอง'));
    await tester.pump();
    expect(picked, kFuelTankReserve);
  });

  testWidgets('shows per-tank summaries and missing fuel badge', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        FuelMacroTankPicker(
          mainDieselLiters: 1200,
          reserveDieselLiters: -50,
          dateLabel: '19/11/2569',
          mainSummary: const FuelMacroTankDaySummary(
            fueledCount: 1,
            liters: 80,
          ),
          reserveSummary: const FuelMacroTankDaySummary(
            fueledCount: 2,
            liters: 185,
          ),
          missingCount: 2,
          onSelect: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1 คัน'), findsOneWidget);
    expect(find.textContaining('80'), findsOneWidget);
    expect(find.textContaining('2 คัน'), findsWidgets);
    expect(find.textContaining('185'), findsOneWidget);
    expect(find.textContaining('ยังไม่เติม 2 คัน'), findsOneWidget);
    expect(find.textContaining('ติดลบ'), findsOneWidget);
  });

  testWidgets('renders cleanly in tablet landscape and dark mode without overflow', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        FuelMacroTankPicker(
          mainDieselLiters: 5000,
          reserveDieselLiters: 650,
          dateLabel: '19/11/2569',
          onSelect: (_) {},
        ),
        brightness: Brightness.dark,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ถังหลัก'), findsOneWidget);
    expect(find.text('ถังสำรอง'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FuelSubModePicker shows tank-selection hint for excavator fuel', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    FuelSubMode? pickedMode;
    await tester.pumpWidget(
      _wrap(
        FuelSubModePicker(
          mainDieselLiters: 2000,
          reserveDieselLiters: 500,
          dateLabel: '19/11/2569',
          onSelect: (mode) => pickedMode = mode,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('น้ำมันรถแม็คโคร'), findsOneWidget);
    expect(find.text('เลือกถังหลัก / ถังสำรอง'), findsOneWidget);

    await tester.tap(find.text('น้ำมันรถแม็คโคร'));
    await tester.pump();
    expect(pickedMode, FuelSubMode.macroUsage);
    expect(tester.takeException(), isNull);
  });
}
