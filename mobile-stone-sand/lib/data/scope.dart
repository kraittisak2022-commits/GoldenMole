import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

/// The order source the signed-in account is limited to (admin_users.order_source), or null for both.
/// UI-level only: the database (RLS allow-all) does not enforce it.
OrderSource? _locked;

void setLockedSource(OrderSource? source) => _locked = source;

OrderSource? lockedSource() => _locked;

bool canSeeSource(OrderSource source) => _locked == null || source == _locked;

/// Hides rows made by the retired guided tour; older app versions can still create them.
PostgrestFilterBuilder<T> hideDemo<T>(PostgrestFilterBuilder<T> q) => q.isFilter('demo_session', null);

/// Adds `source = locked` when the account is limited, and hides guided-tour demo rows.
PostgrestFilterBuilder<T> scoped<T>(PostgrestFilterBuilder<T> q) {
  final locked = _locked;
  return hideDemo(locked != null ? q.eq('source', locked.name) : q);
}
