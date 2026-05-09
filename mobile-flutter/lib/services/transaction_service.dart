import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_transaction.dart';
import 'local_data_cache.dart';

class TransactionService {
  TransactionService(this._client);

  final SupabaseClient _client;

  Future<void> _invalidateAfterMutation({required String? affectingDate}) async {
    await LocalDataCache.invalidateDashboard();
    if (affectingDate != null && affectingDate.isNotEmpty) {
      await LocalDataCache.invalidateTransactionsForDay(affectingDate);
    }
    await LocalDataCache.invalidateTransactionsFull();
  }

  Future<List<AppTransaction>> fetchTransactions({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached =
          await LocalDataCache.readTransactionsFull(LocalDataCache.transactionsFullTtl);
      if (cached != null) return cached;
    }

    final rows = await _client.from('transactions').select().order('created_at', ascending: false);
    final list = rows.map(AppTransaction.fromMap).toList();
    await LocalDataCache.writeTransactionsFull(list);
    return list;
  }

  Future<List<AppTransaction>> fetchRecentTransactions({int limit = 10}) async {
    final rows = await _client
        .from('transactions')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(AppTransaction.fromMap).toList();
  }

  Future<List<AppTransaction>> fetchTransactionsForDate(
    String ymd, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await LocalDataCache.readTransactionsForDay(
        ymd,
        LocalDataCache.transactionsByDayTtl,
      );
      if (cached != null) return cached;
    }

    final rows = await _client
        .from('transactions')
        .select()
        .eq('date', ymd)
        .order('created_at', ascending: false);
    final list = rows.map(AppTransaction.fromMap).toList();
    await LocalDataCache.writeTransactionsForDay(ymd, list);
    return list;
  }

  Future<void> upsertTransaction(
    AppTransaction item, {
    bool omitCreatedAt = false,
  }) async {
    final rows = await _client
        .from('transactions')
        .upsert(
          item.toInsertMap(omitCreatedAt: omitCreatedAt),
          onConflict: 'id',
        )
        .select('id');

    if (rows.isEmpty) {
      throw Exception(
        'ไม่สามารถยืนยันผลการบันทึกข้อมูลได้ (server ไม่ตอบกลับแถวที่บันทึก)',
      );
    }

    await _invalidateAfterMutation(affectingDate: item.date);
  }

  Future<void> deleteTransaction(String id) async {
    await _client.from('transactions').delete().eq('id', id);
    await LocalDataCache.invalidateDashboard();
    await LocalDataCache.invalidateAllTransactionsByDay();
    await LocalDataCache.invalidateTransactionsFull();
  }
}
