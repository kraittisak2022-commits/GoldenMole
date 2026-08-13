import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ข้อมูลหยุดรายสัปดาห์ (วันในสัปดาห์ + เหตุผลเมื่อเลื่อนจากวันพฤหัสบดี)
class WeeklyOffCalendarData {
  const WeeklyOffCalendarData({
    required this.weekdayByMonday,
    required this.moveReasonByMonday,
  });

  final Map<String, int> weekdayByMonday;
  final Map<String, String> moveReasonByMonday;
}

/// เก็บว่าวันไหนในสัปดาห์เป็นวันหยุดประจำ (ค่าเริ่มต้นวันพฤหัสบดี) โดยคีย์คือ yyyy-MM-dd ของ **วันจันทร์** ในสัปดาห์นั้น
///
/// เก็บใน SharedPreferences และ **ซิงก์ไป Supabase** (`app_settings.app_defaults`)
/// — `weeklyOffByMonday` (วัน) และ `weeklyOffMoveReasonByMonday` (เหตุผลเมื่อเลื่อนหยุด)
class WeeklyOffCalendarStore {
  WeeklyOffCalendarStore();

  static const _prefsKey = 'calendar_weekly_off_by_monday_v1';
  static const _prefsReasonKey = 'calendar_weekly_off_reason_by_monday_v1';
  static const _prefsAtKey = 'calendar_weekly_off_cached_ms';
  static const _remoteKey = 'weeklyOffByMonday';
  static const _remoteReasonKey = 'weeklyOffMoveReasonByMonday';
  static const _remoteTtl = Duration(minutes: 30);

  /// ปกติหยุดวันพฤหัสบดี (ตาม Dart: จันทร์=1 … พฤหัสบดี=4)
  static const int defaultOffWeekday = DateTime.thursday;

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

