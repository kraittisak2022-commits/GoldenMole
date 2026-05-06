import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_transaction.dart';

class TransactionService {
  TransactionService(this._client);

  final SupabaseClient _client;

  Future<List<AppTransaction>> fetchTransactions() async {
    final rows = await _client.from('transactions').select().order('created_at', ascending: false);
    return rows.map(AppTransaction.fromMap).toList();
  }

  Future<List<AppTransaction>> fetchRecentTransactions({int limit = 10}) async {
    final rows = await _client
        .from('transactions')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(AppTransaction.fromMap).toList();
  }

  Future<void> upsertTransaction(AppTransaction item) async {
    await _client.from('transactions').upsert(item.toInsertMap(), onConflict: 'id');
  }

  Future<void> deleteTransaction(String id) async {
    await _client.from('transactions').delete().eq('id', id);
  }
}
