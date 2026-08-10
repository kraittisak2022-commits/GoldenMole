import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_transaction.dart';
import 'local_data_cache.dart';

class TransactionService {
  TransactionService(this._client);

  final SupabaseClient _client;

  Future<void> _invalidateAfterMutation({
    required String? affectingDate,
    AppTransaction? patchedTx,
    String? removedId,
  }) async {
    await LocalDataCache.invalidateDashboard();
    if (affectingDate != null && affectingDate.isNotEmpty) {
      await LocalDataCache.invalidateTransactionsForDay(affectingDate);
    }
    // แพตช์แถวในแคชเต็มชุดแทนการล้างทั้งก้อน — ลดการดึงตารางทั้งหมดรอบถัดไป
    if (patchedTx != null) {
      await LocalDataCache.patchTransactionInFull(patchedTx);
    } else if (removedId != null && removedId.isNotEmpty) {
      await LocalDataCache.removeTransactionFromFull(removedId);
    } else {
      await LocalDataCache.invalidateTransactionsFull();
    }
  }

  Future<List<AppTransaction>> fetchTransactions({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached =
          await LocalDataCache.readTransactionsFull(LocalDataCache.transactionsFullTtl);
      if (cached != null) return cached;
    }

    try {
      final rows = await _client.from('transactions').select().order('created_at', ascending: false);
      final list = rows.map(AppTransaction.fromMap).toList();
      await LocalDataCache.writeTransactionsFull(list);
      return list;
    } catch (_) {
      final stale = await LocalDataCache.readTransactionsFullAny();
      if (stale != null) return stale;
      rethrow;
    }
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

    try {
      final rows = await _client
          .from('transactions')
          .select()
          .eq('date', ymd)
          .order('created_at', ascending: false);
      final list = rows.map(AppTransaction.fromMap).toList();
      await LocalDataCache.writeTransactionsForDay(ymd, list);
      return list;
    } catch (_) {
      final stale = await LocalDataCache.readTransactionsForDayAny(ymd);
      if (stale != null) return stale;
      rethrow;
    }
  }

  /// ดึง created_at จากเซิร์ฟเวอร์ — ใช้ตรวจ conflict ก่อน upsert
  Future<Map<String, DateTime?>> fetchCreatedAtByIds(List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _client
        .from('transactions')
        .select('id, created_at')
        .inFilter('id', ids);
    final out = <String, DateTime?>{};
    for (final row in rows) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final raw = row['created_at'];
      if (raw == null) {
        out[id] = null;
      } else if (raw is DateTime) {
        out[id] = raw;
      } else {
        out[id] = DateTime.tryParse(raw.toString());
      }
    }
    return out;
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

    await _invalidateAfterMutation(
      affectingDate: item.date,
      patchedTx: item,
    );
  }

  /// อัปโหลดหลายแถวในครั้งเดียว — ใช้ตอนซิงค์คิวออฟไลน์
  Future<int> upsertTransactionsBatch(
    List<({AppTransaction item, bool omitCreatedAt})> items,
  ) async {
    if (items.isEmpty) return 0;
    final maps = items
        .map((e) => e.item.toInsertMap(omitCreatedAt: e.omitCreatedAt))
        .toList();
    final rows = await _client
        .from('transactions')
        .upsert(maps, onConflict: 'id')
        .select('id');
    if (rows.length != maps.length) {
      throw Exception(
        'batch upsert ไม่ครบ (${rows.length}/${maps.length})',
      );
    }
    await LocalDataCache.invalidateDashboard();
    for (final item in items) {
      await LocalDataCache.patchTransactionInFull(item.item);
    }
    for (final d in items.map((e) => e.item.date).toSet()) {
      await LocalDataCache.invalidateTransactionsForDay(d);
    }
    return rows.length;
  }

  Future<void> deleteTransaction(String id, {String? affectingDate}) async {
    await _client.from('transactions').delete().eq('id', id);
    await _invalidateAfterMutation(
      affectingDate: affectingDate,
      removedId: id,
    );
  }

  /// ลบหลายแถวในครั้งเดียว — ใช้ตอนซิงค์คิวออฟไลน์
  Future<int> deleteTransactionsBatch(
    List<({String id, String? affectingDate})> items,
  ) async {
    if (items.isEmpty) return 0;
    final ids = items.map((e) => e.id).where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return 0;
    await _client.from('transactions').delete().inFilter('id', ids);
    await LocalDataCache.invalidateDashboard();
    for (final id in ids) {
      await LocalDataCache.removeTransactionFromFull(id);
    }
    for (final d in items.map((e) => e.affectingDate).whereType<String>()) {
      await LocalDataCache.invalidateTransactionsForDay(d);
    }
    return ids.length;
  }
}
