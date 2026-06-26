import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_transaction.dart';
import '../models/employee.dart';
import 'employee_service.dart';
import 'local_data_cache.dart';
import 'transaction_service.dart';

/// คิวบันทึกออฟไลน์สำหรับเมนู "บันทึกและนับจำนวน"
class CountRecordOfflineSync {
  CountRecordOfflineSync._();

  static final CountRecordOfflineSync instance = CountRecordOfflineSync._();

  static const _kQueue = 'v1_count_record_offline_queue_v1';
  static const _kCars = 'v1_count_record_cars_json';
  static const _kEmployees = 'v1_count_record_employees_json';
  static const _kDropdownAt = 'v1_count_record_dropdown_cached_ms';

  Timer? _autoSyncTimer;
  TransactionService? _autoSyncService;
  SupabaseClient? _autoSyncClient;
  VoidCallback? _onAutoSynced;
  bool _autoSyncTickRunning = false;

  bool? _cachedReachable;
  DateTime? _reachabilityCheckedAt;
  static const _reachabilityTtl = Duration(seconds: 4);
  static const _probeTimeout = Duration(milliseconds: 1200);
  bool _awaitingUploadAfterOffline = false;
  bool _uploadInFlight = false;

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  /// แดชบอร์ดรายงานออฟไลน์ — ข้ามการยิงเครือข่ายชั่วคราว
  void noteServerUnreachable() {
    _cachedReachable = false;
    _reachabilityCheckedAt = DateTime.now();
    _awaitingUploadAfterOffline = true;
  }

  void noteServerReachable() {
    _cachedReachable = true;
    _reachabilityCheckedAt = DateTime.now();
  }

  Future<bool> isOnline(
    SupabaseClient client, {
    bool forceProbe = false,
  }) async {
    if (!forceProbe &&
        _cachedReachable == false &&
        _reachabilityCheckedAt != null &&
        DateTime.now().difference(_reachabilityCheckedAt!) < _reachabilityTtl) {
      return false;
    }
    if (!forceProbe &&
        _cachedReachable == true &&
        _reachabilityCheckedAt != null &&
        DateTime.now().difference(_reachabilityCheckedAt!) < _reachabilityTtl) {
      return true;
    }
    try {
      await client
          .from('transactions')
          .select('id')
          .limit(1)
          .timeout(_probeTimeout);
      noteServerReachable();
      return true;
    } catch (_) {
      noteServerUnreachable();
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

  Future<void> cacheEmployees(List<Employee> employees) async {
    if (employees.isEmpty) return;
    final p = await _prefs();
    await p.setString(
      _kEmployees,
      jsonEncode(employees.map((e) => e.toPersistenceMap()).toList()),
    );
    await p.setInt(_kDropdownAt, DateTime.now().millisecondsSinceEpoch);
  }

  Future<List<Employee>> readCachedEmployees() async {
    final p = await _prefs();
    final raw = p.getString(_kEmployees);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Employee.fromMap)
          .toList();
    } catch (e, st) {
      debugPrint('CountRecordOfflineSync.readCachedEmployees: $e\n$st');
      return const [];
    }
  }

  /// รวมแหล่งพนักงาน — widget / แคช count-record / แคชแอpp
  Future<List<Employee>> mergedEmployeeSources([
    List<Employee>? fromWidget,
  ]) async {
    final byId = <String, Employee>{};
    void addAll(Iterable<Employee> list) {
      for (final e in list) {
        if (e.id.trim().isEmpty) continue;
        byId[e.id] = e;
      }
    }

    addAll(await readCachedEmployees());
    final appCache = await LocalDataCache.readEmployeesAny();
    if (appCache != null) addAll(appCache);
    if (fromWidget != null) addAll(fromWidget);
    return byId.values.toList();
  }

