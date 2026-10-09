import 'db.dart';

/// Removes every order, statement and customer created in a guided-tour session.
Future<void> deleteDemoSession(String session) async {
  await guard(() => db.rpc('ss_delete_demo', params: {'p_session': session}));
  notifyDataChanged();
}

/// Cleans up tours that were abandoned more than a day ago.
Future<void> deleteStaleDemoSessions() => guard(() => db.rpc('ss_delete_stale_demo'));
