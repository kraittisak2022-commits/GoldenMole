import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/admin_user.dart';

class SessionService {
  static const _sessionKey = 'mobile_admin_session';

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
}
