import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user.dart';

class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  static const Duration _loginQueryTimeout = Duration(seconds: 15);
  static const Duration _lastLoginUpdateTimeout = Duration(seconds: 8);

  String _normalizeUsername(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _looksLikeSha256Hex(String value) {
    return RegExp(r'^[a-f0-9]{64}$', caseSensitive: false).hasMatch(value.trim());
  }

  String? _extractSha256Hex(String value) {
    final trimmed = value.trim();
    if (_looksLikeSha256Hex(trimmed)) return trimmed;
    final match = RegExp(r'([a-f0-9]{64})', caseSensitive: false).firstMatch(trimmed);
    return match?.group(1);
  }

  String _sha256Hex(String plain) {
    final digest = sha256.convert(utf8.encode(plain));
    return digest.toString();
  }

  bool _isHashedPassword(String stored) {
    final s = stored.trim();
    return s.startsWith('sha256\$') || s.startsWith('sha256:') || _extractSha256Hex(s) != null;
  }

  bool _verifyPassword(String stored, String inputPlain) {
    final s = stored.trim();
    if (_isHashedPassword(s)) {
      final expectedRaw = s.startsWith('sha256\$')
          ? s.substring('sha256\$'.length)
          : s.startsWith('sha256:')
              ? s.substring('sha256:'.length)
              : ( _extractSha256Hex(s) ?? s );
      final expectedHex = (_extractSha256Hex(expectedRaw) ?? expectedRaw).toLowerCase();

      final actual = _sha256Hex(inputPlain).toLowerCase();
      if (expectedHex == actual) return true;

      final trimmedInput = inputPlain.trim();
      if (trimmedInput != inputPlain) {
        final trimmedActual = _sha256Hex(trimmedInput).toLowerCase();
        return expectedHex == trimmedActual;
      }
      return false;
    }

    return s == inputPlain || s == inputPlain.trim();
  }

  Future<AdminUser> login(String username, String password) async {
    final normalizedInput = _normalizeUsername(username);
    late final List<Map<String, dynamic>> rows;
    try {
      final result = await _client
          .from('admin_users')
          .select()
          .timeout(_loginQueryTimeout);
      rows = List<Map<String, dynamic>>.from(result as List);
    } on TimeoutException {
      throw const AdminLoginException(
        'หมดเวลารอเซิร์ฟเวอร์ — ตรวจสอบการเชื่อมต่อแล้วลองอีกครั้ง',
      );
    }
    final admins = rows.map(AdminUser.fromMap).toList();

    AdminUser? matchedUser;
    for (final admin in admins) {
      if (_normalizeUsername(admin.username) == normalizedInput) {
        matchedUser = admin;
        break;
      }
    }

    if (matchedUser == null) {
      throw const AdminLoginException('ไม่พบ user จริง');
    }

    final ok = _verifyPassword(matchedUser.password, password);
    if (!ok) {
      throw const AdminLoginException('รหัสไม่ตรง');
    }

    // Best-effort; never block entering the app on last_login write.
    final matchedId = matchedUser.id;
    unawaited(() async {
      try {
        await _client
            .from('admin_users')
            .update({
              'last_login': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', matchedId)
            .timeout(_lastLoginUpdateTimeout);
      } catch (_) {}
    }());

    return matchedUser;
  }
}

/// ข้อผิดพลาดจากการตรวจ user/รหัส (ไม่ใช่คลาส AuthException ของ Supabase GoTrue)
class AdminLoginException implements Exception {
  const AdminLoginException(this.message);

  final String message;

  @override
  String toString() => message;
}
