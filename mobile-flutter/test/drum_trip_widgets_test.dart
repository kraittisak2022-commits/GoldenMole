import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/models/employee.dart';
import 'package:mobile_flutter/theme/daily_palette.dart';
import 'package:mobile_flutter/utils/drum_trip_summary.dart';
import 'package:mobile_flutter/widgets/drum_trip_widgets.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  final isDark = brightness == Brightness.dark;
  return MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      extensions: [isDark ? DailyColors.dark : DailyColors.light],
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
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('vehicleTripAccentForCar', () {
    test('assigns distinct colors to different cars in fleet', () {
      const cars = ['รถดรัม 1', 'รถดรัม 2', 'รถดรัม 3', 'รถดรัม 4'];
      final names = cars
          .map((c) => vehicleTripAccentForCar(c, cars).name)
          .toSet();
      expect(names.length, cars.length);
    });

    test('vehicleTripDisplayNumber extracts digit or index', () {
      const cars = ['รถดรัม 1', 'รถดรัมพี่เอ'];
      expect(vehicleTripDisplayNumber('รถดรัม 1', cars), '#1');
      expect(vehicleTripDisplayNumber('รถดรัมพี่เอ', cars), '#2');
    });
  });

  group('VehicleTripOverviewHeader', () {
    testWidgets('renders KPI metrics without overflow on narrow phone (360px)',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const overview = VehicleTripDayOverview(
        savedVehicles: 3,
        fleetTotal: 5,
        totalMorningTrips: 14,
        totalAfternoonTrips: 11,
        totalTrips: 25,
        totalCubic: 85,
        lumpSumVehicles: 1,
        countRecordSyncedVehicles: 1,
      );

      await tester.pumpWidget(
        _wrap(
          const VehicleTripOverviewHeader(
            overview: overview,
            dateLabel: '15 มิ.ย. 2569',
          ),
        ),
      );

      expect(find.text('สรุปรถดรัมประจำวัน'), findsOneWidget);
      expect(find.text('บันทึก 3/5 คัน'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('85'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('VehicleTripEditorCard', () {
    testWidgets('supports 1-tap vehicle, stepper, cubic preset, and live total',
        (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? selectedCar;
      double morningDelta = 0;
      String? cubicPreset;
      String? toggledPhrase;
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);

      const drivers = [
        Employee(id: 'd1', name: 'สมชาย ใจดี', nickname: 'พี่ชาย', type: 'Daily'),
        Employee(id: 'd2', name: 'สมศักดิ์', nickname: 'ลุงศักดิ์', type: 'Daily'),
      ];

      await tester.pumpWidget(
        _wrap(
          VehicleTripEditorCard(
            index: 0,
            totalRows: 1,
            vehicleId: 'รถดรัม 1',
            driverId: 'd1',
            billingMode: 'PerTrip',
            morningText: '4',
            afternoonText: '2',
            cubicPerTripText: '3',
            lumpSumCubicText: '',
            workType: 'FullDay',
            hourlyHoursText: '',
            workDetailsController: ctrl,
            allCars: const ['รถดรัม 1', 'รถดรัม 2'],
            savedCarNames: const {'รถดรัม 2'},
            otherDraftCarNames: const {},
            drivers: drivers,
            defaultDriverId: 'd1',
            status: VehicleTripRowStatus.ready,
            isEditingSaved: false,
            isCountRecordSynced: false,
            workDetailSuggestions: const ['ขนทรายบ่อ 2'],
            onSelectVehicle: (v) => selectedCar = v,
            onSelectDriver: (_) {},
            onSelectBillingMode: (_) {},
            onStepMorning: (d) => morningDelta = d,
            onTapMorningPad: () {},
            onStepAfternoon: (_) {},
            onTapAfternoonPad: () {},
            onSelectCubicPreset: (p) => cubicPreset = p,
            onTapCubicPad: () {},
            onTapLumpSumPad: () {},
            onSelectWorkType: (_) {},
            onSelectHourlyPreset: (_) {},
            onTapHourlyPad: () {},
            onToggleQuickPhrase: (p) => toggledPhrase = p,
            onWorkDetailsChanged: (_) {},
          ),
        ),
      );

      expect(find.text('พร้อมบันทึก'), findsOneWidget);
      expect(find.text('6 เที่ยว × 3 คิว'), findsOneWidget);
      expect(find.text('= 18 คิว'), findsOneWidget);

      await tester.tap(find.text('รถดรัม 2'));
      expect(selectedCar, 'รถดรัม 2');

      await tester.tap(find.text('5 คิว'));
      expect(cubicPreset, '5');

      await tester.tap(find.text('+ ขนทรายล้าง'));
      expect(toggledPhrase, 'ขนทรายล้าง');

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      expect(morningDelta, 1);

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders cleanly in dark mode', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(
        _wrap(
          VehicleTripEditorCard(
            index: 0,
            totalRows: 1,
            vehicleId: 'รถดรัม 1',
            driverId: '',
            billingMode: 'LumpSum',
            morningText: '3',
            afternoonText: '2',
            cubicPerTripText: '',
            lumpSumCubicText: '20',
            workType: 'Hourly',
            hourlyHoursText: '4',
            workDetailsController: ctrl,
            allCars: const ['รถดรัม 1'],
            savedCarNames: const {},
            otherDraftCarNames: const {},
            drivers: const [
              Employee(id: 'd1', name: 'สมชาย', nickname: 'ชาย', type: 'Daily'),
            ],
            defaultDriverId: 'd1',
            status: VehicleTripRowStatus.incomplete,
            isEditingSaved: false,
            isCountRecordSynced: true,
            workDetailSuggestions: const [],
            onSelectVehicle: (_) {},
            onSelectDriver: (_) {},
            onSelectBillingMode: (_) {},
            onStepMorning: (_) {},
            onTapMorningPad: () {},
            onStepAfternoon: (_) {},
            onTapAfternoonPad: () {},
            onSelectCubicPreset: (_) {},
            onTapCubicPad: () {},
            onTapLumpSumPad: () {},
            onSelectWorkType: (_) {},
            onSelectHourlyPreset: (_) {},
            onTapHourlyPad: () {},
            onToggleQuickPhrase: (_) {},
            onWorkDetailsChanged: (_) {},
          ),
          brightness: Brightness.dark,
        ),
      );

      expect(find.text('เชื่อมข้อมูลจากแผงนับเที่ยวสด'), findsOneWidget);
      expect(find.text('= 20 คิว'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'supports card collapse/expand and driver show/hide even when no driver selected',
      (tester) async {
        tester.view.physicalSize = const Size(390, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final ctrl = TextEditingController();
        addTearDown(ctrl.dispose);

        await tester.pumpWidget(
          _wrap(
            VehicleTripEditorCard(
              index: 0,
              totalRows: 1,
              vehicleId: '',
              driverId: '',
              billingMode: 'PerTrip',
              morningText: '',
              afternoonText: '',
              cubicPerTripText: '3',
              lumpSumCubicText: '',
              workType: 'FullDay',
              hourlyHoursText: '',
              workDetailsController: ctrl,
              allCars: const ['รถดรัม 1', 'รถดรัม 2'],
              savedCarNames: const {},
              otherDraftCarNames: const {},
              drivers: const [
                Employee(
                  id: 'd1',
                  name: 'สมชาย',
                  nickname: 'พี่ชาย',
                  type: 'Daily',
                  positions: ['คนขับรถ'],
                ),
                Employee(
                  id: 'd2',
                  name: 'สมศักดิ์',
                  nickname: 'ลุงศักดิ์',
                  type: 'Daily',
                  positions: ['คนขับรถ'],
                ),
              ],
              defaultDriverId: null,
              status: VehicleTripRowStatus.empty,
              isEditingSaved: false,
              isCountRecordSynced: false,
              workDetailSuggestions: const [],
              onSelectVehicle: (_) {},
              onSelectDriver: (_) {},
              onSelectBillingMode: (_) {},
              onStepMorning: (_) {},
              onTapMorningPad: () {},
              onStepAfternoon: (_) {},
              onTapAfternoonPad: () {},
              onSelectCubicPreset: (_) {},
              onTapCubicPad: () {},
              onTapLumpSumPad: () {},
              onSelectWorkType: (_) {},
              onSelectHourlyPreset: (_) {},
              onTapHourlyPad: () {},
              onToggleQuickPhrase: (_) {},
              onWorkDetailsChanged: (_) {},
            ),
          ),
        );

        // 1) Driver list starts open when no driver selected; tapping toggle MUST hide it
        expect(find.text('พี่ชาย'), findsOneWidget);
        expect(find.text('ลุงศักดิ์'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('drum_driver_toggle_0')));
        await tester.pumpAndSettle();
        expect(find.text('พี่ชาย'), findsNothing);
        expect(find.text('แสดง'), findsOneWidget);

        // Tap again to show driver list back
        await tester.tap(find.byKey(const ValueKey('drum_driver_toggle_0')));
        await tester.pumpAndSettle();
        expect(find.text('พี่ชาย'), findsOneWidget);

        // 2) Card collapse/expand button hides body and expands back cleanly
        expect(find.text('เลือกรถดรัม'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('drum_card_toggle_0')));
        await tester.pumpAndSettle();
        expect(find.text('เลือกรถดรัม'), findsNothing);
        expect(find.text('ขยาย'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('drum_card_toggle_0')));
        await tester.pumpAndSettle();
        expect(find.text('เลือกรถดรัม'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('VehicleTripSavedCard', () {
    testWidgets('displays metrics and triggers edit and delete callbacks',
        (tester) async {
      var editTapped = false;
      var deleteTapped = false;

      const tx = AppTransaction(
        id: 'tx_saved_1',
        date: '2026-06-15',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'VehicleTrip',
        description: 'รถดรัม 1: 8 เที่ยว × 3 คิว',
        amount: 0,
        vehicleId: 'รถดรัม 1',
        driverId: 'd1',
        tripBillingMode: 'PerTrip',
        tripMorning: 5,
        tripAfternoon: 3,
        tripCount: 8,
        cubicPerTrip: 3,
        totalCubic: 24,
        workType: 'FullDay',
        workDetails: 'ขนทรายล้าง',
      );

      await tester.pumpWidget(
        _wrap(
          VehicleTripSavedCard(
            transaction: tx,
            driverName: 'พี่ชาย',
            allCars: const ['รถดรัม 1', 'รถดรัม 2'],
            isBeingEdited: false,
            onEdit: () => editTapped = true,
            onDelete: () => deleteTapped = true,
          ),
        ),
      );

      expect(find.text('รถดรัม 1'), findsOneWidget);
      expect(find.text('8 เที่ยว'), findsOneWidget);
      expect(find.text('24 คิว'), findsOneWidget);
      expect(find.text('ขนทรายล้าง'), findsOneWidget);

      await tester.tap(find.text('แก้ไข'));
      expect(editTapped, isTrue);

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      expect(deleteTapped, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
