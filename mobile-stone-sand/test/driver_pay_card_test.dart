import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/models/models.dart';
import 'package:mobile_stone_sand/screens/new_order/step_fulfillment.dart';

const _delivery = DeliverySettings(nearKm: 5, customerPerKm: 50, driverPerKm5: 50, driverPerKm3: 30);
const _zone = Zone(id: 'z1', name: 'วังเหนือ', feePerCubic: 40, driverFee: 350, driverFee3: 250, sortOrder: 1);

Future<void> _pump(WidgetTester tester, Widget card) async {
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: card))));
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
    expect(find.text('รวม 2 เที่ยว'), findsOneWidget);
    expect(find.text('1,000'), findsOneWidget);
    expect(find.text('ค่ารถ ต.วังเหนือ (รถ 5 คิว)'), findsOneWidget);
    expect(find.text('ตามระยะ เกิน 5 กม. คิด 3 กม. × 50'), findsOneWidget);
    expect(find.text('+150'), findsOneWidget);
    expect(find.text('ถ้าใช้รถ 3 คิว: 340 บาท/เที่ยว'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('asks for the tambon first, and warns when its rate is not set', (tester) async {
    await _pump(
      tester,
      const DriverPayCard(zone: null, truckSize: 5, trips: 1, roadDistanceKm: null, delivery: _delivery, otherSizeFits: true),
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
}
