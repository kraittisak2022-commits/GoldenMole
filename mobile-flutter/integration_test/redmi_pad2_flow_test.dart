import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_flutter/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Dashboard -> Quick Input -> Vehicle Trip -> drag labor',
    (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 6));

      final dashboardMarker = find.text('บันทึกรถและจำนวนเที่ยวรถ');
      if (dashboardMarker.evaluate().isEmpty) {
        fail(
          'Dashboard not visible. Ensure you are logged in on device, then rerun.',
        );
      }

      await tester.tap(dashboardMarker.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Ensure Vehicle Trip section is present (route landed correctly).
      expect(find.textContaining('บันทึกรถและเที่ยวรถ'), findsWidgets);

      // Move to labor section on the same page.
      final laborSaveButton = find.text('บันทึกการทำงาน');
      await _scrollUntilVisible(
        tester,
        laborSaveButton,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Drag one available employee chip into first labor bucket.
      final draggable = find.byType(LongPressDraggable<String>);
      final targets = find.byType(DragTarget<String>);

      if (draggable.evaluate().isNotEmpty && targets.evaluate().isNotEmpty) {
        await tester.longPress(draggable.first);
        await tester.pump(const Duration(milliseconds: 250));

        final from = tester.getCenter(draggable.first);
        final to = tester.getCenter(targets.first);
        final gesture = await tester.startGesture(from);
        await gesture.moveTo(to);
        await tester.pump(const Duration(milliseconds: 350));
        await gesture.up();
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
    },
  );
}

Future<void> _scrollUntilVisible(
  WidgetTester tester,
  Finder target, {
  required Finder scrollable,
}) async {
  var guard = 0;
  while (target.evaluate().isEmpty && guard < 12) {
    await tester.drag(scrollable, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 300));
    guard++;
  }
}
