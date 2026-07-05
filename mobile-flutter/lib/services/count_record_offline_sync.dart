import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_transaction.dart';
import '../models/employee.dart';
import 'employee_service.dart';
import 'local_data_cache.dart';
import 'transaction_service.dart';

/// คิวบันทึกออฟไลน์สำหรับเมนู "บันทึกและนับจำนวน"
///
/// - ฟัง connectivity ของ OS (connectivity_plus)
/// - scheduler เดียว + exponential backoff
/// - คิวใน memory (อ่าน prefs ครั้งเดียว)
/// - retry ต่อรายการ + batch upload
class CountRecordOfflineSync {
  CountRecordOfflineSync._();

  static final CountRecordOfflineSync instance = CountRecordOfflineSync._();

  static const _kQueue = 'v1_count_record_offline_queue_v1';
  static const _kCars = 'v1_count_record_cars_json';
  static const _kEmployees = 'v1_count_record_employees_json';
  static const _kDropdownAt = 'v1_count_record_dropdown_cached_ms';

  static const _reachabilityTtlOnline = Duration(seconds: 8);
  static const _reachabilityTtlOffline = Duration(seconds: 18);
  static const _failuresBeforeOffline = 2;
  static const _probeTimeout = Duration(milliseconds: 2500);
  static const _batchChunkSize = 25;
  static const _maxItemRetries = 8;

  static const _schedulerMinDelay = Duration(seconds: 2);
  static const _schedulerMaxDelay = Duration(seconds: 30);

  TransactionService? _autoSyncService;
  SupabaseClient? _autoSyncClient;
  VoidCallback? _onAutoSynced;
  ValueChanged<bool>? _onServerReachabilityChanged;

  Timer? _schedulerTimer;
  Duration _schedulerDelay = _schedulerMinDelay;
  bool _schedulerRunning = false;
  bool _uploadInFlight = false;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _lastHasNetworkLink = true;

  List<_PendingOp>? _memoryQueue;
  bool _queueLoaded = false;

  bool? _cachedReachable;
  DateTime? _reachabilityCheckedAt;
  int _probeFailStreak = 0;
  bool _awaitingUploadAfterOffline = false;

  bool get uploadInFlight => _uploadInFlight;
  bool get awaitingUploadAfterOffline => _awaitingUploadAfterOffline;

  /// หน่วง retry ต่อรายการ (วินาที) — ใช้ใน unit test ได้
  @visibleForTesting
  static Duration retryDelayForCount(int retryCount) {
    final capped = retryCount.clamp(0, 5);
    final seconds = (2 * (1 << capped)).clamp(2, 30);
    return Duration(seconds: seconds);
  }

  Duration _reachabilityTtlFor(bool? reachable) =>
      reachable == false ? _reachabilityTtlOffline : _reachabilityTtlOnline;

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  void noteServerUnreachable() {
    final wasOnline = _cachedReachable != false;
    _cachedReachable = false;
    _reachabilityCheckedAt = DateTime.now();
    _probeFailStreak = _failuresBeforeOffline;
    _awaitingUploadAfterOffline = true;
    if (wasOnline) _onServerReachabilityChanged?.call(false);
  }

  void noteServerReachable() {
    final wasOffline = _cachedReachable == false;
    _cachedReachable = true;
    _reachabilityCheckedAt = DateTime.now();
    _probeFailStreak = 0;
    if (wasOffline) _onServerReachabilityChanged?.call(true);
  }

  Future<void> _ensureQueueLoaded() async {
    if (_queueLoaded) return;
    _memoryQueue = await _readQueueFromDisk();
    _queueLoaded = true;
  }

