import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/count_record_work_mode.dart';

/// เก็บโหมดงาน «บันทึกและนับจำนวน» ต่อวัน (yyyy-MM-dd → trip|sand|both)
class CountRecordWorkModeStore {
  CountRecordWorkModeStore._();

  static const _prefsKey = 'count_record_work_mode_by_day_v1';

  static Future<Map<String, String>> _readMap() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, String>{};
      decoded.forEach((k, v) {
        final key = '$k'.trim();
        final val = '$v'.trim();
        if (key.isEmpty || val.isEmpty) return;
        out[key] = val;
      });
      return out;
    } catch (e, st) {
      debugPrint('CountRecordWorkModeStore._readMap: $e\n$st');
      return {};
    }
  }

  static Future<void> _writeMap(Map<String, String> map) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, jsonEncode(map));
  }

  static Future<CountRecordWorkMode?> load(String dayKey) async {
    final key = dayKey.trim();
    if (key.isEmpty) return null;
    final map = await _readMap();
    return CountRecordWorkModeCodec.tryParse(map[key]);
  }

  static Future<void> save(String dayKey, CountRecordWorkMode mode) async {
    final key = dayKey.trim();
    if (key.isEmpty) return;
    final map = await _readMap();
    map[key] = mode.storageValue;
    await _writeMap(map);
  }
}
