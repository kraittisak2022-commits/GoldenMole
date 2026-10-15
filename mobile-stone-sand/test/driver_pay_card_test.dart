import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/logic/wizard_state.dart';
import 'package:mobile_stone_sand/models/models.dart';
import 'package:mobile_stone_sand/screens/new_order/step_delivery.dart';

const _delivery = DeliverySettings(nearKm: 5, customerPerKm: 50, driverPerKm5: 50, driverPerKm3: 30);
const _zone = Zone(id: 'z1', name: 'วังเหนือ', feePerCubic: 40, driverFee: 350, driverFee3: 250, sortOrder: 1);

Future<void> _pump(WidgetTester tester, Widget card) async {
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: card),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the driver pay per trip, the total and how it adds up', (tester) async {
    await _pump(
      tester,
      const DriverPayCard(
        zone: _zone,
        truckSize: 5,
        trips: 2,
        roadDistanceKm: 7.4,
        delivery: _delivery,
        otherSizeFits: true,
      ),
    );
    expect(find.text('ค่ารถคนขับเที่ยวนี้ · บอกคนขับตอนโทร'), findsOneWidget);
    expect(find.textContaining('500'), findsOneWidget);
    expect(find.text('รวม 2 เที่ยว 1,000 บาท'), findsOneWidget);
    expect(find.text('ค่ารถ ต.วังเหนือ (รถ 5 คิว)'), findsOneWidget);
    expect(find.text('ตามระยะ เกิน 5 กม. คิด 3 กม. × 50'), findsOneWidget);
    expect(find.text('+150'), findsOneWidget);
    expect(find.text('ถ้าใช้รถ 3 คิว: 340 บาท/เที่ยว'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('asks for the tambon first, and warns when its rate is not set', (tester) async {
    await _pump(
      tester,
      const DriverPayCard(
        zone: null,
        truckSize: 5,
        trips: 1,
        roadDistanceKm: null,
        delivery: _delivery,
        otherSizeFits: true,
      ),
    );
    expect(find.text('เลือกตำบลก่อน ระบบจะคำนวณค่ารถคนขับให้'), findsOneWidget);

    await _pump(
      tester,
      const DriverPayCard(
        zone: Zone(id: 'z2', name: 'ใหม่', feePerCubic: 40, sortOrder: 2),
        truckSize: 3,
        trips: 1,
        roadDistanceKm: 2,
        delivery: _delivery,
        otherSizeFits: false,
      ),
    );
    expect(find.textContaining('ยังไม่ได้ตั้งค่ารถคนขับ ต.ใหม่ สำหรับรถ 3 คิว'), findsOneWidget);
  });

  testWidgets('the admin can raise or lower the pay per trip and go back to the tambon rate', (tester) async {
    double? edited;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => DriverPayCard(
          zone: _zone,
          truckSize: 5,
          trips: 2,
          roadDistanceKm: 7.4,
          delivery: _delivery,
          otherSizeFits: true,
          edited: edited,
          onEdit: (v) => setState(() => edited = v),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('driver-fee-edit')));
    await tester.pump();
    expect(edited, 500);

    await tester.enterText(find.byKey(const ValueKey('driver-fee-field')), '450');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(edited, 450);
    expect(find.text('ปรับเอง'), findsOneWidget);
    expect(find.text('ปรับลด (ระบบคำนวณ 500)'), findsOneWidget);
    expect(find.text('−50'), findsOneWidget);
    expect(find.text('รวม 2 เที่ยว 900 บาท'), findsOneWidget);
    expect(find.textContaining('ถ้าใช้รถ 3 คิว'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('driver-fee-reset')));
    await tester.pump();
    expect(edited, isNull);
    expect(find.text('ปรับเอง'), findsNothing);
    expect(find.text('รวม 2 เที่ยว 1,000 บาท'), findsOneWidget);
  });

  testWidgets('the admin can set the pay to 0 baht', (tester) async {
    double? edited;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => DriverPayCard(
          zone: _zone,
          truckSize: 5,
          trips: 2,
          roadDistanceKm: 7.4,
          delivery: _delivery,
          otherSizeFits: true,
          edited: edited,
          onEdit: (v) => setState(() => edited = v),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('driver-fee-edit')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('driver-fee-field')), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(edited, 0);
    expect(find.text('ปรับเอง'), findsOneWidget);
    expect(find.text('รวม 2 เที่ยว 0 บาท'), findsOneWidget);
    expect(find.textContaining('ยังไม่ได้ตั้งค่ารถคนขับ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pay can be typed in when the tambon has no rate', (tester) async {
    double? edited;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => DriverPayCard(
          zone: const Zone(id: 'z2', name: 'ใหม่', feePerCubic: 40, sortOrder: 2),
          truckSize: 5,
          trips: 1,
          roadDistanceKm: 2,
          delivery: _delivery,
          otherSizeFits: false,
          edited: edited,
          onEdit: (v) => setState(() => edited = v),
        ),
      ),
    );
    await tester.tap(find.text('ใส่ค่ารถเอง'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('driver-fee-field')), '300');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(edited, 300);
    expect(find.text('ต.ใหม่ ยังไม่ได้ตั้งค่ารถ ใช้ค่ารถที่ใส่เอง'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('typed pay sticks to the tambon and truck size it was typed for', () {
    final s = initialWizardState.copyWith(zoneId: 'z1', truckSize: 5);
    final typed = s.copyWith(driverFeeEdit: (perTrip: 450.0, key: driverFeeKey(s)));
    expect(editedDriverFee(s), isNull);
    expect(editedDriverFee(typed), 450);
    expect(editedDriverFee(typed.copyWith(truckSize: 3)), isNull);
    expect(editedDriverFee(typed.copyWith(zoneId: 'z2')), isNull);
    expect(editedDriverFee(WizardState.fromJson(typed.toJson())), 450);
  });
}