  Future<List<_PendingOp>> _readQueueFromDisk() async {
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
      debugPrint('CountRecordOfflineSync._readQueueFromDisk: $e\n$st');
      return [];
    }
  }

  Future<List<_PendingOp>> _readQueue() async {
    await _ensureQueueLoaded();
    return _memoryQueue!;
  }

  Future<void> _writeQueue(List<_PendingOp> ops) async {
    _memoryQueue = List<_PendingOp>.from(ops);
    _queueLoaded = true;
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
    await _ensureQueueLoaded();
    return _memoryQueue!.length;
  }

  int get pendingCountSync =>
      _queueLoaded ? (_memoryQueue?.length ?? 0) : -1;

  Future<bool> hasPendingForDay(String ymd) async {
    final ops = await _readQueue();
    return ops.any((o) => o.affectsDate(ymd));
  }

  bool _hasNetworkLink(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<bool> _checkOsNetworkLink() async {
    try {
      final results = await Connectivity().checkConnectivity();
      _lastHasNetworkLink = _hasNetworkLink(results);
      return _lastHasNetworkLink;
    } catch (_) {
      return _lastHasNetworkLink;
    }
  }

  Future<bool> isOnline(
    SupabaseClient client, {
    bool forceProbe = false,
  }) async {
    if (!await _checkOsNetworkLink()) {
      noteServerUnreachable();
      return false;
    }

    final cached = _cachedReachable;
    final checkedAt = _reachabilityCheckedAt;
    if (!forceProbe && cached != null && checkedAt != null) {
      final ttl = _reachabilityTtlFor(cached);
      if (DateTime.now().difference(checkedAt) < ttl) {
        return cached;
      }
    }
    try {
      await client
          .from('transactions')
          .select('id')
          .limit(1)
          .timeout(_probeTimeout);
      _probeFailStreak = 0;
      noteServerReachable();
      return true;
    } catch (_) {
      _probeFailStreak++;
      if (forceProbe || _probeFailStreak >= _failuresBeforeOffline) {
        noteServerUnreachable();
        return false;
      }
      return cached ?? true;
    }
  }

  void _resetSchedulerBackoff() {
    _schedulerDelay = _schedulerMinDelay;
  }

  void _increaseSchedulerBackoff() {
    final nextMs = (_schedulerDelay.inMilliseconds * 2)
        .clamp(_schedulerMinDelay.inMilliseconds, _schedulerMaxDelay.inMilliseconds);
    _schedulerDelay = Duration(milliseconds: nextMs);
  }

  void _scheduleNextCycle({Duration? overrideDelay}) {
    _schedulerTimer?.cancel();
    final delay = overrideDelay ?? _schedulerDelay;
    _schedulerTimer = Timer(delay, () => unawaited(_runSchedulerCycle()));
  }

  void _startConnectivityWatch() {
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen(
      (results) {
        final hasLink = _hasNetworkLink(results);
        _lastHasNetworkLink = hasLink;
        if (hasLink) {
          _resetSchedulerBackoff();
          unawaited(_runSchedulerCycle(immediate: true));
        } else {
          noteServerUnreachable();
          _increaseSchedulerBackoff();
          _scheduleNextCycle();
        }
      },
    );
  }

  Future<void> _runSchedulerCycle({bool immediate = false}) async {
    if (_schedulerRunning || _uploadInFlight) {
      if (!immediate) _scheduleNextCycle();
      return;
    }
    final service = _autoSyncService;
    final client = _autoSyncClient;
    if (service == null || client == null) return;

    _schedulerRunning = true;
    try {
      await _ensureQueueLoaded();
      final pending = _memoryQueue!.length;

      if (!await _checkOsNetworkLink()) {
        _increaseSchedulerBackoff();
        _scheduleNextCycle();
        return;
      }

      final needsWork = pending > 0 || _awaitingUploadAfterOffline;
      final online = await isOnline(
        client,
        forceProbe: needsWork || !(_cachedReachable ?? true),
      );

      if (!online) {
        _increaseSchedulerBackoff();
        _scheduleNextCycle();
        return;
      }

      _resetSchedulerBackoff();

      if (needsWork) {
        await uploadPendingImmediately(service, client);
      }

      _scheduleNextCycle();
    } finally {
      _schedulerRunning = false;
    }
  }

  // --- dropdown cache (unchanged API) ---

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

  // --- merge ---

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
    _resetSchedulerBackoff();
    unawaited(_runSchedulerCycle(immediate: true));
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
    _resetSchedulerBackoff();
    unawaited(_runSchedulerCycle(immediate: true));
  }

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
              o.transaction?.id == transaction.id ||
              o.deleteId == transaction.id,
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

  List<_PendingOp> _readyOps(List<_PendingOp> ops, int nowMs) {
    return ops.where((op) => op.isReadyToRetry(nowMs)).toList();
  }

  Future<int> syncPending(
    TransactionService service,
    SupabaseClient client, {
    bool forceProbe = false,
  }) async {
    if (!await isOnline(client, forceProbe: forceProbe)) return 0;
    await _ensureQueueLoaded();
    if (_memoryQueue!.isEmpty) return 0;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ready = _readyOps(_memoryQueue!, nowMs);
    if (ready.isEmpty) return 0;

    var synced = 0;
    final stillPending = <_PendingOp>[
      ..._memoryQueue!.where((op) => !ready.contains(op)),
    ];

    final upserts = ready.where((o) => o.type == _PendingOpType.upsert).toList();
    final deletes =
        ready.where((o) => o.type == _PendingOpType.delete).toList();

    for (var i = 0; i < upserts.length; i += _batchChunkSize) {
      final chunk = upserts.skip(i).take(_batchChunkSize).toList();
      final batchItems = <({AppTransaction item, bool omitCreatedAt})>[];
      for (final op in chunk) {
        final tx = op.transaction;
        if (tx != null) {
          batchItems.add((item: tx, omitCreatedAt: op.omitCreatedAt));
        }
      }
      if (batchItems.isEmpty) continue;
      try {
        synced += await service.upsertTransactionsBatch(batchItems);
      } catch (e) {
        debugPrint('CountRecordOfflineSync.syncPending batch upsert: $e');
        for (final op in chunk) {
          stillPending.add(op.withRetryFailure(nowMs));
        }
      }
    }

    for (var i = 0; i < deletes.length; i += _batchChunkSize) {
      final chunk = deletes.skip(i).take(_batchChunkSize).toList();
      final batchItems = <({String id, String? affectingDate})>[];
      for (final op in chunk) {
        final id = op.deleteId;
        if (id != null && id.isNotEmpty) {
          batchItems.add((id: id, affectingDate: op.date));
        }
      }
      if (batchItems.isEmpty) continue;
      try {
        synced += await service.deleteTransactionsBatch(batchItems);
      } catch (e) {
        debugPrint('CountRecordOfflineSync.syncPending batch delete: $e');
        for (final op in chunk) {
          stillPending.add(op.withRetryFailure(nowMs));
        }
      }
    }

    await _writeQueue(stillPending);
    if (synced > 0) {
      noteServerReachable();
    }
    return synced;
  }

  Future<int> uploadPendingImmediately([
    TransactionService? service,
    SupabaseClient? client,
  ]) async {
    final s = service ?? _autoSyncService;
    final c = client ?? _autoSyncClient;
    if (s == null || c == null || _uploadInFlight) return 0;

    _uploadInFlight = true;
    try {
      if (!await _checkOsNetworkLink()) return 0;
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

  /// ตรวจและอัปโหลดคิว — scheduler เดียว + connectivity listener
  void startAutoSync({
    required TransactionService service,
    required SupabaseClient client,
    VoidCallback? onSynced,
    ValueChanged<bool>? onServerReachabilityChanged,
  }) {
    _autoSyncService = service;
    _autoSyncClient = client;
    _onAutoSynced = onSynced;
    _onServerReachabilityChanged = onServerReachabilityChanged;
    _startConnectivityWatch();
    _resetSchedulerBackoff();
    unawaited(_runSchedulerCycle(immediate: true));
  }

  void stopAutoSync() {
    _schedulerTimer?.cancel();
    _schedulerTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _autoSyncService = null;
    _autoSyncClient = null;
    _onAutoSynced = null;
    _onServerReachabilityChanged = null;
    _schedulerRunning = false;
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
    this.retryCount = 0,
    this.nextAttemptMs,
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
  final int retryCount;
  final int? nextAttemptMs;

  bool isReadyToRetry(int nowMs) {
    if (retryCount >= CountRecordOfflineSync._maxItemRetries) {
      return nowMs >= (nextAttemptMs ?? 0);
    }
    if (retryCount == 0 || nextAttemptMs == null) return true;
    return nowMs >= nextAttemptMs!;
  }

  _PendingOp withRetryFailure(int nowMs) {
    final nextRetry = retryCount + 1;
    final delay = CountRecordOfflineSync.retryDelayForCount(nextRetry);
    return _PendingOp._(
      type: type,
      transaction: transaction,
      omitCreatedAt: omitCreatedAt,
      deleteId: deleteId,
      date: date,
      queuedAtMs: queuedAtMs,
      retryCount: nextRetry,
      nextAttemptMs: nowMs + delay.inMilliseconds,
    );
  }

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
      'retry_count': retryCount,
      if (nextAttemptMs != null) 'next_attempt_ms': nextAttemptMs,
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
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      nextAttemptMs: (map['next_attempt_ms'] as num?)?.toInt(),
    );
  }
}
