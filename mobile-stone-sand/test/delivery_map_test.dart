import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/data/db.dart';
import 'package:mobile_stone_sand/logic/latlng.dart';
import 'package:mobile_stone_sand/widgets/delivery_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Prefs.setForTest(await SharedPreferences.getInstance());
  });

  testWidgets('map type toggle switches to satellite and remembers it', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DeliveryMap(value: LatLngValue(17.4, 99.6), height: 300, readOnly: true)),
    ));
    String urls() => tester.widgetList<TileLayer>(find.byType(TileLayer)).map((t) => t.urlTemplate).join(' ');
    expect(urls(), contains('openstreetmap'));

    await tester.tap(find.text('ดาวเทียม'));
    await tester.pump();
    expect(urls(), contains('World_Imagery'));
    expect(urls(), isNot(contains('openstreetmap')));
    expect(Prefs.instance.getString('ss_map_type'), 'satellite');

    await tester.tap(find.text('แผนที่'));
    await tester.pump();
    expect(urls(), contains('openstreetmap'));
  });
}
