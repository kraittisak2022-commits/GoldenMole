import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/theme/daily_palette.dart';
import 'package:mobile_flutter/utils/macro_vehicle_summary.dart';
import 'package:mobile_flutter/widgets/macro_vehicle_widgets.dart';

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
  testWidgets('MacroFleetHeader shows KPIs, unsaved dot, and filter pills', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    MacroFleetFilter? nextFilter;
    await tester.pumpWidget(
      _wrap(
        MacroFleetHeader(
          dateLabel: '19/11/2569',
          overview: const MacroFleetOverview(
            totalCount: 5,
            activeCount: 3,
            savedCount: 2,
            idleCount: 2,
          ),
          filter: MacroFleetFilter.all,
          hasUnsavedChanges: true,
          onFilterChanged: (f) => nextFilter = f,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('19/11/2569'), findsOneWidget);
    expect(find.text('ยังไม่บันทึก'), findsOneWidget);
    expect(find.text('3/5'), findsOneWidget);
    expect(find.text('2'), findsWidgets);

    await tester.tap(find.text('ทำงาน (3)'));
    await tester.pump();
    expect(nextFilter, MacroFleetFilter.working);

    await tester.tap(find.text('ว่าง (2)'));
    await tester.pump();
    expect(nextFilter, MacroFleetFilter.idle);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MacroVehicleCard supports compact driver drawer, shift toggle, work sequence, and actions', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var driverExpanded = false;
    String? pickedDriver;
    String? pickedShift;
    String? toggledTag;
    var singleSaved = false;
    var deleted = false;

    const drivers = [
      MacroDriverOption(id: 'd1', displayName: 'สมชาย', isDefault: true),
      MacroDriverOption(id: 'd2', displayName: 'เก่ง', isDefault: false),
    ];

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => MacroVehicleCard(
            displayIndex: 1,
            vehicleName: 'รถแม็คโคร CAT 320',
            status: MacroVehicleRowStatus.saved,
            isSaved: true,
            hasData: true,
            selectedDriverId: 'd1',
            drivers: drivers,
            driverPickerExpanded: driverExpanded,
            workType: 'FullDay',
            quickPhrases: const ['เปิดหน้าดิน', 'ทอยดิน', 'ขุดแร่'],
            selectedTags: const ['เปิดหน้าดิน', 'ขุดแร่'],
            saving: false,
            onToggleDriverPicker: () =>
                setState(() => driverExpanded = !driverExpanded),
            onSelectDriver: (id) => pickedDriver = id,
            onSelectWorkType: (wt) => pickedShift = wt,
            onToggleWorkTag: (tag) => toggledTag = tag,
            onRemoveCustomTag: (_) {},
            onAddCustomTag: () {},
            onSaveSingle: () => singleSaved = true,
            onDeleteOrClear: () => deleted = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('รถแม็คโคร CAT 320'), findsOneWidget);
    expect(find.text('บันทึกแล้ว'), findsOneWidget);
    expect(find.text('สมชาย'), findsOneWidget);
    // Compact mode: non-selected driver 'เก่ง' hidden until expanded
    expect(find.text('เก่ง'), findsNothing);
    // Work sequence strip visible when >1 tags selected
    expect(find.textContaining('ลำดับงาน'), findsOneWidget);

    // Expand driver drawer and select 'เก่ง'
    await tester.tap(find.text('เปลี่ยน'));
    await tester.pumpAndSettle();
    expect(find.text('เก่ง'), findsOneWidget);

    await tester.tap(find.text('เก่ง'));
    await tester.pump();
    expect(pickedDriver, 'd2');

    // Toggle shift to HalfDay
    await tester.tap(find.text('ครึ่งวัน'));
    await tester.pump();
    expect(pickedShift, 'HalfDay');

    // Toggle work phrase
    await tester.tap(find.text('ทอยดิน'));
    await tester.pump();
    expect(toggledTag, 'ทอยดิน');

    // Tap single-row update
    await tester.tap(find.text('อัปเดตคันนี้'));
    await tester.pump();
    expect(singleSaved, isTrue);

    // Tap delete button
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pump();
    expect(deleted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MacroVehicleCard auto-shows drivers when missing driver and renders cleanly in dark tablet', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        MacroVehicleCard(
          displayIndex: 2,
          vehicleName: 'รถแม็คโคร PC200',
          status: MacroVehicleRowStatus.missingDriver,
          isSaved: false,
          hasData: true,
          selectedDriverId: '',
          drivers: const [
            MacroDriverOption(id: 'd1', displayName: 'วิชัย', isDefault: false),
          ],
          driverPickerExpanded: false,
          workType: 'HalfDay',
          quickPhrases: const ['เปิดหน้าดิน', 'ร่อนทราย'],
          selectedTags: const ['ร่อนทราย'],
          saving: false,
          onToggleDriverPicker: () {},
          onSelectDriver: (_) {},
          onSelectWorkType: (_) {},
          onToggleWorkTag: (_) {},
          onRemoveCustomTag: (_) {},
          onAddCustomTag: () {},
          onSaveSingle: () {},
          onDeleteOrClear: () {},
        ),
        brightness: Brightness.dark,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ขาดคนขับ'), findsOneWidget);
    // Auto-exposed driver chip when no driver is selected!
    expect(find.text('วิชัย'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('macroVehicleColorFor gives distinct colors across 8 excavators', () {
    final lightColors = <Color>{};
    final darkColors = <Color>{};
    for (var i = 1; i <= kMacroVehicleColorPalette.length; i++) {
      final theme = macroVehicleColorFor(displayIndex: i);
      lightColors.add(theme.primary(false));
      darkColors.add(theme.primary(true));
    }
    expect(lightColors.length, kMacroVehicleColorPalette.length);
    expect(darkColors.length, kMacroVehicleColorPalette.length);
  });

  testWidgets('distinct excavators render distinct stripe and badge colors even with same status', (
    WidgetTester tester,
  ) async {
    Widget buildCard(int index, String name) => MacroVehicleCard(
          displayIndex: index,
          vehicleName: name,
          status: MacroVehicleRowStatus.idle,
          isSaved: false,
          hasData: false,
          selectedDriverId: 'd1',
          drivers: const [
            MacroDriverOption(id: 'd1', displayName: 'สมชาย', isDefault: true),
          ],
          driverPickerExpanded: false,
          workType: 'FullDay',
          quickPhrases: const ['เปิดหน้าดิน'],
          selectedTags: const [],
          saving: false,
          onToggleDriverPicker: () {},
          onSelectDriver: (_) {},
          onSelectWorkType: (_) {},
          onToggleWorkTag: (_) {},
          onRemoveCustomTag: (_) {},
          onAddCustomTag: () {},
          onSaveSingle: () {},
          onDeleteOrClear: () {},
        );

    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            buildCard(1, 'รถแม็คโคร CAT 320'),
            buildCard(2, 'รถแม็คโคร PC200'),
            buildCard(3, 'รถแม็คโคร KOBELCO'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final stripe1 = tester
        .widget<Container>(find.byKey(const ValueKey('macro_vehicle_stripe_1')))
        .color;
    final stripe2 = tester
        .widget<Container>(find.byKey(const ValueKey('macro_vehicle_stripe_2')))
        .color;
    final stripe3 = tester
        .widget<Container>(find.byKey(const ValueKey('macro_vehicle_stripe_3')))
        .color;

    expect({stripe1, stripe2, stripe3}.length, 3);

    final badge1 = (tester
            .widget<Container>(
              find.byKey(const ValueKey('macro_vehicle_badge_1')),
            )
            .decoration! as BoxDecoration)
        .color;
    final badge2 = (tester
            .widget<Container>(
              find.byKey(const ValueKey('macro_vehicle_badge_2')),
            )
            .decoration! as BoxDecoration)
        .color;
    expect(badge1, isNot(equals(badge2)));
    expect(tester.takeException(), isNull);
  });
}
