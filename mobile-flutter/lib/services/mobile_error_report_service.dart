import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user.dart';

/// บันทึกรายงานข้อผิดพลาดจากแอป Android ลง Supabase (`mobile_error_reports`)
class MobileErrorReportService {
  MobileErrorReportService(this._client);

  final SupabaseClient _client;

  static const _table = 'mobile_error_reports';
  static const _maxSummary = 220;
  static const _maxDetail = 12000;

  Future<String> _deviceLine() async {
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        return '${a.manufacturer} ${a.model} · Android ${a.version.release} (SDK ${a.version.sdkInt})';
      }
      if (Platform.isIOS) {
        final i = await DeviceInfoPlugin().iosInfo;
        return '${i.model} · ${i.systemName} ${i.systemVersion}';
      }
    } catch (_) {}
    return Platform.operatingSystem;
  }

  Future<String> _appVersionLine() async {
    try {
      final p = await PackageInfo.fromPlatform();
      return '${p.version}+${p.buildNumber}';
    } catch (_) {
      return 'unknown';
    }
  }

  String _clip(String? s, int max) {
    if (s == null) return '';
    final t = s.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max)}\n…(ตัดข้อความ)';
  }

  /// ส่งรายงานขึ้นเซิร์ฟเวอร์ — คืน `id` ที่บันทึก
  Future<String> submit({
    required Object error,
    StackTrace? stackTrace,
    required String source,
    String userNote = '',
    AdminUser? reporter,
  }) async {
    final id = 'mer_${DateTime.now().millisecondsSinceEpoch}';
    final summary = _clip(error.toString(), _maxSummary);
    final stackStr = stackTrace?.toString() ?? '';
    final combined = '$summary\n\n$stackStr'.trim();
    final detail = _clip(combined, _maxDetail);
    final note = userNote.trim().isEmpty ? null : _clip(userNote, 2000);

    final row = <String, dynamic>{
      'id': id,
      'platform': 'android',
      'reported_by_username': reporter?.username,
      'reported_by_name': reporter?.displayName,
      'app_version': await _appVersionLine(),
      'device_info': await _deviceLine(),
      'error_summary': summary,
      'error_detail': detail,
      'user_note': note,
      'source': source,
      'reviewed': false,
    };

    await _client.from(_table).insert(row);
    return id;
  }

  Future<List<Map<String, dynamic>>> listRecent({int limit = 80}) async {
    final rows = await _client
        .from(_table)
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    final list = rows as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
