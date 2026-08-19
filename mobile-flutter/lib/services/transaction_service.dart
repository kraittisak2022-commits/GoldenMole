import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_transaction.dart';
import 'local_data_cache.dart';

class TransactionService {
  TransactionService(this._client);

  final SupabaseClient _client;

  static Future<List<AppTransaction>>? _inFlightFull;
  static final Map<String, Future<List<AppTransaction>>> _inFlightByDay = {};

  /// คอลัมน์ที่ [AppTransaction.fromMap] ใช้ — ลด bytes ตอน full fetch (Disk IO / network)
  static const String _transactionColumns =
      'id, date, type, category, description, amount, sub_category, '
      'labor_status, employee_ids, employee_id, note, event_time, event_type, '
      'event_priority, sand_morning, sand_afternoon, sand_machine_type, '
      'sand_operators, drums_obtained, drums_washed_at_home, sand_morning_start, '
      'sand_afternoon_start, sand_evening_end, vehicle_id, vehicle_name, driver_id, '
      'driver_name, driver_wage, '
      'vehicle_wage, work_details, work_type, work_assignments, '
      'work_type_by_employee, custom_work_categories, quantity, unit_price, unit, '
      'project_id, location, fuel_type, fuel_movement, fuel_tank, trip_count, '
      'trip_morning, trip_afternoon, cubic_per_trip, total_cubic, per_car_trips, '
      'per_car_cubic, trip_billing_mode, ot_amount, ot_hours, ot_description, '
      'advance_amount, leave_reason, leave_days, income_payment_status, created_at';

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

  Future<List<AppTransaction>> fetchTransactions({
    bool forceRefresh = false,
  }) {
    final existing = _inFlightFull;
    if (existing != null) return existing;
    final future = _fetchTransactionsBody(forceRefresh: forceRefresh);
    _inFlightFull = future;
    return future.whenComplete(() {
      if (identical(_inFlightFull, future)) _inFlightFull = null;
    });
  }

  Future<List<AppTransaction>> _fetchTransactionsBody({
    required bool forceRefresh,
  }) async {
    if (!forceRefresh) {
      final cached =
          await LocalDataCache.readTransactionsFull(LocalDataCache.transactionsFullTtl);
      if (cached != null) return cached;
    }

    try {
      final rows = await _client
          .from('transactions')
          .select(_transactionColumns)
          .order('created_at', ascending: false);
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
        .select(_transactionColumns)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(AppTransaction.fromMap).toList();
  }

  Future<List<AppTransaction>> fetchTransactionsForDate(
    String ymd, {
    bool forceRefresh = false,
  }) {
    final existing = _inFlightByDay[ymd];
    if (existing != null) return existing;
    final future = _fetchTransactionsForDateBody(
      ymd,
      forceRefresh: forceRefresh,
    );
    _inFlightByDay[ymd] = future;
    return future.whenComplete(() {
      if (identical(_inFlightByDay[ymd], future)) {
        _inFlightByDay.remove(ymd);
      }
    });
  }

  Future<List<AppTransaction>> _fetchTransactionsForDateBody(
    String ymd, {
    required bool forceRefresh,
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
          .select(_transactionColumns)
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
