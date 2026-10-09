import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/db.dart';
import '../models/models.dart';
import 'password_auth.dart';
import 'session.dart';

class SignInError implements Exception {
  const SignInError(this.code, this.message);

  /// empty_fields | user_not_found | bad_password | forbidden_role | network | missing_config
  final String code;
  final String message;

  @override
  String toString() => message;
}

const _roleDefaults = {
  'main': ['SuperAdmin', 'Admin', 'Assistant'],
  'order': ['SuperAdmin', 'Admin'],
  'flowaccount': ['SuperAdmin'],
};

/// Copy of the main app's siteAccess rule — keep in sync.
bool canAccessSite(String role, Object? allowedApps, String site) {
  if (allowedApps is List) return allowedApps.contains(site);
  return (_roleDefaults[site] ?? const []).contains(role);
}

String normalizeUsername(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

Future<StoneSandSession> signInWithAdminUsers(String username, String password) async {
  final u = username.trim();
  if (u.isEmpty || password.isEmpty) {
    throw const SignInError('empty_fields', 'กรุณากรอกชื่อผู้ใช้และรหัสผ่าน');
  }
  final normalized = normalizeUsername(u);
  Map<String, dynamic>? row;
  try {
    row = await db
        .from('admin_users')
        .select('id, username, password, display_name, role, allowed_apps, order_source')
        .ilike('username', normalized)
        .maybeSingle();
  } on PostgrestException catch (e) {
    throw SignInError('network', 'เชื่อมต่อฐานข้อมูลไม่ได้ (${e.message})');
  } catch (_) {
    throw const SignInError('network', 'เชื่อมต่อฐานข้อมูลไม่ได้ ตรวจสอบอินเทอร์เน็ต');
  }
  if (row == null || normalizeUsername('${row['username']}') != normalized) {
    throw const SignInError('user_not_found', 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
  }
  if (!verifyStoredPassword('${row['password'] ?? ''}', password)) {
    throw const SignInError('bad_password', 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
  }
  final role = '${row['role'] ?? ''}';
  if (!canAccessSite(role, row['allowed_apps'], 'order')) {
    throw const SignInError('forbidden_role', 'บัญชีนี้ไม่มีสิทธิ์เข้าใช้ระบบออเดอร์');
  }
  return StoneSandSession(
    id: '${row['id']}',
    username: '${row['username']}',
    displayName: '${row['display_name'] ?? ''}',
    role: role,
    orderSource: OrderSource.tryParse(row['order_source']),
    loginAt: DateTime.now().toUtc().toIso8601String(),
  );
}

class SessionCheck {
  const SessionCheck({required this.allowed, this.role, this.orderSource});
  final bool allowed;
  final String? role;
  final OrderSource? orderSource;
}

/// `allowed` is false only when the account is gone or lost access; a failed request keeps the
/// session (access unknown).
Future<SessionCheck> checkSession(String id) async {
  try {
    final row = await db
        .from('admin_users')
        .select('role, allowed_apps, order_source')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return const SessionCheck(allowed: false);
    final role = '${row['role'] ?? ''}';
    return SessionCheck(
      allowed: canAccessSite(role, row['allowed_apps'], 'order'),
      role: role,
      orderSource: OrderSource.tryParse(row['order_source']),
    );
  } catch (_) {
    return const SessionCheck(allowed: true);
  }
}
