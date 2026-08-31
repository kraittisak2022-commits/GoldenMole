import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/admin_user.dart';
import '../models/saved_login_profile.dart';

/// อ่าน/เขียนสตริงลับ (รหัสผ่านโปรไฟล์) — แยกจาก SharedPreferences
abstract class SecureCredentialStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureCredentialStore implements SecureCredentialStore {
  FlutterSecureCredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _timeout = Duration(seconds: 4);

  @override
  Future<String?> read(String key) =>
      _storage.read(key: key).timeout(_timeout);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value).timeout(_timeout);

  @override
  Future<void> delete(String key) =>
      _storage.delete(key: key).timeout(_timeout);
}

class SessionService {
  SessionService({SecureCredentialStore? secureStore})
      : _secureStore = secureStore ?? FlutterSecureCredentialStore();

  static const _sessionKey = 'mobile_admin_session';
  static const _rememberSessionKey = 'mobile_login_remember_session';
  static const _lastUsernameKey = 'mobile_last_login_username';
  static const _profilesMetaKey = 'mobile_saved_login_profiles';

  /// คีย์เก่า (single password) — migrate ครั้งเดียวแล้วลบ
  static const _legacySavedPasswordKey = 'mobile_saved_login_password';

  static const maxSavedProfiles = 5;
  static const _passwordKeyPrefix = 'mobile_saved_pwd_';

  final SecureCredentialStore _secureStore;

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

  /// ลบเฉพาะ session — คงโปรไฟล์ที่บันทึกไว้
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  /// ค่าเริ่มต้น true — ให้จดจำ session / โปรไฟล์ลงเครื่อง
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

  Future<List<SavedLoginProfile>> getSavedProfiles() async {
    await _migrateLegacySinglePasswordIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesMetaKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final profiles = <SavedLoginProfile>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final p = SavedLoginProfile.fromJson(item);
          if (p.id.isNotEmpty && p.username.isNotEmpty) {
            profiles.add(p);
          }
        } else if (item is Map) {
          final p = SavedLoginProfile.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (p.id.isNotEmpty && p.username.isNotEmpty) {
            profiles.add(p);
          }
        }
      }
      profiles.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
      return profiles;
    } catch (_) {
      return [];
    }
  }

  /// บันทึก/อัปเดตโปรไฟล์หลังล็อกอินสำเร็จ (รหัสผ่านใน secure storage)
  Future<void> saveLoginProfile({
    required AdminUser admin,
    required String password,
  }) async {
    final id = admin.id.trim().isNotEmpty
        ? admin.id.trim()
        : 'user_${admin.username.trim().toLowerCase()}';
    final username = admin.username.trim();
    if (username.isEmpty || password.isEmpty) return;

    final displayName = admin.displayName.trim().isEmpty
        ? username
        : admin.displayName.trim();

    try {
      await _secureStore.write(_passwordStorageKey(id), password);
    } catch (_) {
      // Secure storage can hang/fail on some devices — still save profile meta.
    }

    var profiles = await getSavedProfiles();
    profiles = profiles.where((p) => p.id != id).toList();
    profiles.insert(
      0,
      SavedLoginProfile(
        id: id,
        username: username,
        displayName: displayName,
        lastUsedAt: DateTime.now(),
      ),
    );

    while (profiles.length > maxSavedProfiles) {
      final oldest = profiles.removeLast();
      await _deleteProfilePassword(oldest.id);
    }

    await _persistProfilesMeta(profiles);
    await setLastLoginUsername(username);
  }

  Future<String?> getProfilePassword(String profileId) async {
    try {
      final s = await _secureStore.read(_passwordStorageKey(profileId));
      if (s == null || s.isEmpty) return null;
      return s;
    } catch (_) {
      return null;
    }
  }

  Future<void> removeSavedProfile(String profileId) async {
    await _deleteProfilePassword(profileId);
    final profiles =
        (await getSavedProfiles()).where((p) => p.id != profileId).toList();
    await _persistProfilesMeta(profiles);
  }

  Future<void> touchSavedProfile(String profileId) async {
    final profiles = await getSavedProfiles();
    final index = profiles.indexWhere((p) => p.id == profileId);
    if (index < 0) return;
    final updated = List<SavedLoginProfile>.from(profiles);
    updated[index] = updated[index].copyWith(lastUsedAt: DateTime.now());
    updated.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    await _persistProfilesMeta(updated);
  }

  String _passwordStorageKey(String profileId) =>
      '$_passwordKeyPrefix$profileId';

  Future<void> _deleteProfilePassword(String profileId) async {
    try {
      await _secureStore.delete(_passwordStorageKey(profileId));
    } catch (_) {
      // ไม่บล็อก flow หลัก
    }
  }

  Future<void> _persistProfilesMeta(List<SavedLoginProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    if (profiles.isEmpty) {
      await prefs.remove(_profilesMetaKey);
      return;
    }
    await prefs.setString(
      _profilesMetaKey,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  /// ย้ายรหัสผ่านเดี่ยวจาก WIP เดิม → โปรไฟล์แรก
  Future<void> _migrateLegacySinglePasswordIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final existingMeta = prefs.getString(_profilesMetaKey);
    if (existingMeta != null && existingMeta.isNotEmpty) {
      try {
        await _secureStore.delete(_legacySavedPasswordKey);
      } catch (_) {}
      return;
    }

    String? legacyPassword;
    try {
      legacyPassword = await _secureStore.read(_legacySavedPasswordKey);
    } catch (_) {
      return;
    }
    if (legacyPassword == null || legacyPassword.isEmpty) return;

    final username = await getLastLoginUsername();
    if (username == null || username.isEmpty) {
      try {
        await _secureStore.delete(_legacySavedPasswordKey);
      } catch (_) {}
      return;
    }

    final id = 'user_${username.toLowerCase()}';
    await _secureStore.write(_passwordStorageKey(id), legacyPassword);
    await _persistProfilesMeta([
      SavedLoginProfile(
        id: id,
        username: username,
        displayName: username,
        lastUsedAt: DateTime.now(),
      ),
    ]);
    try {
      await _secureStore.delete(_legacySavedPasswordKey);
    } catch (_) {}
  }
}
