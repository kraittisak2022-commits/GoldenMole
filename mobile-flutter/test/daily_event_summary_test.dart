import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_transaction.dart';
import 'package:mobile_flutter/utils/daily_event_summary.dart';

const _day = '2026-11-20';

AppTransaction _event({
  required String id,
  required String desc,
  String? eventType = 'info',
  String? eventPriority = 'normal',
  String? eventTime,
  DateTime? createdAt,
  String date = _day,
  String category = 'DailyLog',
  String subCategory = 'Event',
}) =>
    AppTransaction(
      id: id,
      date: date,
      type: 'Expense',
      category: category,
      subCategory: subCategory,
      description: desc,
      amount: 0,
      eventType: eventType,
      eventPriority: eventPriority,
      eventTime: eventTime,
      createdAt: createdAt,
    );

void main() {
  group('daily event type & priority normalization', () {
    test('normalizes known types and falls back to info', () {
      expect(normalizeDailyEventType('problem'), 'problem');
      expect(normalizeDailyEventType(' WARNING '), 'warning');
      expect(normalizeDailyEventType('complaint'), 'complaint');
      expect(normalizeDailyEventType('request'), 'request');
      expect(normalizeDailyEventType('success'), 'success');
      expect(normalizeDailyEventType('unknown'), 'info');
      expect(normalizeDailyEventType(null), 'info');
    });

    test('recognizes both urgent and legacy high priorities', () {
      expect(isDailyEventUrgent('urgent'), isTrue);
      expect(isDailyEventUrgent('HIGH'), isTrue);
      expect(isDailyEventUrgent('normal'), isFalse);
      expect(isDailyEventUrgent(null), isFalse);
    });

    test('strips and extracts recorder suffix cleanly', () {
      const raw = 'เครื่องจักรเสีย (ผู้กรอก: สมชาย)';
      expect(stripDailyEventRecorderSuffix(raw), 'เครื่องจักรเสีย');
      expect(extractDailyEventRecorderName(raw), 'สมชาย');
      expect(extractDailyEventRecorderName('ฝนตกหนัก'), isNull);
    });
  });

  group('dailyEventEntriesForDay & overview & filters', () {
    test('filters to day events, excludes non-events, and sorts newest first', () {
      final morning = _event(
        id: 'e1',
        desc: 'ฝนตก หยุดงาน (ผู้กรอก: เอ)',
        eventType: 'warning',
        eventPriority: 'normal',
        eventTime: '08:30',
        createdAt: DateTime.utc(2026, 11, 20, 1, 30),
      );
      final afternoon = _event(
        id: 'e2',
        desc: 'เครื่องจักรเสีย (ผู้กรอก: บี)',
        eventType: 'problem',
        eventPriority: 'urgent',
        eventTime: '14:15',
        createdAt: DateTime.utc(2026, 11, 20, 7, 15),
      );
      final noTime = _event(
        id: 'e3',
        desc: 'งานเสร็จตามแผน',
        eventType: 'success',
        eventPriority: 'normal',
        createdAt: DateTime.utc(2026, 11, 20, 10, 0),
      );
      final otherDay = _event(
        id: 'e4',
        desc: 'เมื่อวาน',
        date: '2026-11-19',
      );
      final fuelRow = _event(
        id: 'f1',
        desc: 'เติมน้ำมัน',
        category: 'Fuel',
        subCategory: 'Withdraw',
      );
      final emptyDesc = _event(id: 'e5', desc: '   ');

      final list = dailyEventEntriesForDay(
        dayYmd: _day,
        transactions: [morning, otherDay, fuelRow, emptyDesc, afternoon, noTime],
      );

      // Newest first by eventTime/createdAt: e3 (17:00 local? wait createdAt UTC vs eventTime)
      // Explicitly verify e2 (14:15) comes before e1 (08:30), and all 3 valid rows are included
      expect(list.length, 3);
      expect(list.indexWhere((e) => e.id == 'e2'), lessThan(list.indexWhere((e) => e.id == 'e1')));
      expect(dailyEventDisplayTime(morning), '08:30');
      expect(dailyEventDisplayTime(afternoon), '14:15');

      final overview = summarizeDailyEvents(list);
      expect(overview.totalCount, 3);
      expect(overview.urgentCount, 1);
      expect(overview.issueCount, 2); // problem + warning

      expect(matchesDailyEventFilter(afternoon, DailyEventFilter.urgent), isTrue);
      expect(matchesDailyEventFilter(morning, DailyEventFilter.urgent), isFalse);
      expect(matchesDailyEventFilter(morning, DailyEventFilter.issues), isTrue);
      expect(matchesDailyEventFilter(noTime, DailyEventFilter.issues), isFalse);
      expect(matchesDailyEventFilter(noTime, DailyEventFilter.all), isTrue);
    });
  });

  group('applyQuickEventTemplate', () {
    test('auto-sets description, type, and priority when text is empty', () {
      final breakdown = kDailyEventQuickTemplates.firstWhere(
        (t) => t.text == 'เครื่องจักรเสีย',
      );
      final res = applyQuickEventTemplate(
        currentText: '',
        currentType: 'info',
        currentPriority: 'normal',
        template: breakdown,
      );
      expect(res.text, 'เครื่องจักรเสีย');
      expect(res.type, 'problem');
      expect(res.priority, 'urgent');
    });

    test('appends cleanly without overriding type/priority when text already exists', () {
      final rain = kDailyEventQuickTemplates.firstWhere(
        (t) => t.text == 'ฝนตก หยุดงาน',
      );
      final res = applyQuickEventTemplate(
        currentText: 'หน้างานเปียก',
        currentType: 'problem',
        currentPriority: 'urgent',
        template: rain,
      );
      expect(res.text, 'หน้างานเปียก, ฝนตก หยุดงาน');
      expect(res.type, 'problem');
      expect(res.priority, 'urgent');

      // Does not duplicate if already present
      final dup = applyQuickEventTemplate(
        currentText: res.text,
        currentType: res.type,
        currentPriority: res.priority,
        template: rain,
      );
      expect(dup.text, res.text);
    });
  });
}
