import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/theme/daily_palette.dart';
import 'package:mobile_flutter/utils/attendance_board_summary.dart';
import 'package:mobile_flutter/widgets/attendance_board_widgets.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      extensions: [
        brightness == Brightness.dark ? DailyColors.dark : DailyColors.light,
      ],
    ),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('AttendanceBoardHeader shows progress, date, and switch action', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var backed = false;
    var switched = false;

    await tester.pumpWidget(
      _wrap(
        AttendanceBoardHeader(
          title: 'พนักงานท่าทราย',
          dateLabel: '19/11/2569',
          progress: const AttendanceGroupProgress(
            checkedCount: 6,
            totalCount: 8,
          ),
          switchLabel: 'คนขับรถ',
          onBack: () => backed = true,
          onSwitchSection: () => switched = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('พนักงานท่าทราย'), findsOneWidget);
    expect(find.textContaining('19/11/2569'), findsOneWidget);
    expect(find.textContaining('6/8'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pump();
    expect(backed, isTrue);

    await tester.tap(find.text('คนขับรถ'));
    await tester.pump();
    expect(switched, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AttendanceSelectionBar displays quick-assign actions and fires callbacks', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? assignedBucket;
    var cleared = false;

    await tester.pumpWidget(
      _wrap(
        AttendanceSelectionBar(
          selectedCount: 3,
          targets: const [
            AttendanceQuickAssignTarget(
              bucketId: 'att_work',
              label: 'มาทำงาน',
              color: kAttendanceWorkColor,
              icon: Icons.engineering_rounded,
            ),
            AttendanceQuickAssignTarget(
              bucketId: 'att_leave_full',
              label: 'ลาเต็มวัน',
              color: kAttendanceLeaveColor,
              icon: Icons.event_busy_rounded,
            ),
          ],
          onAssignToBucket: (id) => assignedBucket = id,
          onClearSelection: () => cleared = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('เลือกอยู่ 3 คน'), findsOneWidget);

    await tester.tap(find.text('มาทำงาน'));
    await tester.pump();
    expect(assignedBucket, 'att_work');

    await tester.tap(find.text('ยกเลิก'));
    await tester.pump();
    expect(cleared, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AttendancePoolPanel shows completion celebration when all checked in', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final scrollCtrl = ScrollController();
    final searchCtrl = TextEditingController();
    addTearDown(scrollCtrl.dispose);
    addTearDown(searchCtrl.dispose);

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          height: 220,
          child: AttendancePoolPanel(
            title: 'รอเช็คชื่อ',
            remainingCount: 0,
            totalGroupCount: 8,
            visiblePeople: const [],
            selectedCount: 0,
            searchOpen: false,
            searchQuery: '',
            searchController: searchCtrl,
            scrollController: scrollCtrl,
            accent: kAttendanceWorkColor,
            emptyConfigText: 'ไม่มีพนักงาน',
            onToggleSearch: () {},
            onSearchChanged: (_) {},
            onSelectAllRemaining: () {},
            onClearSelection: () {},
            onTogglePerson: (_) {},
            onAcceptDropBack: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('เช็คชื่อครบทั้ง 8 คนแล้ว'), findsOneWidget);
    expect(find.text('ไม่มีพนักงาน'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AttendanceBoardCard keeps sub-zone labels visible even when filled', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? removedEmp;
    String? tappedBucket;

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          height: 360,
          child: AttendanceBoardCard(
            title: 'ลางาน',
            icon: Icons.event_busy_rounded,
            color: kAttendanceLeaveColor,
            pickedCount: 2,
            equalHeightZones: true,
            zones: const [
              AttendanceZoneSlotData(
                bucketId: 'att_leave_full',
                label: 'ลาเต็มวัน',
                emptyHint: 'แตะหรือลากวาง',
                activeChips: [
                  AttendancePlacedChipData(
                    empId: 'e1',
                    displayName: 'สมชาย',
                    isTimedWork: false,
                  ),
                ],
                closedSessions: [],
              ),
              AttendanceZoneSlotData(
                bucketId: 'att_leave_morning',
                label: 'ช่วงเช้า',
                emptyHint: 'แตะหรือลากวาง',
                activeChips: [],
                closedSessions: [],
              ),
              AttendanceZoneSlotData(
                bucketId: 'att_leave_afternoon',
                label: 'ช่วงบ่าย',
                emptyHint: 'แตะหรือลากวาง',
                activeChips: [],
                closedSessions: [],
              ),
            ],
            onTapZone: (bucketId) => tappedBucket = bucketId,
            onAcceptDrop: (_, _) {},
            onRemoveEmp: (_, empId) => removedEmp = empId,
            onDeleteClosedSession: (_) {},
          ),
        ),
        brightness: Brightness.dark,
      ),
    );
    await tester.pumpAndSettle();

    // Even though 'ลาเต็มวัน' has a chip inside, its label stays visible!
    expect(find.text('ลาเต็มวัน'), findsOneWidget);
    expect(find.text('ช่วงเช้า'), findsOneWidget);
    expect(find.text('ช่วงบ่าย'), findsOneWidget);
    expect(find.text('สมชาย'), findsOneWidget);
    expect(find.textContaining('วาง 2 คน'), findsWidgets);

    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump();
    expect(removedEmp, 'e1');

    await tester.tap(find.text('ช่วงเช้า'));
    await tester.pump();
    expect(tappedBucket, 'att_leave_morning');
    expect(tester.takeException(), isNull);
  });

  testWidgets('AttendanceBottomDock shows stats, unsaved indicator, and save CTA', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var saved = false;
    await tester.pumpWidget(
      _wrap(
        Align(
          alignment: Alignment.bottomCenter,
          child: AttendanceBottomDock(
            stats: buildAttendanceSandYardStats(
              work: 5,
              leaveFull: 1,
              leaveMorning: 0,
              leaveAfternoon: 0,
            ),
            remainingCount: 2,
            hasUnsavedChanges: true,
            canSave: true,
            saveLabel: 'บันทึกเช็คชื่อ · 6 คน',
            onSave: () => saved = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ทำงาน 5'), findsOneWidget);
    expect(find.text('ลาเต็มวัน 1'), findsOneWidget);
    expect(find.text('ยังไม่บันทึก'), findsOneWidget);

    await tester.tap(find.text('บันทึกเช็คชื่อ · 6 คน'));
    await tester.pump();
    expect(saved, isTrue);
    expect(tester.takeException(), isNull);
  });
}
