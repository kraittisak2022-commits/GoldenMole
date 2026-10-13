import '../models/app_transaction.dart';
import 'daily_module_transactions.dart';

/// ขอบเขตการวิเคราะห์ — สัปดาห์ / เดือน
enum OpsAnalyticsScope { week, month }

/// ตัวชี้วัดหลัก — ร่อนทราย (รอบ) / เที่ยวรถ
enum OpsAnalyticsMetric { sand, trips }

/// จุดรายวันในช่วงปัจจุบัน
class OpsDayPoint {
  const OpsDayPoint({
    required this.dayKey,
    required this.label,
    required this.value,
  });

  final String dayKey;
  final String label;
  final double value;
}

/// ถังรวมช่วงเวลา (สัปดาห์หรือเดือน)
class OpsPeriodBucket {
  const OpsPeriodBucket({
    required this.key,
    required this.label,
    required this.value,
    required this.dayCount,
    required this.startKey,
    required this.endKey,
  });

  final String key;
  final String label;
  final double value;
  final int dayCount;
  final String startKey;
  final String endKey;

  double get averagePerDay => dayCount <= 0 ? 0 : value / dayCount;
}

/// ผลการเติบโตแบบโปร — รวม / เฉลี่ย / เทียบช่วงก่อน / จังหวะ
class OpsGrowthSnapshot {
  const OpsGrowthSnapshot({
    required this.scope,
    required this.metric,
    required this.buckets,
    required this.dailyInCurrent,
    required this.current,
    required this.previous,
    required this.changePercent,
    required this.pace,
    required this.unitLabel,
  });

  final OpsAnalyticsScope scope;
  final OpsAnalyticsMetric metric;
  final List<OpsPeriodBucket> buckets;
  final List<OpsDayPoint> dailyInCurrent;
  final OpsPeriodBucket current;
  final OpsPeriodBucket? previous;
  final double? changePercent;
  final OpsPace pace;
  final String unitLabel;

  double get total => current.value;
  double get averagePerDay => current.averagePerDay;

  double get peakDaily {
    var peak = 0.0;
    for (final d in dailyInCurrent) {
      if (d.value > peak) peak = d.value;
    }
    return peak;
  }

  OpsDayPoint? get peakDay {
    OpsDayPoint? best;
    for (final d in dailyInCurrent) {
      if (best == null || d.value > best.value) best = d;
    }
    return best;
  }
}

enum OpsPace {
  accelerating,
  decelerating,
  steady,
  insufficient,
}

extension OpsPaceLabel on OpsPace {
  String get th {
    switch (this) {
      case OpsPace.accelerating:
        return 'เร็วขึ้น';
      case OpsPace.decelerating:
        return 'ช้าลง';
      case OpsPace.steady:
        return 'คงที่';
      case OpsPace.insufficient:
        return 'ข้อมูลไม่พอ';
    }
  }

  String get zh {
    switch (this) {
      case OpsPace.accelerating:
        return '加快';
      case OpsPace.decelerating:
        return '放缓';
      case OpsPace.steady:
        return '持平';
      case OpsPace.insufficient:
        return '数据不足';
    }
  }
}