  /// ดึงรถ+พนักงานล่าสุด — ออนไลน์อัปเดตแคช, ออฟไลน์อ่านแคชที่มี
  Future<({List<String> cars, List<Employee> employees})> loadDropdownCatalog({
    required SupabaseClient client,
    EmployeeService? employeeService,
    List<Employee>? widgetEmployees,
    bool serverOnlineHint = true,
    bool forceNetwork = false,
  }) async {
    var cars = await readCachedCars();
    var employees = await mergedEmployeeSources(widgetEmployees);

    final shouldFetch = forceNetwork ||
        (serverOnlineHint && await isOnline(client, forceProbe: forceNetwork));
    if (!shouldFetch || employeeService == null) {
      return (cars: cars, employees: employees);
    }

    try {
      final rows = await client
          .from('app_settings')
          .select('cars')
          .eq('id', 'default')
          .limit(1)
          .timeout(_probeTimeout);
      if (rows.isNotEmpty) {
        final raw = rows.first['cars'];
        final all = <String>[
          if (raw is List)
            ...raw.map((e) => '$e').where((e) => e.trim().isNotEmpty),
        ];
        if (all.isNotEmpty) {
          cars = all;
          await cacheCars(cars);
        }
      }
    } catch (e) {
      debugPrint('CountRecordOfflineSync.loadDropdownCatalog cars: $e');
    }

    try {
      final fetched = await employeeService.fetchEmployees(
        forceRefresh: forceNetwork,
      );
      if (fetched.isNotEmpty) {
        await cacheEmployees(fetched);
        employees = await mergedEmployeeSources(widgetEmployees);
      }
    } catch (e) {
      debugPrint('CountRecordOfflineSync.loadDropdownCatalog employees: $e');
    }

    return (cars: cars, employees: employees);
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

  /// รวมคิวออฟไลน์กับธุรกรรมทั้งหมด — ให้ประวัติเที่ยวรถตรงกับข้อมูลที่บันทึก
  Future<List<AppTransaction>> mergeAllTransactionsAsync(
    List<AppTransaction> serverRows,
  ) async {
    final ops = await _readQueue();
    if (ops.isEmpty) return serverRows;
    final byId = {for (final t in serverRows) t.id: t};
    for (final op in ops) {
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

  Future<void> _syncLocalCaches({
    required String ymd,
    required List<AppTransaction> mergedDayRows,
    AppTransaction? touchedTx,
    String? removedId,
  }) async {
    await _updateDayCache(ymd, mergedDayRows);
    if (touchedTx != null) {
      await LocalDataCache.patchTransactionInFull(touchedTx);
    }
    if (removedId != null && removedId.isNotEmpty) {
      await LocalDataCache.removeTransactionFromFull(removedId);
    }
  }

  List<AppTransaction> _mergedDayRowsAfterUpsert(
    String ymd,
    List<AppTransaction> dayServerRows,
    AppTransaction transaction,
  ) {
    final byId = <String, AppTransaction>{
      for (final t in dayServerRows)
        if (t.date == ymd) t.id: t,
    };
    byId[transaction.id] = transaction;
    return byId.values.toList();
  }

  List<AppTransaction> _mergedDayRowsAfterDelete(
    String ymd,
    List<AppTransaction> dayServerRows,
    String id,
  ) {
    return dayServerRows
        .where((t) => !(t.date == ymd && t.id == id))
        .toList();
  }

  Future<void> _persistOffline({
    required String ymd,
    required AppTransaction transaction,
    required bool omitCreatedAt,
    required List<AppTransaction> dayServerRows,
  }) async {
    await _enqueue(
      _PendingOp.upsert(
        transaction: transaction,
        omitCreatedAt: omitCreatedAt,
      ),
    );
    final merged = _applyQueueSync(ymd, dayServerRows, await _readQueue());
    await _syncLocalCaches(
      ymd: ymd,
      mergedDayRows: merged,
      touchedTx: transaction,
    );
  }

  Future<void> _deleteOffline({
    required String id,
    required String ymd,
    required List<AppTransaction> dayServerRows,
  }) async {
    await _enqueue(_PendingOp.delete(id: id, date: ymd));
    final merged = _applyQueueSync(ymd, dayServerRows, await _readQueue());
    await _syncLocalCaches(
      ymd: ymd,
      mergedDayRows: merged,
      removedId: id,
    );
  }

  /// บันทึก — ออนไลน์ส่ง server ทันที, ออฟไลน์เก็บคิว + แคชวัน
  /// [serverOnlineHint] false = บังคับ probe เน็ตก่อนตัดสินใจ
  Future<bool> persist({
    required TransactionService service,
    required SupabaseClient client,
    required AppTransaction transaction,
    required bool omitCreatedAt,
    required List<AppTransaction> dayServerRows,
    bool serverOnlineHint = true,
  }) async {
    final ymd = transaction.date;
    if (await isOnline(client, forceProbe: !serverOnlineHint)) {
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
        final merged = _mergedDayRowsAfterUpsert(ymd, dayServerRows, transaction);
        await _syncLocalCaches(
          ymd: ymd,
          mergedDayRows: merged,
          touchedTx: transaction,
        );
        noteServerReachable();
        return false;
      } catch (e) {
        debugPrint('CountRecordOfflineSync.persist online failed: $e');
        noteServerUnreachable();
      }
    }

    await _persistOffline(
      ymd: ymd,
      transaction: transaction,
      omitCreatedAt: omitCreatedAt,
      dayServerRows: dayServerRows,
    );
    _awaitingUploadAfterOffline = true;
    return true;
  }

  /// ลบ — ออนไลน์ลบ server ทันที, ออฟไลน์เก็บคิว
  Future<bool> delete({
    required TransactionService service,
    required SupabaseClient client,
    required String id,
    required String ymd,
    required List<AppTransaction> dayServerRows,
    bool serverOnlineHint = true,
  }) async {
    if (await isOnline(client, forceProbe: !serverOnlineHint)) {
      try {
        await service.deleteTransaction(id, affectingDate: ymd);
        final ops = await _readQueue();
        ops.removeWhere(
          (o) => o.transaction?.id == id || o.deleteId == id,
        );
        await _writeQueue(ops);
        final merged = _mergedDayRowsAfterDelete(ymd, dayServerRows, id);
        await _syncLocalCaches(
          ymd: ymd,
          mergedDayRows: merged,
          removedId: id,
        );
        noteServerReachable();
        return false;
      } catch (e) {
        debugPrint('CountRecordOfflineSync.delete online failed: $e');
        noteServerUnreachable();
      }
    }

    await _deleteOffline(
      id: id,
      ymd: ymd,
      dayServerRows: dayServerRows,
    );
    _awaitingUploadAfterOffline = true;
    return true;
  }

  /// อัปโหลดคิวที่ค้าง — คืนจำนวนที่สำเร็จ (ลองทีละรายการ ไม่หยุดทั้งคิวเมื่อรายการเดียวล้ม)
  Future<int> syncPending(
    TransactionService service,
    SupabaseClient client, {
    bool forceProbe = false,
  }) async {
    if (!await isOnline(client, forceProbe: forceProbe)) return 0;
    final ops = await _readQueue();
    if (ops.isEmpty) return 0;

    var synced = 0;
    final stillPending = <_PendingOp>[];
    for (final op in ops) {
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
            await service.deleteTransaction(
              id,
              affectingDate: op.date,
            );
        }
        synced += 1;
      } catch (e) {
        debugPrint('CountRecordOfflineSync.syncPending item failed: $e');
        stillPending.add(op);
      }
    }

    await _writeQueue(stillPending);
    if (synced > 0) {
      noteServerReachable();
    }
    return synced;
  }

