import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/theme/daily_palette.dart';
import 'package:mobile_flutter/utils/fuel_stock.dart';
import 'package:mobile_flutter/widgets/fuel_macro_form_widgets.dart';

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
        padding: const EdgeInsets.all(12),
        child: child,
      ),
    ),
  );
}

void main() {
  group('FuelMacroTankHeader', () {
    testWidgets('shows active main tank, live balance preview, and switch button', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var switched = false;
      await tester.pumpWidget(
        _wrap(
          FuelMacroTankHeader(
            activeTank: kFuelTankMain,
            mainDieselLiters: 2000,
            reserveDieselLiters: 350,
            pendingDelta: -150,
            reserveShortfallLiters: 0,
            onSwitchTank: () => switched = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('ถังหลัก'), findsWidgets);
      expect(find.textContaining('2000'), findsOneWidget);
      expect(find.textContaining('1850'), findsOneWidget);
      expect(find.textContaining('-150'), findsOneWidget);
      expect(find.textContaining('350'), findsOneWidget);

      await tester.tap(find.text('เปลี่ยนถัง'));
      await tester.pump();
      expect(switched, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows negative warning when reserve tank goes below zero', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          FuelMacroTankHeader(
            activeTank: kFuelTankReserve,
            mainDieselLiters: 1500,
            reserveDieselLiters: 80,
            pendingDelta: -120,
            reserveShortfallLiters: 0,
            onSwitchTank: () {},
          ),
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('ถังสำรอง'), findsWidgets);
      expect(find.textContaining('ติดลบ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('FuelMacroVehicleCard', () {
    testWidgets('renders inputs, cross-tank badge, and fires tap & delete callbacks', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var litersTapped = false;
      var timeTapped = false;
      var deleteTapped = false;

      await tester.pumpWidget(
        _wrap(
          FuelMacroVehicleCard(
            displayIndex: 1,
            vehicleName: 'รถแม็คโคร CAT 320',
            driverLabel: 'สมชาย',
            activeTank: kFuelTankMain,
            litersText: '120',
            timeText: '09:30',
            isSaved: true,
            workedToday: true,
            missingFuelAfterWork: false,
            otherTankSummary: 'เติมจากถังสำรองแล้ว 80 ล. · 07:15',
            onTapLiters: () => litersTapped = true,
            onTapTime: () => timeTapped = true,
            onClearOrDelete: () async => deleteTapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('รถแม็คโคร CAT 320'), findsOneWidget);
      expect(find.textContaining('สมชาย'), findsOneWidget);
      expect(find.text('บันทึกแล้ว'), findsOneWidget);
      expect(find.text('เติมจากถังสำรองแล้ว 80 ล. · 07:15'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('09:30'), findsOneWidget);

      await tester.tap(find.text('120'));
      await tester.pump();
      expect(litersTapped, isTrue);

      await tester.tap(find.text('09:30'));
      await tester.pump();
      expect(timeTapped, isTrue);

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pump();
      expect(deleteTapped, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows missing-fuel state and clean empty placeholders', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          FuelMacroVehicleCard(
            displayIndex: 2,
            vehicleName: 'รถแม็คโคร KOBELCO',
            driverLabel: '',
            activeTank: kFuelTankReserve,
            litersText: '',
            timeText: '',
            isSaved: false,
            workedToday: true,
            missingFuelAfterWork: true,
            otherTankSummary: '',
            onTapLiters: () {},
            onTapTime: () {},
            onClearOrDelete: () async {},
          ),
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ยังไม่เติม'), findsOneWidget);
      expect(find.text('แตะกรอกลิตร'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
