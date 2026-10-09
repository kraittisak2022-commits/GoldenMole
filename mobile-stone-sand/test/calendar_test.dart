import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/logic/calendar.dart';
import 'package:mobile_stone_sand/widgets/calendar_picker.dart';

void main() {
  group('monthGrid', () {
    test('starts on the Sunday on or before the 1st and spans six weeks', () {
      final grid = monthGrid((year: 2026, month: 10)); // October 2026 starts on a Thursday
      expect(grid, hasLength(42));
      expect(grid[0], '2026-09-27');
      expect(grid[4], '2026-10-01');
      expect(grid[41], '2026-11-07');
    });

    test('starts on the 1st when the month begins on a Sunday', () {
      expect(monthGrid((year: 2026, month: 2))[0], '2026-02-01');
    });
  });

  test('shiftMonth crosses year boundaries', () {
    expect(shiftMonth((year: 2026, month: 12), 1), (year: 2027, month: 1));
    expect(shiftMonth((year: 2026, month: 1), -1), (year: 2025, month: 12));
  });

  test('yearMonthOf / sameMonth read the month of an ISO date', () {
    expect(yearMonthOf('2026-10-09'), (year: 2026, month: 10));
    expect(sameMonth('2026-10-31', (year: 2026, month: 10)), isTrue);
    expect(sameMonth('2026-11-01', (year: 2026, month: 10)), isFalse);
  });

  testWidgets('calendar shows the Buddhist-era month, order dots and picks a day', (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CalendarPanel(
          value: '2026-10-09',
          today: '2026-10-09',
          counts: const {'2026-10-05': 3},
          onSelect: (iso) => picked = iso,
        ),
      ),
    ));
    expect(find.text('ตุลาคม 2569'), findsOneWidget);
    expect(find.text('มีออเดอร์'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('มีออเดอร์ 3 รายการ')), findsOneWidget);

    await tester.tap(find.text('15'));
    expect(picked, '2026-10-15');

    await tester.tap(find.byTooltip('เดือนถัดไป'));
    await tester.pump();
    expect(find.text('พฤศจิกายน 2569'), findsOneWidget);
    expect(find.text('มีออเดอร์'), findsNothing);

    await tester.tap(find.text('วันนี้'));
    expect(picked, '2026-10-09');
  });
}