abstract final class OpsGrowthAnalytics {
  static String dayKeyOf(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static DateTime? parseDayKey(String key) {
    final parts = key.trim().split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  /// จันทร์ของสัปดาห์ที่ครอบคลุม [day]
  static DateTime weekStartMonday(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    final weekday = date.weekday; // Mon=1 … Sun=7
    return date.subtract(Duration(days: weekday - 1));
  }

  static DateTime monthStart(DateTime day) =>
      DateTime(day.year, day.month, 1);

  static DateTime monthEnd(DateTime day) =>
      DateTime(day.year, day.month + 1, 0);

  static double valueForDay(
    String dayKey,
    OpsAnalyticsMetric metric,
    Iterable<AppTransaction> transactions,
  ) {
    switch (metric) {
      case OpsAnalyticsMetric.sand:
        return countRecordSandRoundsForDay(dayKey, transactions);
      case OpsAnalyticsMetric.trips:
        final s = vehicleTripSummaryForDay(dayKey, transactions);
        return s.morningTrips + s.afternoonTrips;
    }
  }

  static String unitLabel(OpsAnalyticsMetric metric, {bool zh = false}) {
    switch (metric) {
      case OpsAnalyticsMetric.sand:
        return zh ? '轮' : 'รอบ';
      case OpsAnalyticsMetric.trips:
        return zh ? '趟' : 'เที่ยว';
    }
  }

  static String metricTitle(OpsAnalyticsMetric metric, {bool zh = false}) {
    switch (metric) {
      case OpsAnalyticsMetric.sand:
        return zh ? '筛沙' : 'ร่อนทราย';
      case OpsAnalyticsMetric.trips:
        return zh ? '车次' : 'เที่ยวรถ';
    }
  }

  static OpsGrowthSnapshot build({
    required List<AppTransaction> transactions,
    required OpsAnalyticsScope scope,
    required OpsAnalyticsMetric metric,
    DateTime? now,
    int historyBuckets = 8,
  }) {
    final today = now ?? DateTime.now();
    final anchor = DateTime(today.year, today.month, today.day);
    final unit = unitLabel(metric);

    final buckets = <OpsPeriodBucket>[];
    if (scope == OpsAnalyticsScope.week) {
      var start = weekStartMonday(anchor);
      for (var i = historyBuckets - 1; i >= 0; i--) {
        final ws = start.subtract(Duration(days: 7 * i));
        final we = ws.add(const Duration(days: 6));
        final end = we.isAfter(anchor) ? anchor : we;
        buckets.add(_bucketForRange(
          transactions: transactions,
          metric: metric,
          start: ws,
          end: end,
          key: dayKeyOf(ws),
          label: _weekLabel(ws, end),
        ));
      }
    } else {
      var cursor = monthStart(anchor);
      for (var i = historyBuckets - 1; i >= 0; i--) {
        final ms = DateTime(cursor.year, cursor.month - i, 1);
        final me = monthEnd(ms);
        final end = me.isAfter(anchor) ? anchor : me;
        buckets.add(_bucketForRange(
          transactions: transactions,
          metric: metric,
          start: ms,
          end: end,
          key: '${ms.year}-${ms.month.toString().padLeft(2, '0')}',
          label: _monthLabel(ms),
        ));
      }
    }

    final current = buckets.isNotEmpty
        ? buckets.last
        : OpsPeriodBucket(
            key: dayKeyOf(anchor),
            label: '—',
            value: 0,
            dayCount: 1,
            startKey: dayKeyOf(anchor),
            endKey: dayKeyOf(anchor),
          );
    final previous = buckets.length >= 2 ? buckets[buckets.length - 2] : null;

    double? changePercent;
    if (previous != null && previous.value > 0) {
      changePercent = ((current.value - previous.value) / previous.value) * 100;
    } else if (previous != null && previous.value == 0 && current.value > 0) {
      changePercent = 100;
    } else if (previous != null && previous.value == 0 && current.value == 0) {
      changePercent = 0;
    }

    final daily = _dailyPoints(
      transactions: transactions,
      metric: metric,
      startKey: current.startKey,
      endKey: current.endKey,
    );

    final pace = _resolvePace(
      buckets: buckets,
      changePercent: changePercent,
      daily: daily,
    );

    return OpsGrowthSnapshot(
      scope: scope,
      metric: metric,
      buckets: buckets,
      dailyInCurrent: daily,
      current: current,
      previous: previous,
      changePercent: changePercent,
      pace: pace,
      unitLabel: unit,
    );
  }

  static OpsPeriodBucket _bucketForRange({
    required Iterable<AppTransaction> transactions,
    required OpsAnalyticsMetric metric,
    required DateTime start,
    required DateTime end,
    required String key,
    required String label,
  }) {
    var total = 0.0;
    var days = 0;
    for (var d = start;
        !d.isAfter(end);
        d = d.add(const Duration(days: 1))) {
      total += valueForDay(dayKeyOf(d), metric, transactions);
      days++;
    }
    return OpsPeriodBucket(
      key: key,
      label: label,
      value: total,
      dayCount: days <= 0 ? 1 : days,
      startKey: dayKeyOf(start),
      endKey: dayKeyOf(end),
    );
  }

  static List<OpsDayPoint> _dailyPoints({
    required Iterable<AppTransaction> transactions,
    required OpsAnalyticsMetric metric,
    required String startKey,
    required String endKey,
  }) {
    final start = parseDayKey(startKey);
    final end = parseDayKey(endKey);
    if (start == null || end == null) return const [];
    final out = <OpsDayPoint>[];
    for (var d = start;
        !d.isAfter(end);
        d = d.add(const Duration(days: 1))) {
      final key = dayKeyOf(d);
      out.add(OpsDayPoint(
        dayKey: key,
        label: '${d.day}/${d.month}',
        value: valueForDay(key, metric, transactions),
      ));
    }
    return out;
  }

  static String _weekLabel(DateTime start, DateTime end) {
    return '${start.day}/${start.month}–${end.day}/${end.month}';
  }

  static String _monthLabel(DateTime month) {
    const th = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    final yy = (month.year + 543) % 100;
    return '${th[month.month - 1]} $yy';
  }

  /// จังหวะ: เทียบครึ่งหลังของช่วงปัจจุบันกับครึ่งแรก + เทียบ WoW/MoM
  static OpsPace _resolvePace({
    required List<OpsPeriodBucket> buckets,
    required double? changePercent,
    required List<OpsDayPoint> daily,
  }) {
    if (daily.length >= 4) {
      final mid = daily.length ~/ 2;
      final first = daily.sublist(0, mid);
      final second = daily.sublist(mid);
      final a1 = _avg(first.map((e) => e.value));
      final a2 = _avg(second.map((e) => e.value));
      if (a1 <= 0 && a2 <= 0) {
        // fall through to period compare
      } else if (a1 <= 0 && a2 > 0) {
        return OpsPace.accelerating;
      } else {
        final delta = ((a2 - a1) / (a1 <= 0 ? 1 : a1)) * 100;
        if (delta >= 8) return OpsPace.accelerating;
        if (delta <= -8) return OpsPace.decelerating;
      }
    }

    if (changePercent == null) return OpsPace.insufficient;
    if (changePercent >= 5) return OpsPace.accelerating;
    if (changePercent <= -5) return OpsPace.decelerating;
    return OpsPace.steady;
  }

  static double _avg(Iterable<double> values) {
    var sum = 0.0;
    var n = 0;
    for (final v in values) {
      sum += v;
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }
}