  /// อัปโหลดคิวที่ค้างทันทีเมื่อกลับมาออนไลน์ (Wi‑Fi/เน็ต)
  Future<int> uploadPendingImmediately([
    TransactionService? service,
    SupabaseClient? client,
  ]) async {
    final s = service ?? _autoSyncService;
    final c = client ?? _autoSyncClient;
    if (s == null || c == null || _uploadInFlight) return 0;

    _uploadInFlight = true;
    try {
      if (!await isOnline(c, forceProbe: true)) return 0;
      final wasAwaiting = _awaitingUploadAfterOffline;
      final synced = await syncPending(s, c, forceProbe: true);
      final remaining = await pendingCount();
      if (remaining == 0) {
        _awaitingUploadAfterOffline = false;
        noteServerReachable();
      }
      if (synced > 0 || (wasAwaiting && remaining == 0)) {
        _onAutoSynced?.call();
      }
      return synced;
    } finally {
      _uploadInFlight = false;
    }
  }

  /// ซิงค์ทันทีถ้าเชื่อมต่อได้ — ใช้ก่อนโหลดแดชบอร์ด / ตอนกลับมาออนไลน์
  Future<int> syncPendingIfPossible(
    TransactionService service,
    SupabaseClient client, {
    bool forceProbe = false,
  }) async {
    if (forceProbe || _awaitingUploadAfterOffline) {
      return uploadPendingImmediately(service, client);
    }
    return syncPending(service, client, forceProbe: forceProbe);
  }

  /// ตรวจและอัปโหลดคิวเป็นระยะ (เรียกจากแดชบอร์ดตลอดที่ล็อกอินอยู่)
  void startAutoSync({
    required TransactionService service,
    required SupabaseClient client,
    VoidCallback? onSynced,
  }) {
    _autoSyncService = service;
    _autoSyncClient = client;
    _onAutoSynced = onSynced;
    _autoSyncTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_autoSyncTick()),
    );
    unawaited(_autoSyncTick());
  }

  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    _autoSyncService = null;
    _autoSyncClient = null;
    _onAutoSynced = null;
  }

  Future<void> _autoSyncTick() async {
    if (_autoSyncTickRunning || _uploadInFlight) return;
    final service = _autoSyncService;
    final client = _autoSyncClient;
    if (service == null || client == null) return;
    final pending = await pendingCount();
    if (pending == 0 && !_awaitingUploadAfterOffline) return;

    _autoSyncTickRunning = true;
    try {
      final synced = await uploadPendingImmediately(service, client);
      if (synced == 0 && pending == 0 && _cachedReachable == true) {
        _awaitingUploadAfterOffline = false;
      }
    } finally {
      _autoSyncTickRunning = false;
    }
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
