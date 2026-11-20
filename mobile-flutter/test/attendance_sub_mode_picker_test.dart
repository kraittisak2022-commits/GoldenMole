import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/theme/daily_palette.dart';
import 'package:mobile_flutter/utils/attendance_board_summary.dart';
import 'package:mobile_flutter/widgets/attendance_sub_mode_picker.dart';

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
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets('displays date, progress bars, stat badges, and invokes onSelect', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    AttendanceSection? picked;
    await tester.pumpWidget(
      _wrap(
        AttendanceSubModePicker(
          dateLabel: '19/11/2569',
          sandYardSummary: 'ทำงาน 5 · ลาเต็ม 1',
          driverSummary: 'แม็คโคร 3 · ดรัม 1',
          sandProgress: const AttendanceGroupProgress(
            checkedCount: 6,
            totalCount: 8,
          ),
          driverProgress: const AttendanceGroupProgress(
            checkedCount: 4,
            totalCount: 4,
          ),
          sandStats: buildAttendanceSandYardStats(
            work: 5,
            leaveFull: 1,
            leaveMorning: 0,
            leaveAfternoon: 0,
          ),
          driverStats: buildAttendanceDriverStats(
            macro: 3,
            drum: 1,
            leaveFull: 0,
            leaveMorning: 0,
            leaveAfternoon: 0,
          ),
          onSelect: (s) => picked = s,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('19/11/2569'), findsOneWidget);
    expect(find.textContaining('6 / 8'), findsOneWidget);
    expect(find.textContaining('4 / 4'), findsOneWidget);
    expect(find.text('ครบแล้ว'), findsOneWidget);
    expect(find.text('เหลือ 2 คน'), findsOneWidget);
    expect(find.text('ทำงาน 5'), findsOneWidget);
    expect(find.text('ลาเต็มวัน 1'), findsOneWidget);
    expect(find.text('แม็คโคร 3'), findsOneWidget);
    expect(find.text('ดรัม 1'), findsOneWidget);

    await tester.tap(find.text('เช็คชื่อพนักงานท่าทราย'));
    await tester.pump();
    expect(picked, AttendanceSection.sandYard);

    await tester.tap(find.text('เช็คชื่อคนขับรถ'));
    await tester.pump();
    expect(picked, AttendanceSection.driver);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders cleanly on narrow 360px portrait and dark tablet landscape', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        AttendanceSubModePicker(
          dateLabel: '19/11/2569',
          sandYardSummary: 'ยังไม่มีรายชื่อ',
          driverSummary: 'ยังไม่มีรายชื่อ',
          sandProgress: const AttendanceGroupProgress(checkedCount: 0, totalCount: 10),
          driverProgress: const AttendanceGroupProgress(checkedCount: 0, totalCount: 5),
          onSelect: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1024, 768);
    await tester.pumpWidget(
      _wrap(
        AttendanceSubModePicker(
          dateLabel: '19/11/2569',
          sandYardSummary: 'ทำงาน 10',
          driverSummary: 'แม็คโคร 5',
          sandProgress: const AttendanceGroupProgress(checkedCount: 10, totalCount: 10),
          driverProgress: const AttendanceGroupProgress(checkedCount: 5, totalCount: 5),
          sandStats: buildAttendanceSandYardStats(
            work: 10,
            leaveFull: 0,
            leaveMorning: 0,
            leaveAfternoon: 0,
          ),
          driverStats: buildAttendanceDriverStats(
            macro: 5,
            drum: 0,
            leaveFull: 0,
            leaveMorning: 0,
            leaveAfternoon: 0,
          ),
          onSelect: (_) {},
        ),
        brightness: Brightness.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ครบแล้ว'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
