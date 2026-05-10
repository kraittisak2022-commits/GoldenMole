import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// เก็บว่าวันไหนในสัปดาห์เป็นวันหยุดประจำ (ค่าเริ่มต้นวันพุธ) โดยคีย์คือ yyyy-MM-dd ของ **วันจันทร์** ในสัปดาห์นั้น
///
/// เก็บใน SharedPreferences และ **ซิงก์ไป Supabase** (`app_settings.app_defaults.weeklyOffByMonday`)
/// เพื่อให้รีเฟรช/อุปกรณ์อื่นยังเห็นค่าเดิม
class WeeklyOffCalendarStore {
  WeeklyOffCalendarStore();

  static const _prefsKey = 'calendar_weekly_off_by_monday_v1';
  static const _remoteKey = 'weeklyOffByMonday';

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

  Map<String, int> _parseWeeklyMap(Map<dynamic, dynamic> raw) {
    final out = <String, int>{};
    raw.forEach((k, v) {
      final key = '$k'.trim();
      if (key.isEmpty) return;
      final wd = v is num ? v.toInt() : int.tryParse('$v');
      if (wd == null) return;
      out[key] = wd.clamp(1, 7);
    });
    return out;
  }

  Future<Map<String, int>> _readPrefsMap(SharedPreferences p) async {
    await p.reload();
    final raw = p.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return _parseWeeklyMap(Map<dynamic, dynamic>.from(decoded));
    } catch (e, st) {
      debugPrint('WeeklyOffCalendarStore._readPrefsMap: $e\n$st');
      return {};
    }
  }

  Future<void> _writePrefsMap(Map<String, int> map) async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    await p.setString(_prefsKey, jsonEncode(map));
  }

  Future<Map<String, int>> _readRemoteMap(SupabaseClient client) async {
    try {
      final row = await client
          .from('app_settings')
          .select('app_defaults')
          .eq('id', 'default')
          .maybeSingle();
      if (row == null) return {};
      final ad = row['app_defaults'];
      if (ad is! Map) return {};
      final w = ad[_remoteKey];
      if (w is! Map) return {};
      return _parseWeeklyMap(Map<dynamic, dynamic>.from(w));
    } catch (e, st) {
      debugPrint('WeeklyOffCalendarStore._readRemoteMap: $e\n$st');
      return {};
    }
  }

  Future<void> _writeRemoteWeeklyMap(
    SupabaseClient client,
    Map<String, int> weeklyMap,
  ) async {
    try {
      final row = await client
          .from('app_settings')
          .select('app_defaults')
          .eq('id', 'default')
          .maybeSingle();
      final prev = row?['app_defaults'];
      final defaults = Map<String, dynamic>.from(
        prev is Map<String, dynamic>
            ? prev
            : prev is Map
                ? Map<String, dynamic>.from(prev)
                : <String, dynamic>{},
      );
      defaults[_remoteKey] = Map<String, int>.from(weeklyMap);
      await client.from('app_settings').update({
        'app_defaults': defaults,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', 'default');
    } catch (e, st) {
      debugPrint('WeeklyOffCalendarStore._writeRemoteWeeklyMap: $e\n$st');
    }
  }

  /// โหลดจากเครื่อง + (ถ้ามี client) ผสานกับ Supabase — ค่าบนเซิร์ฟเวอร์ชนะเมื่อคีย์ซ้ำ
  Future<Map<String, int>> load({SupabaseClient? client}) async {
    final p = await SharedPreferences.getInstance();
    final local = await _readPrefsMap(p);

    if (client == null) return local;

    try {
      final remote = await _readRemoteMap(client);
      if (remote.isEmpty) {
        if (local.isNotEmpty) {
          try {
            await _writeRemoteWeeklyMap(client, local);
          } catch (_) {}
        }
        return local;
      }
      final merged = <String, int>{...local, ...remote};
      if (jsonEncode(merged) != jsonEncode(local)) {
        await p.setString(_prefsKey, jsonEncode(merged));
      }
      return merged;
    } catch (e, st) {
      debugPrint('WeeklyOffCalendarStore.load remote: $e\n$st');
      return local;
    }
  }

  /// ถ้าเลือกวันพุธจะถือว่าใช้ค่ามาตรฐาน (ลบการเลื่อนของสัปดาห์นั้น)
  Future<void> setWeekOffWeekday(
    DateTime anyDayInWeek,
    int weekday, {
    SupabaseClient? client,
  }) async {
    final wd = weekday.clamp(1, 7);
    final mondayStr = mondayKeyOf(anyDayInWeek);
    final p = await SharedPreferences.getInstance();
    final map = await _readPrefsMap(p);
    if (wd == defaultOffWeekday) {
      map.remove(mondayStr);
    } else {
      map[mondayStr] = wd;
    }
    await _writePrefsMap(map);
    if (client != null) {
      await _writeRemoteWeeklyMap(client, map);
    }
  }
}
