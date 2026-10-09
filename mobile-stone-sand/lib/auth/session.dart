import 'dart:convert';

import '../data/db.dart';
import '../models/models.dart';

class StoneSandSession {
  const StoneSandSession({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    this.orderSource,
    required this.loginAt,
    this.remember = false,
  });

  final String id;
  final String username;
  final String displayName;

  /// 'SuperAdmin' | 'Admin' | 'Assistant'
  final String role;

  /// Only this order source is visible; null = both.
  final OrderSource? orderSource;
  final String loginAt;

  /// Whether the user chose "จดจำการเข้าสู่ระบบ" (30-day sliding TTL).
  /// Defaults to false for backward compat when absent from stored JSON.
  final bool remember;

  /// Name written into status logs and documents.
  String get by => displayName.isNotEmpty ? displayName : username;

  StoneSandSession copyWith({
    String? role,
    OrderSource? orderSource,
    bool clearSource = false,
    String? loginAt,
    bool? remember,
  }) => StoneSandSession(
    id: id,
    username: username,
    displayName: displayName,
    role: role ?? this.role,
    orderSource: clearSource ? null : (orderSource ?? this.orderSource),
    loginAt: loginAt ?? this.loginAt,
    remember: remember ?? this.remember,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'displayName': displayName,
    'role': role,
    'orderSource': orderSource?.name,
    'loginAt': loginAt,
    'remember': remember,
  };

  factory StoneSandSession.fromJson(Map<String, dynamic> j) => StoneSandSession(
    id: '${j['id'] ?? ''}',
    username: '${j['username'] ?? ''}',
    displayName: '${j['displayName'] ?? ''}',
    role: '${j['role'] ?? ''}',
    orderSource: OrderSource.tryParse(j['orderSource']),
    loginAt: '${j['loginAt'] ?? ''}',
    remember: j['remember'] as bool? ?? false,
  );
}

const _sessionKey = 'stone_sand_session_v1';
const _lastUsernameKey = 'stone_sand_last_username';

/// 12 hours for non-remembered sessions.
const _shortTtl = Duration(hours: 12);

/// 30 days for remembered sessions (sliding — refreshed on each successful recheck).
const _longTtl = Duration(days: 30);

Duration _ttlFor(StoneSandSession s) => s.remember ? _longTtl : _shortTtl;

void saveSession(StoneSandSession session) {
  try {
    Prefs.instance.setString(_sessionKey, jsonEncode(session.toJson()));
  } catch (_) {}
}

void clearSession() {
  try {
    Prefs.instance.remove(_sessionKey);
  } catch (_) {}
}

StoneSandSession? readSession({DateTime? now}) {
  try {
    final raw = Prefs.instance.getString(_sessionKey);
    if (raw == null) return null;
    final s = StoneSandSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    if (s.id.isEmpty || s.username.isEmpty || s.role.isEmpty || s.loginAt.isEmpty) return null;
    final loginAt = DateTime.tryParse(s.loginAt);
    if (loginAt == null || (now ?? DateTime.now()).difference(loginAt) > _ttlFor(s)) {
      clearSession();
      return null;
    }
    return s;
  } catch (_) {
    return null;
  }
}

/// Slides the TTL for a remembered session by writing a fresh loginAt.
/// Call this after a successful recheck so active users never get logged out.
StoneSandSession slideSession(StoneSandSession session) {
  if (!session.remember) return session;
  final next = session.copyWith(loginAt: DateTime.now().toUtc().toIso8601String());
  saveSession(next);
  return next;
}

// ─── Last username helpers ────────────────────────────────────────────────────

void saveLastUsername(String username) {
  try {
    if (username.isNotEmpty) {
      Prefs.instance.setString(_lastUsernameKey, username);
    }
  } catch (_) {}
}

String? readLastUsername() {
  try {
    final v = Prefs.instance.getString(_lastUsernameKey);
    return (v != null && v.isNotEmpty) ? v : null;
  } catch (_) {
    return null;
  }
}