  Map<String, String> _parseReasonMap(Map<dynamic, dynamic> raw) {
    final out = <String, String>{};
    raw.forEach((k, v) {
      final key = '$k'.trim();
      final reason = '$v'.trim();
      if (key.isEmpty || reason.isEmpty) return;
      out[key] = reason;
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

  Future<Map<String, String>> _readPrefsReasonMap(SharedPreferences p) async {
    await p.reload();
    final raw = p.getString(_prefsReasonKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return _parseReasonMap(Map<dynamic, dynamic>.from(decoded));
    } catch (e, st) {
      debugPrint('WeeklyOffCalendarStore._readPrefsReasonMap: $e\n$st');
      return {};
    }
  }

  Future<void> _writePrefsMap(Map<String, int> map) async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    await p.setString(_prefsKey, jsonEncode(map));
  }

  Future<void> _writePrefsReasonMap(Map<String, String> map) async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    await p.setString(_prefsReasonKey, jsonEncode(map));
  }

  Future<({Map<String, int> weekday, Map<String, String> reason})>
      _readRemoteMaps(SupabaseClient client) async {
    try {
      final row = await client
          .from('app_settings')
          .select('app_defaults')
          .eq('id', 'default')
          .maybeSingle();
      if (row == null) {
        return (weekday: <String, int>{}, reason: <String, String>{});
      }
      final ad = row['app_defaults'];
      if (ad is! Map) {
        return (weekday: <String, int>{}, reason: <String, String>{});
      }
      final w = ad[_remoteKey];
      final r = ad[_remoteReasonKey];
      return (
        weekday: w is Map
            ? _parseWeeklyMap(Map<dynamic, dynamic>.from(w))
            : <String, int>{},
        reason: r is Map
            ? _parseReasonMap(Map<dynamic, dynamic>.from(r))
            : <String, String>{},
      );
    } catch (e, st) {
      debugPrint('WeeklyOffCalendarStore._readRemoteMaps: $e\n$st');
      return (weekday: <String, int>{}, reason: <String, String>{});
    }
  }

  Future<void> _writeRemoteMaps(
    SupabaseClient client,
    Map<String, int> weeklyMap,
    Map<String, String> reasonMap,
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
      defaults[_remoteReasonKey] = Map<String, String>.from(reasonMap);
      await client.from('app_settings').update({
        'app_defaults': defaults,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', 'default');
    } catch (e, st) {
      debugPrint('WeeklyOffCalendarStore._writeRemoteMaps: $e\n$st');
    }
  }

  /// โหลดจากเครื่อง + (ถ้ามี client) ผสานกับ Supabase — ค่าบนเซิร์ฟเวอร์ชนะเมื่อคีย์ซ้ำ
  Future<WeeklyOffCalendarData> load({SupabaseClient? client}) async {
    final p = await SharedPreferences.getInstance();
    final localWd = await _readPrefsMap(p);
    final localReason = await _readPrefsReasonMap(p);

    if (client == null) {
      return WeeklyOffCalendarData(
        weekdayByMonday: localWd,
        moveReasonByMonday: localReason,
      );
    }

    final cachedAt = p.getInt(_prefsAtKey);
    final ttlFresh = cachedAt != null &&
        DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(cachedAt),
            ) <=
            _remoteTtl;
    if (ttlFresh) {
      return WeeklyOffCalendarData(
        weekdayByMonday: localWd,
        moveReasonByMonday: localReason,
      );
    }

    try {
      final remote = await _readRemoteMaps(client);
      final remoteWd = remote.weekday;
      final remoteReason = remote.reason;
      if (remoteWd.isEmpty && remoteReason.isEmpty) {
        if (localWd.isNotEmpty || localReason.isNotEmpty) {
          try {
            await _writeRemoteMaps(client, localWd, localReason);
          } catch (_) {}
        }
        await p.setInt(_prefsAtKey, DateTime.now().millisecondsSinceEpoch);
        return WeeklyOffCalendarData(
          weekdayByMonday: localWd,
          moveReasonByMonday: localReason,
        );
      }
      final mergedWd = <String, int>{...localWd, ...remoteWd};
      final mergedReason = <String, String>{...localReason, ...remoteReason};
      for (final k in mergedWd.keys.toList()) {
        if (mergedWd[k] == defaultOffWeekday) {
          mergedReason.remove(k);
        }
      }
      for (final k in mergedReason.keys.toList()) {
        if (!mergedWd.containsKey(k)) mergedReason.remove(k);
      }
      if (jsonEncode(mergedWd) != jsonEncode(localWd) ||
          jsonEncode(mergedReason) != jsonEncode(localReason)) {
        await p.setString(_prefsKey, jsonEncode(mergedWd));
        await p.setString(_prefsReasonKey, jsonEncode(mergedReason));
      }
      await p.setInt(_prefsAtKey, DateTime.now().millisecondsSinceEpoch);
      return WeeklyOffCalendarData(
        weekdayByMonday: mergedWd,
        moveReasonByMonday: mergedReason,
      );
    } catch (e, st) {
      debugPrint('WeeklyOffCalendarStore.load remote: $e\n$st');
      return WeeklyOffCalendarData(
        weekdayByMonday: localWd,
        moveReasonByMonday: localReason,
      );
    }
  }

  /// ถ้าเลือกวันพฤหัสบดีจะถือว่าใช้ค่ามาตรฐาน (ลบการเลื่อนของสัปดาห์นั้น)
  /// ถ้าเลื่อนจากวันพฤหัสบดี — ต้องระบุ [moveReason] (ไม่ว่าง)
  Future<void> setWeekOffWeekday(
    DateTime anyDayInWeek,
    int weekday, {
    String? moveReason,
    SupabaseClient? client,
  }) async {
    final wd = weekday.clamp(1, 7);
    final mondayStr = mondayKeyOf(anyDayInWeek);
    final p = await SharedPreferences.getInstance();
    final map = await _readPrefsMap(p);
    final reasonMap = await _readPrefsReasonMap(p);
    if (wd == defaultOffWeekday) {
      map.remove(mondayStr);
      reasonMap.remove(mondayStr);
    } else {
      final reason = moveReason?.trim() ?? '';
      if (reason.isEmpty) {
        throw ArgumentError('กรุณาระบุเหตุผลการย้ายวันหยุด');
      }
      map[mondayStr] = wd;
      reasonMap[mondayStr] = reason;
    }
    await _writePrefsMap(map);
    await _writePrefsReasonMap(reasonMap);
    await p.setInt(_prefsAtKey, DateTime.now().millisecondsSinceEpoch);
    if (client != null) {
      await _writeRemoteMaps(client, map, reasonMap);
    }
  }
}
