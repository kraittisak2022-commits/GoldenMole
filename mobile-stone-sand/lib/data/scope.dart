import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'db.dart';

/// The order source the signed-in account is limited to (admin_users.order_source), or null for both.
/// UI-level only: the database (RLS allow-all) does not enforce it.
OrderSource? _locked;

void setLockedSource(OrderSource? source) => _locked = source;

OrderSource? lockedSource() => _locked;

bool canSeeSource(OrderSource source) => _locked == null || source == _locked;

/// The guided-tour demo session. Rows created while it is set carry demo_session = this id:
/// the database gives them DEMO- document numbers and only this device lists them.
const demoSessionKey = 'stone_sand_demo_session_v1';

String? _session;
bool _sessionLoaded = false;

String? demoSession() {
  if (!_sessionLoaded) {
    _sessionLoaded = true;
    try {
      final v = Prefs.instance.getString(demoSessionKey);
      _session = v != null && v.startsWith('demo-') ? v : null;
    } catch (_) {
      _session = null;
    }
  }
  return _session;
}

String startDemoSession() {
  final rnd = Random();
  final suffix = List.generate(6, (_) => rnd.nextInt(36).toRadixString(36)).join();
  _session = 'demo-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$suffix';
  _sessionLoaded = true;
  try {
    Prefs.instance.setString(demoSessionKey, _session!);
  } catch (_) {}
  return _session!;
}

void endDemoSession() {
  _session = null;
  _sessionLoaded = true;
  try {
    Prefs.instance.remove(demoSessionKey);
  } catch (_) {}
}

/// Real rows always; demo rows only for the current session.
PostgrestFilterBuilder<T> demoFilter<T>(PostgrestFilterBuilder<T> q) {
  final s = demoSession();
  return s != null ? q.or('demo_session.is.null,demo_session.eq.$s') : q.isFilter('demo_session', null);
}

bool isVisibleDemo(Object? demoSessionValue) =>
    demoSessionValue == null || demoSessionValue == '' || demoSessionValue == demoSession();

/// Adds `source = locked` when the account is limited, and hides demo rows of other tour sessions.
PostgrestFilterBuilder<T> scoped<T>(PostgrestFilterBuilder<T> q) {
  final locked = _locked;
  return demoFilter(locked != null ? q.eq('source', locked.name) : q);
}
