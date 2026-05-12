import 'dart:math' as math;

import '../models/app_transaction.dart';

/// คีย์ yyyy-MM-dd — สอดคล้อง `normalizeDate` / `_normalizeSandDayKey` บนเว็บ
String normalizeSandDrumDayKey(String raw) {
  final s = raw.trim();
  if (s.length >= 10) return s.substring(0, 10);
  return s;
}

String addOneCalendarDayYmd(String ymd) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(ymd.trim());
  if (m == null) return ymd;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final next = DateTime.utc(y, mo, d).add(const Duration(days: 1));
  return '${next.year.toString().padLeft(4, '0')}-'
      '${next.month.toString().padLeft(2, '0')}-'
      '${next.day.toString().padLeft(2, '0')}';
}

class SandRoundDailyRow {
  SandRoundDailyRow({
    required this.date,
    this.transported = 0,
    this.washed = 0,
    this.obtained = 0,
    this.home = 0,
  });

  final String date;
  double transported;
  double washed;
  double obtained;
  double home;
}

/// สรุปรายวันเดียวกับ `buildSandRoundDailyRows` ใน `dailyStepRecorderUtils.ts`
List<SandRoundDailyRow> buildSandRoundDailyRows(List<AppTransaction> transactions) {
  final dailyMap = <String, SandRoundDailyRow>{};

  for (final t in transactions) {
    final d = normalizeSandDrumDayKey(t.date);
    if (d.isEmpty) continue;
    final daily = dailyMap.putIfAbsent(d, () => SandRoundDailyRow(date: d));

    if (t.category == 'DailyLog' && t.subCategory == 'VehicleTrip') {
      final tripCubic = (t.totalCubic ?? t.quantity ?? 0).toDouble();
      if (tripCubic > 0) daily.transported += tripCubic;
    }

    if (t.category == 'DailyLog' && t.subCategory == 'Sand') {
      final washed = (t.sandMorning ?? 0) + (t.sandAfternoon ?? 0);
      if (washed > 0) daily.washed += washed;
      final obtained = math.max(0.0, (t.drumsObtained ?? 0).toDouble());
      if (obtained > daily.obtained) daily.obtained = obtained;
      final homeSand = math.max(0.0, (t.drumsWashedAtHome ?? 0).toDouble());
      if (homeSand > daily.home) daily.home = homeSand;
    }

    if (t.category == 'Labor') {
      final homeLabor = math.max(0.0, (t.drumsWashedAtHome ?? 0).toDouble());
      if (homeLabor > 0 && homeLabor > daily.home) daily.home = homeLabor;
    }
  }

  final list = dailyMap.values.toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return list;
}

String? parseRoundStartDateFromRoundId(String roundId) {
  final m = RegExp(r'^round_\d+_(\d{4}-\d{2}-\d{2})$').firstMatch(roundId.trim());
  return m?.group(1);
}

String maxYmd(String a, String b) => a.compareTo(b) >= 0 ? a : b;

class _InternalSandRound {
  _InternalSandRound({
    required this.id,
    required this.roundNo,
    required this.startDate,
    required this.endDate,
    required this.obtainedDrums,
    required this.washedHomeDrums,
    required this.remainingDrums,
    required this.completed,
    required this.days,
  });

  final String id;
  final int roundNo;
  final String startDate;
  String endDate;
  double obtainedDrums;
  double washedHomeDrums;
  double remainingDrums;
  bool completed;
  final List<SandRoundDailyRow> days;
}

List<_InternalSandRound> _buildSandRoundsFromDailyRows(
  List<SandRoundDailyRow> dailyRows,
  List<Map<String, dynamic>> sandRoundAuditTrail,
  int roundCloseMinDays,
) {
  final manualClosedIds = <String>{
    for (final a in sandRoundAuditTrail)
      if ('${a['action'] ?? ''}' == 'manual_close_round') '${a['roundId'] ?? ''}',
  };
  final manualClosedStartDates = <String>{};
  for (final a in sandRoundAuditTrail) {
    if ('${a['action'] ?? ''}' != 'manual_close_round') continue;
    final sd = parseRoundStartDateFromRoundId('${a['roundId'] ?? ''}');
    if (sd != null) manualClosedStartDates.add(sd);
  }

  final rounds = <_InternalSandRound>[];
  var roundNo = 0;
  _InternalSandRound? current;

  for (final r in dailyRows) {
    final active =
        r.transported > 0 || r.washed > 0 || r.obtained > 0 || r.home > 0;
    if (!active) continue;

    if (current == null) {
      roundNo += 1;
      current = _InternalSandRound(
        id: 'round_${roundNo}_${r.date}',
        roundNo: roundNo,
        startDate: r.date,
        endDate: r.date,
        obtainedDrums: 0,
        washedHomeDrums: 0,
        remainingDrums: 0,
        completed: false,
        days: [],
      );
    }

    current.endDate = r.date;
    current.obtainedDrums += r.obtained;
    current.washedHomeDrums += r.home;
    current.remainingDrums = math.max(
      0.0,
      math.min(9999999.0, current.obtainedDrums - current.washedHomeDrums),
    );
    current.days.add(r);

    final minDays = roundCloseMinDays < 1 ? 1 : roundCloseMinDays;
    final isAutoCompleted = current.remainingDrums == 0 &&
        current.obtainedDrums > 0 &&
        current.days.length >= minDays;
    final isForceClosed = manualClosedIds.contains(current.id);
    final isCompleted = isAutoCompleted || isForceClosed;

    if (isCompleted) {
      current.completed = true;
      rounds.add(current);
      current = null;
    }
  }

  if (current != null) {
    rounds.add(current);
  }

  for (final r in rounds) {
    if (r.completed) continue;
    final byExact = manualClosedIds.contains(r.id);
    final byStart = manualClosedStartDates.contains(r.startDate);
    if (byExact || byStart) {
      r.completed = true;
    }
  }

  return rounds;
}

/// วันแรกที่นับ “คงเหลือถังสะสม” ใหม่หลังรอบล้างทรายที่ปิดแล้ว — สอดคล้อง `computeSandDrumCarryoverEpochStart` บนเว็บ
String computeSandDrumCarryoverEpochStart(
  String selectedDate,
  List<AppTransaction> transactions, {
  List<Map<String, dynamic>> sandRoundAuditTrail = const [],
  int roundCloseMinDays = 2,
}) {
  final norm = normalizeSandDrumDayKey(selectedDate);
  final minDays = roundCloseMinDays < 1 ? 1 : roundCloseMinDays;
  final dailyRows = buildSandRoundDailyRows(transactions);
  final rounds = _buildSandRoundsFromDailyRows(
    dailyRows,
    sandRoundAuditTrail,
    minDays,
  );

  var epochStart = '0000-01-01';
  final completedBefore =
      rounds.where((r) => r.completed && r.endDate.compareTo(norm) < 0).toList();
  if (completedBefore.isNotEmpty) {
    final last = completedBefore.last;
    epochStart = addOneCalendarDayYmd(last.endDate);
  }

  _InternalSandRound? openContaining;
  for (final r in rounds) {
    if (!r.completed &&
        r.startDate.compareTo(norm) <= 0 &&
        r.endDate.compareTo(norm) >= 0) {
      openContaining = r;
      break;
    }
  }

  if (openContaining != null) {
    epochStart = maxYmd(epochStart, openContaining.startDate);
  }

  return epochStart;
}
