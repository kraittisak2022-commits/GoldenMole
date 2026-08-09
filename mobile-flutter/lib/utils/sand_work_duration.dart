// Sand work duration from lapTimes (parity with countRecordAnalytics.ts).
// Lunch break 12:00-13:00 Bangkok time is deducted.

const int kSandLunchStartHour = 12;
const int kSandLunchEndHour = 13;
const int _tzOffsetMs = 7 * 60 * 60 * 1000;

class SandWorkDurationSummary {
  const SandWorkDurationSummary({
    required this.totalActiveHours,
    required this.lunchDeductedHours,
    this.startClock,
    this.endClock,
  });

  final double totalActiveHours;
  final double lunchDeductedHours;
  final String? startClock;
  final String? endClock;
}

int? parseLapStampMs(String stamp, String dayKey) {
  final s = stamp.trim();
  final space = s.indexOf(' ');
  if (space < 0) return null;
  final datePart = s.substring(0, space);
  final timePart = s.substring(space + 1);
  final dm = datePart.split('/');
  final hms = timePart.split(':');
  if (dm.length < 2 || hms.length < 2) return null;
  final dd = int.tryParse(dm[0]);
  final mm = int.tryParse(dm[1]);
  final hh = int.tryParse(hms[0]);
  final min = int.tryParse(hms.length > 1 ? hms[1] : '0') ?? 0;
  final sec = int.tryParse(hms.length > 2 ? hms[2] : '0') ?? 0;
  if (dd == null || mm == null || hh == null) return null;
  final ymd = dayKey.trim();
  if (ymd.length < 4) return null;
  final yy = int.tryParse(ymd.substring(0, 4));
  if (yy == null) return null;
  // Bangkok local → UTC epoch (same as web)
  final utcMs =
      DateTime.utc(yy, mm, dd, hh, min, sec).millisecondsSinceEpoch -
      _tzOffsetMs;
  return utcMs;
}

String? formatLapClock(String stamp) {
  final s = stamp.trim();
  final space = s.indexOf(' ');
  final timePart = space >= 0 ? s.substring(space + 1) : s;
  final parts = timePart.split(':');
  if (parts.length < 2) return null;
  final hh = parts[0].trim().padLeft(2, '0');
  final mm = parts[1].trim().padLeft(2, '0');
  return '$hh:$mm';
}

({int startMs, int endMs})? _lunchWindowMs(int refMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(refMs + _tzOffsetMs, isUtc: true);
  final startMs =
      DateTime.utc(d.year, d.month, d.day, kSandLunchStartHour).millisecondsSinceEpoch -
      _tzOffsetMs;
  final endMs =
      DateTime.utc(d.year, d.month, d.day, kSandLunchEndHour).millisecondsSinceEpoch -
      _tzOffsetMs;
  return (startMs: startMs, endMs: endMs);
}

int lunchOverlapMs(int startMs, int endMs) {
  if (endMs <= startMs) return 0;
  final lunch = _lunchWindowMs(startMs);
  if (lunch == null) return 0;
  final overlapStart = startMs > lunch.startMs ? startMs : lunch.startMs;
  final overlapEnd = endMs < lunch.endMs ? endMs : lunch.endMs;
  final o = overlapEnd - overlapStart;
  return o > 0 ? o : 0;
}

int activeDurationSec(int startMs, int endMs) {
  if (endMs <= startMs) return 0;
  final rawMs = endMs - startMs;
  final lunchMs = lunchOverlapMs(startMs, endMs);
  final activeMs = rawMs - lunchMs;
  if (activeMs <= 0) return 0;
  return (activeMs / 1000).round();
}

SandWorkDurationSummary? computeSandWorkDurationSummary(
  List<String> lapTimes,
  String dayKey,
) {
  final parsed = <({String stamp, int timeMs})>[];
  for (final stamp in lapTimes) {
    final ms = parseLapStampMs(stamp, dayKey);
    if (ms == null) continue;
    parsed.add((stamp: stamp, timeMs: ms));
  }
  if (parsed.isEmpty) return null;
  parsed.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  final first = parsed.first;
  final last = parsed.last;
  if (first.timeMs == last.timeMs) {
    return SandWorkDurationSummary(
      totalActiveHours: 0,
      lunchDeductedHours: 0,
      startClock: formatLapClock(first.stamp),
      endClock: formatLapClock(last.stamp),
    );
  }
  final rawSec = ((last.timeMs - first.timeMs) / 1000).round().clamp(0, 1 << 30);
  final activeSec = activeDurationSec(first.timeMs, last.timeMs);
  final lunchSec = (rawSec - activeSec).clamp(0, rawSec);
  return SandWorkDurationSummary(
    totalActiveHours: activeSec / 3600.0,
    lunchDeductedHours: lunchSec / 3600.0,
    startClock: formatLapClock(first.stamp),
    endClock: formatLapClock(last.stamp),
  );
}
