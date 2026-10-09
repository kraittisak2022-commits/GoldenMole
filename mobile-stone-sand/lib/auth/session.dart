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
  });

  final String id;
  final String username;
  final String displayName;

  /// 'SuperAdmin' | 'Admin' | 'Assistant'
  final String role;

  /// Only this order source is visible; null = both.
  final OrderSource? orderSource;
  final String loginAt;

  /// Name written into status logs and documents.
  String get by => displayName.isNotEmpty ? displayName : username;

  StoneSandSession copyWith({String? role, OrderSource? orderSource, bool clearSource = false}) =>
      StoneSandSession(
        id: id,
        username: username,
        displayName: displayName,
        role: role ?? this.role,
        orderSource: clearSource ? null : (orderSource ?? this.orderSource),
        loginAt: loginAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
        'role': role,
        'orderSource': orderSource?.name,
        'loginAt': loginAt,
      };

  factory StoneSandSession.fromJson(Map<String, dynamic> j) => StoneSandSession(
        id: '${j['id'] ?? ''}',
        username: '${j['username'] ?? ''}',
        displayName: '${j['displayName'] ?? ''}',
        role: '${j['role'] ?? ''}',
        orderSource: OrderSource.tryParse(j['orderSource']),
        loginAt: '${j['loginAt'] ?? ''}',
      );
}

const _sessionKey = 'stone_sand_session_v1';

/// 12 hours
const sessionTtl = Duration(hours: 12);

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
    if (loginAt == null || (now ?? DateTime.now()).difference(loginAt) > sessionTtl) {
      clearSession();
      return null;
    }
    return s;
  } catch (_) {
    return null;
  }
}
