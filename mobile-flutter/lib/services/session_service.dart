import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/admin_user.dart';

class SessionService {
  static const _sessionKey = 'mobile_admin_session';
  static const _rememberSessionKey = 'mobile_login_remember_session';
  static const _lastUsernameKey = 'mobile_last_login_username';

  Future<void> saveAdmin(AdminUser admin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(admin.toSessionMap()));
  }

  Future<AdminUser?> getSavedAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return AdminUser.fromSessionMap(decoded);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  /// ค่าเริ่มต้น true — ให้จดจำ session ลงเครื่องเหมือนเดิม
  Future<bool> getRememberSessionPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberSessionKey) ?? true;
  }

  Future<void> setRememberSessionPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberSessionKey, value);
  }

  Future<String?> getLastLoginUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_lastUsernameKey);
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> setLastLoginUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final t = username.trim();
    if (t.isEmpty) {
      await prefs.remove(_lastUsernameKey);
    } else {
      await prefs.setString(_lastUsernameKey, t);
    }
  }
}
