import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get db => Supabase.instance.client;

/// A user-facing failure; [message] is shown as-is.
class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}

const _foreignKeyViolation = '23503';

/// Rethrows Supabase errors as [AppException]; [inUse] replaces the message when other rows
/// still reference the deleted one.
Never rethrowDb(Object e, [String? inUse]) {
  if (e is AppException) throw e;
  if (e is PostgrestException) {
    throw AppException(inUse != null && e.code == _foreignKeyViolation ? inUse : e.message);
  }
  throw AppException(e.toString());
}

/// Runs a query and turns any database error into an [AppException].
Future<T> guard<T>(Future<T> Function() run, [String? inUse]) async {
  try {
    return await run();
  } catch (e) {
    rethrowDb(e, inUse);
  }
}

String errorText(Object e, [String fallback = 'เกิดข้อผิดพลาด']) {
  if (e is AppException) return e.message;
  if (e is PostgrestException) return e.message;
  if (e is StateError) return e.message;
  final s = e.toString();
  return s.isEmpty ? fallback : s;
}

/// SharedPreferences loaded once at startup so session reads stay synchronous.
abstract final class Prefs {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static SharedPreferences get instance {
    final p = _prefs;
    if (p == null) throw StateError('Prefs.init() not called');
    return p;
  }

  @visibleForTesting
  static void setForTest(SharedPreferences p) => _prefs = p;
}

/// Bumped after any write so open screens can reload their lists.
final dataVersion = ValueNotifier<int>(0);

void notifyDataChanged() => dataVersion.value++;
