import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// เก็บว่าวันไหนในสัปดาห์เป็นวันหยุดประจำ (ค่าเริ่มต้นวันพุธ) โดยคีย์คือ yyyy-MM-dd ของ **วันจันทร์** ในสัปดาห์นั้น
class WeeklyOffCalendarStore {
  WeeklyOffCalendarStore();

  static const _prefsKey = 'calendar_weekly_off_by_monday_v1';

  /// ปกติหยุดวันพุธ (ตาม Dart: จันทร์=1 … พุธ=3)
  static const int defaultOffWeekday = DateTime.wednesday;

  static String mondayKeyOf(DateTime d) {
    final local = DateTime(d.year, d.month, d.day);
    final monday = local.subtract(Duration(days: local.weekday - 1));
    final y = monday.year;
    final m = monday.month.toString().padLeft(2, '0');
    final day = monday.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<Map<String, int>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, int>{};
      decoded.forEach((k, v) {
        final key = '$k'.trim();
        if (key.isEmpty) return;
        final wd = v is num ? v.toInt() : int.tryParse('$v');
        if (wd == null) return;
        out[key] = wd.clamp(1, 7);
      });
      return out;
    } catch (e, st) {
      debugPrint('WeeklyOffCalendarStore.load: $e\n$st');
      return {};
    }
  }

  /// ถ้าเลือกวันพุธจะถือว่าใช้ค่ามาตรฐาน (ลบการเลื่อนของสัปดาห์นั้น)
  Future<void> setWeekOffWeekday(DateTime anyDayInWeek, int weekday) async {
    final wd = weekday.clamp(1, 7);
    final mondayStr = mondayKeyOf(anyDayInWeek);
    final p = await SharedPreferences.getInstance();
    final map = await load();
    if (wd == defaultOffWeekday) {
      map.remove(mondayStr);
    } else {
      map[mondayStr] = wd;
    }
    await p.setString(_prefsKey, jsonEncode(map));
  }
}
