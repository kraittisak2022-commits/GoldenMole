import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_transaction.dart';
import 'local_data_cache.dart';
import 'transaction_service.dart';

/// คิวบันทึกออฟไลน์สำหรับเมนู "บันทึกและนับจำนวน"
class CountRecordOfflineSync {
  CountRecordOfflineSync._();

  static final CountRecordOfflineSync instance = CountRecordOfflineSync._();

  static const _kQueue = 'v1_count_record_offline_queue_v1';
  static const _kCars = 'v1_count_record_cars_json';

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<bool> isOnline(SupabaseClient client) async {
    try {
      await client
          .from('transactions')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 4));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<_PendingOp>> _readQueue() async {
    final p = await _prefs();
    final raw = p.getString(_kQueue);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_PendingOp.fromMap)
          .whereType<_PendingOp>()
          .toList();
    } catch (e, st) {
      debugPrint('CountRecordOfflineSync._readQueue: $e\n$st');
      return [];
    }
  }

  Future<void> _writeQueue(List<_PendingOp> ops) async {
    final p = await _prefs();
    if (ops.isEmpty) {
      await p.remove(_kQueue);
      return;
    }
    await p.setString(
      _kQueue,
      jsonEncode(ops.map((e) => e.toMap()).toList()),
    );
  }

  Future<int> pendingCount() async {
    final ops = await _readQueue();
    return ops.length;
  }

  Future<bool> hasPendingForDay(String ymd) async {
    final ops = await _readQueue();
    return ops.any((o) => o.affectsDate(ymd));
  }

  Future<void> cacheCars(List<String> cars) async {
    if (cars.isEmpty) return;
    final p = await _prefs();
    await p.setString(_kCars, jsonEncode(cars));
  }

  Future<List<String>> readCachedCars() async {
    final p = await _prefs();
    final raw = p.getString(_kCars);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((e) => '$e').where((s) => s.trim().isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  List<AppTransaction> mergeForDay(
    String ymd,
    List<AppTransaction> serverRows,
  ) {
    return _applyQueueSync(ymd, serverRows, const []);
  }

  Future<List<AppTransaction>> mergeForDayAsync(
    String ymd,
    List<AppTransaction> serverRows,
  ) async {
    final ops = await _readQueue();
    return _applyQueueSync(ymd, serverRows, ops);
  }

  List<AppTransaction> _applyQueueSync(
    String ymd,
    List<AppTransaction> serverRows,
    List<_PendingOp> ops,
  ) {
    final byId = <String, AppTransaction>{
      for (final t in serverRows)
        if (t.date == ymd) t.id: t,
    };
    for (final op in ops) {
      if (!op.affectsDate(ymd)) continue;
      switch (op.type) {
        case _PendingOpType.upsert:
          final tx = op.transaction;
          if (tx != null) byId[tx.id] = tx;
        case _PendingOpType.delete:
          final id = op.deleteId;
          if (id != null) byId.remove(id);
      }
    }
    return byId.values.toList();
  }

  Future<void> _enqueue(_PendingOp op) async {
    final ops = await _readQueue();
    ops.removeWhere((existing) {
      if (op.type == _PendingOpType.delete && op.deleteId != null) {
        return existing.transaction?.id == op.deleteId ||
            existing.deleteId == op.deleteId;
      }
      if (op.type == _PendingOpType.upsert && op.transaction != null) {
        return existing.transaction?.id == op.transaction!.id ||
            existing.deleteId == op.transaction!.id;
      }
      return false;
    });
    ops.add(op);
    await _writeQueue(ops);
  }

  Future<void> _updateDayCache(String ymd, List<AppTransaction> merged) async {
    await LocalDataCache.writeTransactionsForDay(ymd, merged);
  }

  /// บันทึก — ออนไลน์ส่ง server ทันที, ออฟไลน์เก็บคิว + แคชวัน
  Future<bool> persist({
    required TransactionService service,
    required SupabaseClient client,
    required AppTransaction transaction,
    required bool omitCreatedAt,
    required List<AppTransaction> dayServerRows,
  }) async {
    final ymd = transaction.date;
    if (await isOnline(client)) {
      try {
        await service.upsertTransaction(
          transaction,
          omitCreatedAt: omitCreatedAt,
        );
        final ops = await _readQueue();
        ops.removeWhere(
          (o) =>
              o.transaction?.id == transaction.id || o.deleteId == transaction.id,
        );
        await _writeQueue(ops);
        return false;
      } catch (e) {
        debugPrint('CountRecordOfflineSync.persist online failed: $e');
      }
    }

    await _enqueue(
      _PendingOp.upsert(
        transaction: transaction,
        omitCreatedAt: omitCreatedAt,
      ),
    );
    final merged = await mergeForDayAsync(ymd, dayServerRows);
    await _updateDayCache(ymd, merged);
    return true;
  }

  /// ลบ — ออนไลน์ลบ server ทันที, ออฟไลน์เก็บคิว
  Future<bool> delete({
    required TransactionService service,
    required SupabaseClient client,
    required String id,
    required String ymd,
    required List<AppTransaction> dayServerRows,
  }) async {
    if (await isOnline(client)) {
      try {
        await service.deleteTransaction(id);
        final ops = await _readQueue();
        ops.removeWhere(
          (o) => o.transaction?.id == id || o.deleteId == id,
        );
        await _writeQueue(ops);
        return false;
      } catch (e) {
        debugPrint('CountRecordOfflineSync.delete online failed: $e');
      }
    }

    await _enqueue(_PendingOp.delete(id: id, date: ymd));
    final merged = await mergeForDayAsync(ymd, dayServerRows);
    await _updateDayCache(ymd, merged);
    return true;
  }

  /// อัปโหลดคิวที่ค้าง — คืนจำนวนที่สำเร็จ
  Future<int> syncPending(
    TransactionService service,
    SupabaseClient client,
  ) async {
    if (!await isOnline(client)) return 0;
    final ops = await _readQueue();
    if (ops.isEmpty) return 0;

    var synced = 0;
    final stillPending = <_PendingOp>[];
    var failed = false;
    for (final op in ops) {
      if (failed) {
        stillPending.add(op);
        continue;
      }
      try {
        switch (op.type) {
          case _PendingOpType.upsert:
            final tx = op.transaction;
            if (tx == null) continue;
            await service.upsertTransaction(
              tx,
              omitCreatedAt: op.omitCreatedAt,
            );
          case _PendingOpType.delete:
            final id = op.deleteId;
            if (id == null || id.isEmpty) continue;
            await service.deleteTransaction(id);
        }
        synced += 1;
      } catch (e) {
        debugPrint('CountRecordOfflineSync.syncPending stop: $e');
        stillPending.add(op);
        failed = true;
      }
    }

    await _writeQueue(stillPending);
    return synced;
  }
}

enum _PendingOpType { upsert, delete }

class _PendingOp {
  _PendingOp._({
    required this.type,
    this.transaction,
    this.omitCreatedAt = false,
    this.deleteId,
    this.date,
    required this.queuedAtMs,
  });

  factory _PendingOp.upsert({
    required AppTransaction transaction,
    required bool omitCreatedAt,
  }) {
    return _PendingOp._(
      type: _PendingOpType.upsert,
      transaction: transaction,
      omitCreatedAt: omitCreatedAt,
      queuedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory _PendingOp.delete({required String id, required String date}) {
    return _PendingOp._(
      type: _PendingOpType.delete,
      deleteId: id,
      date: date,
      queuedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  final _PendingOpType type;
  final AppTransaction? transaction;
  final bool omitCreatedAt;
  final String? deleteId;
  final String? date;
  final int queuedAtMs;

  bool affectsDate(String ymd) {
    if (type == _PendingOpType.upsert) {
      return transaction?.date == ymd;
    }
    return date == ymd;
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      if (transaction != null)
        'transaction': transaction!.toPersistenceMap(),
      'omit_created_at': omitCreatedAt,
      if (deleteId != null) 'delete_id': deleteId,
      if (date != null) 'date': date,
      'queued_at_ms': queuedAtMs,
    };
  }

  static _PendingOp? fromMap(Map<String, dynamic> map) {
    final typeRaw = (map['type'] ?? '').toString();
    final type = switch (typeRaw) {
      'upsert' => _PendingOpType.upsert,
      'delete' => _PendingOpType.delete,
      _ => null,
    };
    if (type == null) return null;
    AppTransaction? tx;
    final txRaw = map['transaction'];
    if (txRaw is Map<String, dynamic>) {
      tx = AppTransaction.fromMap(txRaw);
    }
    return _PendingOp._(
      type: type,
      transaction: tx,
      omitCreatedAt: map['omit_created_at'] == true,
      deleteId: map['delete_id']?.toString(),
      date: map['date']?.toString(),
      queuedAtMs: (map['queued_at_ms'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}
