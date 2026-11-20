import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/utils/fuel_stock.dart';
import 'package:mobile_flutter/widgets/fuel_withdraw_widgets.dart';

const _day = '2026-08-10';

AppTransaction _entry({
  required String id,
  required String sub,
  required double liters,
  required String workType,
  required String time,
  String? vehicleId,
  String? note,
}) =>
    AppTransaction(
      id: id,
      date: _day,
      type: 'Expense',
      category: 'Fuel',
      subCategory: sub,
      description: id,
      amount: 0,
      quantity: liters,
      unit: 'L',
      fuelType: 'Diesel',
      fuelMovement: 'stock_out',
      fuelTank: kFuelTankMain,
      workType: workType,
      vehicleId: vehicleId,
      note: note,
      workDetails: '$time (ผู้กรอก: สมชาย)',
    );

Widget _wrap({
  required Widget child,
  Size size = const Size(360, 740),
  Brightness brightness = Brightness.light,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      theme: ThemeData(brightness: brightness, useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'FuelWithdrawPurposeSelector renders all 5 purposes with multi-round summary and handles selection on 360px phone',
    (tester) async {
      final m1 = _entry(
        id: 'm1',
        sub: kFuelTransferSubCategory,
        liters: 600,
        workType: 'machine',
        time: '09:00',
        note: 'xfer:1',
      );
      final m2 = _entry(
        id: 'm2',
        sub: kFuelTransferSubCategory,
        liters: 600,
        workType: 'machine',
        time: '13:00',
        note: 'xfer:2',
      );
      final g1 = _entry(
        id: 'g1',
        sub: kFuelWithdrawSubCategory,
        liters: 25,
        workType: 'generator',
        time: '10:30',
      );

      FuelWithdrawPurpose? picked;
      final summaries = {
        FuelWithdrawPurpose.machine: FuelWithdrawDaySummary(
          entries: [m1, m2],
          totalLiters: 1200,
        ),
        FuelWithdrawPurpose.generator: FuelWithdrawDaySummary(
          entries: [g1],
          totalLiters: 25,
        ),
      };

      await tester.pumpWidget(
        _wrap(
          size: const Size(360, 740),
          child: FuelWithdrawPurposeSelector(
            selectedPurpose: FuelWithdrawPurpose.machine,
            summariesByPurpose: summaries,
            compact: true,
            onSelect: (p) => picked = p,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('เติมเครื่องจักร (ถังสำรอง)'), findsOneWidget);
      expect(find.text('2 รอบ · รวม 1200 ลิตร'), findsOneWidget);
      expect(find.text('เครื่องปั่นไฟเล็ก'), findsOneWidget);
      expect(find.text('25 ลิตร · 10:30'), findsOneWidget);
      expect(find.text('นายกเบิก'), findsOneWidget);
      expect(find.text(kFuelCarFillTaplien), findsOneWidget);
      expect(find.text(kFuelCarFillTenWheelerMayor), findsOneWidget);

      await tester.tap(find.text('เครื่องปั่นไฟเล็ก'));
      await tester.pump();
      expect(picked, FuelWithdrawPurpose.generator);
    },
  );

  testWidgets(
    'FuelWithdrawDayLogSection displays multiple rounds chronologically and wires edit, delete, and filter callbacks without overflow',
    (tester) async {
      final m1 = _entry(
        id: 'm1',
        sub: kFuelTransferSubCategory,
        liters: 600,
        workType: 'machine',
        time: '09:00',
        note: 'xfer:1',
      );
      final g1 = _entry(
        id: 'g1',
        sub: kFuelWithdrawSubCategory,
        liters: 25,
        workType: 'generator',
        time: '10:30',
      );
      final m2 = _entry(
        id: 'm2',
        sub: kFuelTransferSubCategory,
        liters: 600,
        workType: 'machine',
        time: '13:00',
        note: 'xfer:2',
      );

      AppTransaction? edited;
      AppTransaction? deleted;
      bool? toggledShowAll;

      await tester.pumpWidget(
        _wrap(
          size: const Size(360, 740),
          child: FuelWithdrawDayLogSection(
            entries: [m1, g1, m2],
            selectedPurpose: FuelWithdrawPurpose.machine,
            showAllPurposes: true,
            editingTxId: 'm1',
            onToggleShowAll: (v) => toggledShowAll = v,
            onEdit: (tx) => edited = tx,
            onDelete: (tx) => deleted = tx,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('รายการเบิกวันนี้'), findsOneWidget);
      expect(find.text('3 รายการ · รวม 1225 ลิตร'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('10:30'), findsOneWidget);
      expect(find.text('13:00'), findsOneWidget);
      expect(find.text('600 ลิตร'), findsNWidgets(2));
      expect(find.text('กำลังแก้ไข'), findsOneWidget);

      // Filter pills present when multiple purposes exist
      expect(find.text('ทั้งหมด (3)'), findsOneWidget);
      expect(find.text('เฉพาะที่เลือก (2)'), findsOneWidget);

      await tester.tap(find.text('เฉพาะที่เลือก (2)'));
      await tester.pump();
      expect(toggledShowAll, isFalse);

      // Tap edit button on m2 (m1 is currently editing, so m2 has the 2nd edit icon after g1)
      await tester.tap(find.byTooltip('แก้ไขรายการ 13:00'));
      await tester.pump();
      expect(edited?.id, 'm2');

      await tester.tap(find.byTooltip('ลบรายการ 13:00'));
      await tester.pump();
      expect(deleted?.id, 'm2');
    },
  );

  testWidgets(
    'FuelWithdrawEditingBanner and empty log render cleanly on dark tablet landscape',
    (tester) async {
      final m1 = _entry(
        id: 'm1',
        sub: kFuelTransferSubCategory,
        liters: 600,
        workType: 'machine',
        time: '09:00',
        note: 'xfer:1',
      );
      var cancelled = false;

      await tester.pumpWidget(
        _wrap(
          size: const Size(1024, 768),
          brightness: Brightness.dark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FuelWithdrawEditingBanner(
                entry: m1,
                onCancel: () => cancelled = true,
              ),
              const SizedBox(height: 12),
              FuelWithdrawDayLogSection(
                entries: const [],
                selectedPurpose: FuelWithdrawPurpose.machine,
                showAllPurposes: true,
                onToggleShowAll: (_) {},
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('กำลังแก้ไขรายการเดิม'), findsOneWidget);
      expect(find.textContaining('09:00'), findsOneWidget);
      expect(find.text('ยังไม่มีรายการเบิกน้ำมันของวันนี้'), findsOneWidget);

      await tester.tap(find.text('ยกเลิก'));
      await tester.pump();
      expect(cancelled, isTrue);
    },
  );
}
