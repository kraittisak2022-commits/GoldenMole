import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/utils/daily_event_summary.dart';
import 'package:mobile_flutter/widgets/daily_event_widgets.dart';

const _day = '2026-11-20';

AppTransaction _event({
  required String id,
  required String desc,
  required String type,
  String priority = 'normal',
  String? eventTime,
}) =>
    AppTransaction(
      id: id,
      date: _day,
      type: 'Expense',
      category: 'DailyLog',
      subCategory: 'Event',
      description: desc,
      amount: 0,
      eventType: type,
      eventPriority: priority,
      eventTime: eventTime,
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
    'composer widgets render cleanly on 360px phone portrait and invoke callbacks without overflow',
    (tester) async {
      String? pickedType;
      String? pickedPriority;
      var timePicked = false;
      var timeCleared = false;
      DailyEventQuickTemplate? pickedTemplate;

      await tester.pumpWidget(
        _wrap(
          size: const Size(360, 740),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DailyEventOverviewHeader(
                dateLabel: '20/11/2569',
                overview: DailyEventDayOverview(
                  totalCount: 3,
                  urgentCount: 1,
                  issueCount: 2,
                ),
              ),
              const SizedBox(height: 12),
              DailyEventTypeGrid(
                selectedType: 'info',
                compact: true,
                onSelect: (t) => pickedType = t,
              ),
              const SizedBox(height: 12),
              DailyEventPriorityAndTimeBar(
                priority: 'normal',
                timeText: '09:30',
                compact: true,
                onPriorityChanged: (p) => pickedPriority = p,
                onPickTime: () => timePicked = true,
                onClearTime: () => timeCleared = true,
              ),
              const SizedBox(height: 12),
              DailyEventQuickTemplatesStrip(
                compact: true,
                onSelectTemplate: (tmpl) => pickedTemplate = tmpl,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('บันทึกเหตุการณ์'), findsOneWidget);
      expect(find.text('ด่วน 1'), findsOneWidget);
      expect(find.text('ปัญหา'), findsOneWidget);
      expect(find.text('09:30'), findsOneWidget);

      await tester.tap(find.text('ปัญหา'));
      await tester.pump();
      expect(pickedType, 'problem');

      await tester.tap(find.text('ด่วน'));
      await tester.pump();
      expect(pickedPriority, 'urgent');

      await tester.tap(find.text('09:30'));
      await tester.pump();
      expect(timePicked, isTrue);

      await tester.tap(find.byTooltip('ล้างเวลาเกิดเหตุ'));
      await tester.pump();
      expect(timeCleared, isTrue);

      await tester.tap(find.text('เครื่องจักรเสีย'));
      await tester.pump();
      expect(pickedTemplate?.text, 'เครื่องจักรเสีย');
    },
  );

  testWidgets(
    'DailyEventDayLogSection displays semantic cards, filters, recorder name, and edit/delete actions on 360px phone',
    (tester) async {
      final urgentProblem = _event(
        id: 'e1',
        desc: 'เครื่องจักรเสีย (ผู้กรอก: สมชาย)',
        type: 'problem',
        priority: 'urgent',
        eventTime: '14:15',
      );
      final warning = _event(
        id: 'e2',
        desc: 'ฝนตก หยุดงาน (ผู้กรอก: สมหญิง)',
        type: 'warning',
        priority: 'normal',
        eventTime: '08:30',
      );
      final ok = _event(
        id: 'e3',
        desc: 'งานเสร็จตามแผน',
        type: 'success',
        priority: 'normal',
        eventTime: '16:30',
      );

      DailyEventFilter? pickedFilter;
      AppTransaction? edited;
      AppTransaction? deleted;

      await tester.pumpWidget(
        _wrap(
          size: const Size(360, 740),
          child: DailyEventDayLogSection(
            entries: [ok, urgentProblem, warning],
            filter: DailyEventFilter.all,
            editingTxId: 'e1',
            onFilterChanged: (f) => pickedFilter = f,
            onEdit: (tx) => edited = tx,
            onDelete: (tx) => deleted = tx,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('เหตุการณ์วันนี้'), findsOneWidget);
      expect(find.text('3 รายการ'), findsOneWidget);
      expect(find.text('ทั้งหมด (3)'), findsOneWidget);
      expect(find.text('ด่วน (1)'), findsOneWidget);
      expect(find.text('ปัญหา/เตือน (2)'), findsOneWidget);
      expect(find.text('เครื่องจักรเสีย'), findsOneWidget);
      expect(find.text('ผู้กรอก: สมชาย'), findsOneWidget);
      expect(find.text('กำลังแก้ไข'), findsOneWidget);

      await tester.tap(find.text('ด่วน (1)'));
      await tester.pump();
      expect(pickedFilter, DailyEventFilter.urgent);

      await tester.tap(find.byTooltip('แก้ไขเหตุการณ์ 08:30'));
      await tester.pump();
      expect(edited?.id, 'e2');

      await tester.tap(find.byTooltip('ลบเหตุการณ์ 08:30'));
      await tester.pump();
      expect(deleted?.id, 'e2');
    },
  );

  testWidgets(
    'DailyEventEditingBanner and empty log render cleanly on dark tablet landscape',
    (tester) async {
      final entry = _event(
        id: 'e1',
        desc: 'ไฟฟ้าดับทั้งหน้างาน (ผู้กรอก: สมชาย)',
        type: 'problem',
        priority: 'urgent',
        eventTime: '11:20',
      );
      var cancelled = false;

      await tester.pumpWidget(
        _wrap(
          size: const Size(1024, 768),
          brightness: Brightness.dark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DailyEventEditingBanner(
                entry: entry,
                onCancel: () => cancelled = true,
              ),
              const SizedBox(height: 12),
              DailyEventDayLogSection(
                entries: const [],
                filter: DailyEventFilter.all,
                onFilterChanged: (_) {},
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('กำลังแก้ไขเหตุการณ์เดิม'), findsOneWidget);
      expect(find.textContaining('ไฟฟ้าดับทั้งหน้างาน'), findsOneWidget);
      expect(find.text('ยังไม่มีเหตุการณ์ของวันนี้'), findsOneWidget);

      await tester.tap(find.text('ยกเลิก'));
      await tester.pump();
      expect(cancelled, isTrue);
    },
  );
}
