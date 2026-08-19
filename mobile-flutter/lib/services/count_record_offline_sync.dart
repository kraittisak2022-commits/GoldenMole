import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_sync_snapshot.dart';
import '../models/app_transaction.dart';
import '../models/employee.dart';
import '../utils/vehicle_catalog.dart';
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
  static const _kFailedQueue = 'v1_count_record_failed_queue_v1';
  static const _kCars = 'v1_count_record_cars_json';
  static const _kVehicleCatalog = 'v1_count_record_vehicle_catalog_json';
  static const _kVehicleDefaultDrivers = 'v1_count_record_vehicle_default_drivers_json';
  static const _kFuelOpeningStock = 'v1_count_record_fuel_opening_stock_json';
  static const _kEmployees = 'v1_count_record_employees_json';
  static const _kDropdownAt = 'v1_count_record_dropdown_cached_ms';

  static const _reachabilityTtlOnline = Duration(minutes: 10);
  static const _reachabilityTtlOffline = Duration(minutes: 1);
  static const _failuresBeforeOffline = 2;
  static const _probeTimeout = Duration(milliseconds: 2500);
  static const _batchChunkSize = 25;
  static const _maxItemRetries = 8;

  static const _schedulerMinDelay = Duration(seconds: 10);
  static const _schedulerMaxDelay = Duration(seconds: 30);

  TransactionService? _autoSyncService;
  SupabaseClient? _autoSyncClient;
  VoidCallback? _onAutoSynced;
  ValueChanged<bool>? _onServerReachabilityChanged;

  Timer? _schedulerTimer;
  Duration _schedulerDelay = _schedulerMinDelay;
  bool _schedulerRunning = false;
  bool _schedulerWakeQueued = false;
  bool _uploadInFlight = false;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _lastHasNetworkLink = true;
  bool _connectivityPluginAvailable = true;

  /// สถานะซิงค์กลาง — UI ทั้งแอปฟังค่านี้
  final ValueNotifier<AppSyncSnapshot> syncState =
      ValueNotifier(const AppSyncSnapshot());

  List<_PendingOp>? _memoryQueue;
  List<_PendingOp>? _memoryFailedQueue;
  bool _queueLoaded = false;
  bool _failedQueueLoaded = false;
  VehicleCatalog _vehicleCatalogMemory = VehicleCatalog.empty;

  NetworkLinkState _networkLinkState = NetworkLinkState.unknown;
  ServerReachState _serverReachState = ServerReachState.unknown;
  Timer? _syncFlashTimer;

  RealtimeChannel? _realtimeChannel;
  String? _realtimeDateFilter;
  VoidCallback? _onRemoteDataChanged;
  /// ผู้ฟังเพิ่มเติม (เช่น Quick Input) — ไม่ทับ callback ของ Dashboard
  final Map<Object, VoidCallback> _remoteChangeListeners = {};

  /// จำนวนรายการค้างในคิว — ให้ UI ฟังค่าแทนการตั้ง timer polling เอง
  final ValueNotifier<int> pendingCountListenable = ValueNotifier<int>(0);

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

  void _publishSyncState({SyncActivity? activity}) {
    AppSyncSnapshot.uploadInFlightHint = _uploadInFlight;
    syncState.value = AppSyncSnapshot(
      network: _networkLinkState,
      server: _serverReachState,
      activity: activity ?? syncState.value.activity,
      pendingCount: _memoryQueue?.length ?? pendingCountListenable.value,
      failedCount: _memoryFailedQueue?.length ?? 0,
    );
  }

  void _flashSyncSuccess() {
    _syncFlashTimer?.cancel();
    _publishSyncState(activity: SyncActivity.syncedFlash);
    _syncFlashTimer = Timer(const Duration(seconds: 2), () {
      if (syncState.value.activity == SyncActivity.syncedFlash) {
        _publishSyncState(activity: SyncActivity.idle);
      }
    });
  }

  void _noteNoNetworkLink() {
    _networkLinkState = NetworkLinkState.unlink;
    _serverReachState = ServerReachState.offline;
    _publishSyncState();
    final wasOnline = _cachedReachable != false;
    _cachedReachable = false;
    _reachabilityCheckedAt = DateTime.now();
    _probeFailStreak = _failuresBeforeOffline;
    _awaitingUploadAfterOffline = true;
    if (wasOnline) _onServerReachabilityChanged?.call(false);
  }

  void noteServerUnreachable() {
    if (_networkLinkState == NetworkLinkState.unlink) {
      _noteNoNetworkLink();
      return;
    }
    _networkLinkState = NetworkLinkState.linked;
    _serverReachState = ServerReachState.offline;
    _publishSyncState();
    final wasOnline = _cachedReachable != false;
    _cachedReachable = false;
    _reachabilityCheckedAt = DateTime.now();
    _probeFailStreak = _failuresBeforeOffline;
    _awaitingUploadAfterOffline = true;
    if (wasOnline) _onServerReachabilityChanged?.call(false);
  }

  void noteServerReachable() {
    _networkLinkState = NetworkLinkState.linked;
    _serverReachState = ServerReachState.online;
    _publishSyncState();
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
    pendingCountListenable.value = _memoryQueue!.length;
    _publishSyncState();
  }

  Future<void> _ensureFailedQueueLoaded() async {
    if (_failedQueueLoaded) return;
    _memoryFailedQueue = await _readFailedQueueFromDisk();
    _failedQueueLoaded = true;
    _publishSyncState();
  }

  Future<List<_PendingOp>> _readFailedQueueFromDisk() async {
    final p = await _prefs();
    final raw = p.getString(_kFailedQueue);
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
      debugPrint('CountRecordOfflineSync._readFailedQueueFromDisk: $e\n$st');
      return [];
    }
  }

  Future<List<_PendingOp>> _readFailedQueue() async {
    await _ensureFailedQueueLoaded();
    return _memoryFailedQueue!;
  }

  Future<void> _writeFailedQueue(List<_PendingOp> ops) async {
    _memoryFailedQueue = List<_PendingOp>.from(ops);
    _failedQueueLoaded = true;
    _publishSyncState();
    final p = await _prefs();
    if (ops.isEmpty) {
      await p.remove(_kFailedQueue);
      return;
    }
    await p.setString(
      _kFailedQueue,
      jsonEncode(ops.map((e) => e.toMap()).toList()),
    );
  }

  Future<void> _moveToFailedQueue(
    _PendingOp op,
    SyncFailureReason reason,
  ) async {
    final failed = op.asFailed(reason);
    final failedOps = await _readFailedQueue();
    failedOps.removeWhere((o) => o.itemKey == failed.itemKey);
    failedOps.add(failed);
    await _writeFailedQueue(failedOps);
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
    pendingCountListenable.value = ops.length;
    _publishSyncState();
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

  static bool get _mayUseConnectivityPlugin {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux =>
        true,
      _ => false,
    };
  }

  void _disableConnectivityPlugin({required String reason}) {
    if (!_connectivityPluginAvailable) return;
    _connectivityPluginAvailable = false;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    debugPrint(
      'CountRecordOfflineSync: connectivity_plus unavailable ($reason); '
      'using scheduler-only probing.',
    );
  }

  Future<bool> _probeConnectivityPlugin() async {
    if (!_mayUseConnectivityPlugin) {
      _disableConnectivityPlugin(reason: 'unsupported platform');
      return false;
    }
    try {
      final results = await Connectivity().checkConnectivity();
      _lastHasNetworkLink = _hasNetworkLink(results);
      return true;
    } on MissingPluginException catch (e) {
      _disableConnectivityPlugin(reason: e.toString());
      return false;
    } on PlatformException catch (e) {
      _disableConnectivityPlugin(reason: e.toString());
      return false;
    } catch (e) {
      debugPrint('CountRecordOfflineSync: connectivity probe failed — $e');
      return false;
    }
  }

  Future<bool> _checkOsNetworkLink() async {
    if (!_connectivityPluginAvailable) return true;
    try {
      final results = await Connectivity().checkConnectivity();
      _lastHasNetworkLink = _hasNetworkLink(results);
      return _lastHasNetworkLink;
    } on MissingPluginException catch (e) {
      _disableConnectivityPlugin(reason: e.toString());
      return true;
    } on PlatformException catch (_) {
      return _lastHasNetworkLink;
    } catch (_) {
      return _lastHasNetworkLink;
    }
  }

  Future<void> _startConnectivityWatch() async {
    if (!_connectivityPluginAvailable || _connectivitySub != null) return;
    if (!await _probeConnectivityPlugin()) return;

    try {
      _connectivitySub = Connectivity()
          .onConnectivityChanged
          .handleError((Object e, StackTrace st) {
            if (e is MissingPluginException || e is PlatformException) {
              _disableConnectivityPlugin(reason: e.toString());
            }
          })
          .listen(
            (results) {
              if (!_connectivityPluginAvailable) return;
              final hasLink = _hasNetworkLink(results);
              _lastHasNetworkLink = hasLink;
              if (hasLink) {
                _networkLinkState = NetworkLinkState.linked;
                _publishSyncState();
                _resetSchedulerBackoff();
                unawaited(_runSchedulerCycle(immediate: true));
              } else {
                _noteNoNetworkLink();
                _increaseSchedulerBackoff();
                _scheduleNextCycle();
              }
            },
            onError: (Object e, StackTrace st) {
              if (e is MissingPluginException || e is PlatformException) {
                _disableConnectivityPlugin(reason: e.toString());
              }
            },
            cancelOnError: false,
          );
    } on MissingPluginException catch (e) {
      _disableConnectivityPlugin(reason: e.toString());
    } on PlatformException catch (e) {
      _disableConnectivityPlugin(reason: e.toString());
    }
  }

  Future<bool> _probeServerReachability(
    SupabaseClient client, {
    bool force = false,
  }) async {
    try {
      await client
          .from('app_settings')
          .select('id')
          .eq('id', 'default')
          .limit(1)
          .timeout(_probeTimeout);
      _probeFailStreak = 0;
      noteServerReachable();
      return true;
    } catch (_) {
      _probeFailStreak++;
      if (force || _probeFailStreak >= _failuresBeforeOffline) {
        noteServerUnreachable();
        return false;
      }
      return _cachedReachable ?? true;
    }
  }

  Future<bool> isOnline(
    SupabaseClient client, {
    bool forceProbe = false,
  }) async {
    if (!await _checkOsNetworkLink()) {
      _noteNoNetworkLink();
      return false;
    }
    _networkLinkState = NetworkLinkState.linked;
    _publishSyncState();

    final cached = _cachedReachable;
    final checkedAt = _reachabilityCheckedAt;
    if (!forceProbe && cached != null && checkedAt != null) {
      final ttl = _reachabilityTtlFor(cached);
      if (DateTime.now().difference(checkedAt) < ttl) {
        return cached;
      }
    }
    return _probeServerReachability(client, force: forceProbe);
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

  Future<void> _runSchedulerCycle({bool immediate = false}) async {
    if (_schedulerRunning || _uploadInFlight) {
      _schedulerWakeQueued = true;
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
      if (pending == 0) {
        _awaitingUploadAfterOffline = false;
        // คิวว่าง — ไม่ probe / ไม่ตั้งรอบถัดไป (ปลุกจาก connectivity / resume / enqueue)
        return;
      }

      if (!await _checkOsNetworkLink()) {
        _increaseSchedulerBackoff();
        _scheduleNextCycle();
        return;
      }

      final online = await isOnline(
        client,
        forceProbe: !(_cachedReachable ?? true),
      );

      if (!online) {
        _increaseSchedulerBackoff();
        _scheduleNextCycle();
        return;
      }

      _resetSchedulerBackoff();
      await uploadPendingImmediately(service, client);
      if ((_memoryQueue?.length ?? 0) > 0) {
        _scheduleNextCycle();
      } else {
        _awaitingUploadAfterOffline = false;
      }
    } finally {
      _schedulerRunning = false;
      if (_schedulerWakeQueued) {
        _schedulerWakeQueued = false;
        unawaited(_runSchedulerCycle(immediate: true));
      }
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

  Future<void> cacheVehicleCatalog(List<VehicleCatalogRow> rows) async {
    if (rows.isEmpty) return;
    _vehicleCatalogMemory = VehicleCatalog(List<VehicleCatalogRow>.from(rows));
    final p = await _prefs();
    await p.setString(
      _kVehicleCatalog,
      jsonEncode(rows.map((r) => r.toJson()).toList()),
    );
  }

  Future<VehicleCatalog> readCachedVehicleCatalog() async {
    if (_vehicleCatalogMemory.rows.isNotEmpty) return _vehicleCatalogMemory;
    final p = await _prefs();
    final raw = p.getString(_kVehicleCatalog);
    if (raw == null || raw.isEmpty) return VehicleCatalog.empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return VehicleCatalog.empty;
      final rows = <VehicleCatalogRow>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final row = VehicleCatalogRow.fromMap(Map<String, dynamic>.from(item));
        if (row.id.isEmpty || row.name.isEmpty) continue;
        rows.add(row);
      }
      rows.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      _vehicleCatalogMemory = VehicleCatalog(rows);
      return _vehicleCatalogMemory;
    } catch (_) {
      return VehicleCatalog.empty;
    }
  }

  List<VehicleCatalogRow> _parseVehicleTableRows(dynamic rows) {
    final out = <VehicleCatalogRow>[];
    if (rows is! List) return out;
    for (final item in rows) {
      if (item is! Map) continue;
      final row = VehicleCatalogRow.fromMap(Map<String, dynamic>.from(item));
      if (row.id.isEmpty || row.name.isEmpty) continue;
      out.add(row);
    }
    out.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.name.compareTo(b.name);
    });
    return out;
  }

  Future<VehicleCatalog> fetchAndCacheVehicleCatalog(
    SupabaseClient client,
  ) async {
    try {
      final rows = await client
          .from('vehicles')
          .select('id, name, default_driver_id, sort_order')
          .order('sort_order')
          .timeout(_probeTimeout);
      final parsed = _parseVehicleTableRows(rows);
      if (parsed.isNotEmpty) {
        await cacheVehicleCatalog(parsed);
        await cacheCars(parsed.map((r) => r.name).toList());
        final drivers = <String, String>{};
        for (final r in parsed) {
          final d = (r.defaultDriverId ?? '').trim();
          if (d.isEmpty) continue;
          drivers[r.name] = d;
        }
        if (drivers.isNotEmpty) {
          await cacheVehicleDefaultDrivers(drivers);
        }
        return VehicleCatalog(parsed);
      }
    } catch (e) {
      debugPrint('CountRecordOfflineSync.fetchAndCacheVehicleCatalog: $e');
    }
    return readCachedVehicleCatalog();
  }

  Future<AppTransaction> stampPersistedTransaction(AppTransaction t) async {
    final catalog = await readCachedVehicleCatalog();
    final employees = await mergedEmployeeSources();
    return stampVehicleAndDriverNames(
      t,
      catalog: catalog,
      employees: employees,
    );
  }

  Future<void> cacheVehicleDefaultDrivers(
    Map<String, String> map, {
    bool allowEmpty = false,
  }) async {
    if (map.isEmpty && !allowEmpty) return;
    final p = await _prefs();
    await p.setString(_kVehicleDefaultDrivers, jsonEncode(map));
  }

  Future<Map<String, String>> readCachedVehicleDefaultDrivers() async {
    final p = await _prefs();
    final raw = p.getString(_kVehicleDefaultDrivers);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map(
        (key, value) => MapEntry('$key'.trim(), '$value'.trim()),
      )..removeWhere((key, value) => key.isEmpty || value.isEmpty);
    } catch (_) {
      return const {};
    }
  }

  /// สต็อกน้ำมันยกมาจากตั้งค่าเว็บ (`app_settings.fuel_opening_stock`)
  Future<void> cacheFuelOpeningStock(
    ({double diesel, double benzine}) opening,
  ) async {
    final p = await _prefs();
    await p.setString(
      _kFuelOpeningStock,
      jsonEncode({'Diesel': opening.diesel, 'Benzine': opening.benzine}),
    );
  }

  Future<({double diesel, double benzine})> readCachedFuelOpeningStock() async {
    final p = await _prefs();
    final raw = p.getString(_kFuelOpeningStock);
    if (raw == null || raw.isEmpty) return (diesel: 0.0, benzine: 0.0);
    try {
      return parseFuelOpeningStock(jsonDecode(raw));
    } catch (_) {
      return (diesel: 0.0, benzine: 0.0);
    }
  }

  static ({double diesel, double benzine}) parseFuelOpeningStock(dynamic raw) {
    if (raw is! Map) return (diesel: 0.0, benzine: 0.0);
    double num0(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? 0;
    }

    return (diesel: num0(raw['Diesel']), benzine: num0(raw['Benzine']));
  }

  static Map<String, String> parseVehicleDefaultDrivers(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((key, value) {
      final vehicle = '$key'.trim();
      final driverId = '$value'.trim();
      if (vehicle.isNotEmpty && driverId.isNotEmpty) {
        out[vehicle] = driverId;
      }
    });
    return out;
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

  Future<({
    List<String> cars,
    List<Employee> employees,
    Map<String, String> vehicleDefaultDrivers,
  })> loadDropdownCatalog({
    required SupabaseClient client,
    EmployeeService? employeeService,
    List<Employee>? widgetEmployees,
    bool serverOnlineHint = true,
    bool forceNetwork = false,
  }) async {
    var cars = await readCachedCars();
    var employees = await mergedEmployeeSources(widgetEmployees);
    var vehicleDefaultDrivers = await readCachedVehicleDefaultDrivers();
    final cachedCatalog = await readCachedVehicleCatalog();
    if (cachedCatalog.names.isNotEmpty) {
      cars = cachedCatalog.names;
      if (cachedCatalog.defaultDriversByName.isNotEmpty) {
        vehicleDefaultDrivers = cachedCatalog.defaultDriversByName;
      }
    }

    if (!forceNetwork &&
        cars.isNotEmpty &&
        employees.isNotEmpty &&
        cachedCatalog.rows.isNotEmpty) {
      return (
        cars: cars,
        employees: employees,
        vehicleDefaultDrivers: vehicleDefaultDrivers,
      );
    }

    final shouldFetch = forceNetwork ||
        (serverOnlineHint && await isOnline(client, forceProbe: forceNetwork));
    if (!shouldFetch || employeeService == null) {
      return (
        cars: cars,
        employees: employees,
        vehicleDefaultDrivers: vehicleDefaultDrivers,
      );
    }

    try {
      final catalog = await fetchAndCacheVehicleCatalog(client);
      if (catalog.names.isNotEmpty) {
        cars = catalog.names;
        if (catalog.defaultDriversByName.isNotEmpty) {
          vehicleDefaultDrivers = catalog.defaultDriversByName;
        }
      }
    } catch (e) {
      debugPrint('CountRecordOfflineSync.loadDropdownCatalog vehicles: $e');
    }

    if (cars.isEmpty) {
    try {
      final rows = await client
          .from('app_settings')
          .select('cars, app_defaults')
          .eq('id', 'default')
          .limit(1)
          .timeout(_probeTimeout);
      if (rows.isNotEmpty) {
        final row = rows.first;
        final raw = row['cars'];
        final all = <String>[
          if (raw is List)
            ...raw.map((e) => '$e').where((e) => e.trim().isNotEmpty),
        ];
        if (all.isNotEmpty) {
          cars = all;
          await cacheCars(cars);
        }

        final appDefaults = row['app_defaults'];
        if (appDefaults is Map) {
          final rawDefaults = appDefaults['vehicleDefaultDrivers'];
          if (rawDefaults != null) {
            final parsed = parseVehicleDefaultDrivers(rawDefaults);
            // mirror จากเว็บเมื่อมีค่าอย่างน้อย 1 คัน — รองรับเปลี่ยน/ลบต่อคัน
            // ถ้าเว็บว่างทั้งก้อน คงแคชเดิม (ไม่ล้างทั้งหมด)
            if (parsed.isNotEmpty) {
              vehicleDefaultDrivers = parsed;
              await cacheVehicleDefaultDrivers(vehicleDefaultDrivers);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('CountRecordOfflineSync.loadDropdownCatalog cars: $e');
    }
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

    return (
      cars: cars,
      employees: employees,
      vehicleDefaultDrivers: vehicleDefaultDrivers,
    );
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
    int? knownServerCreatedAtMs,
  }) async {
    await _enqueue(
      _PendingOp.upsert(
        transaction: transaction,
        omitCreatedAt: omitCreatedAt,
        knownServerCreatedAtMs: knownServerCreatedAtMs,
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
    final stamped = await stampPersistedTransaction(transaction);
    if (await isOnline(client, forceProbe: !serverOnlineHint)) {
      try {
        await service.upsertTransaction(
          stamped,
          omitCreatedAt: omitCreatedAt,
        );
        final ops = await _readQueue();
        ops.removeWhere(
          (o) =>
              o.transaction?.id == stamped.id ||
              o.deleteId == stamped.id,
        );
        await _writeQueue(ops);
        final merged = _mergedDayRowsAfterUpsert(ymd, dayServerRows, stamped);
        await _syncLocalCaches(
          ymd: ymd,
          mergedDayRows: merged,
          touchedTx: stamped,
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
      transaction: stamped,
      omitCreatedAt: omitCreatedAt,
      dayServerRows: dayServerRows,
      knownServerCreatedAtMs: _createdAtMsForId(dayServerRows, stamped.id),
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

  int? _createdAtMsForId(List<AppTransaction> rows, String id) {
    for (final row in rows) {
      if (row.id == id) return row.createdAt?.millisecondsSinceEpoch;
    }
    return null;
  }

  Future<List<_PendingOp>> _splitConflicts(
    TransactionService service,
    List<_PendingOp> upserts,
  ) async {
    if (upserts.isEmpty) return upserts;
    final withBaseline = upserts
        .where((o) =>
            o.knownServerCreatedAtMs != null && o.transaction != null)
        .toList();
    if (withBaseline.isEmpty) return upserts;

    final ids = withBaseline.map((o) => o.transaction!.id).toList();
    final serverTimes = await service.fetchCreatedAtByIds(ids);
    final conflicts = <_PendingOp>[];
    final ok = <_PendingOp>[];

    for (final op in upserts) {
      final tx = op.transaction;
      if (tx == null) {
        ok.add(op);
        continue;
      }
      final baseline = op.knownServerCreatedAtMs;
      final serverAt = serverTimes[tx.id];
      if (baseline != null &&
          serverAt != null &&
          serverAt.millisecondsSinceEpoch > baseline) {
        conflicts.add(op);
        continue;
      }
      ok.add(op);
    }

    for (final c in conflicts) {
      await _moveToFailedQueue(c, SyncFailureReason.conflict);
    }
    return ok;
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
    if (_memoryQueue!.isEmpty) {
      _awaitingUploadAfterOffline = false;
      return 0;
    }

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

    final upsertsToSend = await _splitConflicts(service, upserts);

    for (var i = 0; i < upsertsToSend.length; i += _batchChunkSize) {
      final chunk = upsertsToSend.skip(i).take(_batchChunkSize).toList();
      final batchItems = <({AppTransaction item, bool omitCreatedAt})>[];
      for (final op in chunk) {
        final tx = op.transaction;
        if (tx != null) {
          batchItems.add((
            item: await stampPersistedTransaction(tx),
            omitCreatedAt: op.omitCreatedAt,
          ));
        }
      }
      if (batchItems.isEmpty) continue;
      try {
        synced += await service.upsertTransactionsBatch(batchItems);
      } catch (e) {
        debugPrint('CountRecordOfflineSync.syncPending batch upsert: $e');
        for (final op in chunk) {
          final failed = op.withRetryFailure(nowMs);
          if (failed.retryCount >= _maxItemRetries) {
            await _moveToFailedQueue(
              failed,
              SyncFailureReason.retryExhausted,
            );
          } else {
            stillPending.add(failed);
          }
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
          final failed = op.withRetryFailure(nowMs);
          if (failed.retryCount >= _maxItemRetries) {
            await _moveToFailedQueue(
              failed,
              SyncFailureReason.retryExhausted,
            );
          } else {
            stillPending.add(failed);
          }
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

    await _ensureQueueLoaded();
    if (_memoryQueue!.isEmpty) {
      _awaitingUploadAfterOffline = false;
      return 0;
    }

    _uploadInFlight = true;
    _publishSyncState(activity: SyncActivity.syncing);
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
        if (synced > 0) _flashSyncSuccess();
      }
      return synced;
    } finally {
      _uploadInFlight = false;
      _publishSyncState(activity: SyncActivity.idle);
    }
  }

  /// ซิงค์ทันที — ใช้จากปุ่ม "ซิงค์เลย" / pull-to-refresh
  Future<int> syncNow() async {
    return uploadPendingImmediately();
  }

  /// เรียกเมื่อแอปกลับ foreground
  void onAppResumed() {
    unawaited(_runSchedulerCycle(immediate: true));
  }

  /// Realtime สำหรับวันที่เลือก — อัปเดต UI เมื่อมีข้อมูลจากเครื่องอื่น
  void configureTransactionRealtime({
    required String dateYmd,
    VoidCallback? onRemoteChange,
  }) {
    _realtimeDateFilter = dateYmd;
    _onRemoteDataChanged = onRemoteChange;
    final client = _autoSyncClient;
    if (client != null) {
      unawaited(_restartRealtime(client));
    }
  }

  /// ลงทะเบียนฟัง remote change โดยไม่ทับ callback หลักของ Dashboard
  void addRemoteChangeListener(Object key, VoidCallback onRemoteChange) {
    _remoteChangeListeners[key] = onRemoteChange;
  }

  void removeRemoteChangeListener(Object key) {
    _remoteChangeListeners.remove(key);
  }

  void _notifyRemoteChangeListeners() {
    _onRemoteDataChanged?.call();
    final listeners = List<VoidCallback>.from(_remoteChangeListeners.values);
    for (final cb in listeners) {
      try {
        cb();
      } catch (e, st) {
        debugPrint('CountRecordOfflineSync remote listener: $e\n$st');
      }
    }
  }

  Future<void> _restartRealtime(SupabaseClient client) async {
    await _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    final day = _realtimeDateFilter;
    if (day == null || day.isEmpty) return;

    _realtimeChannel = client
        .channel('mobile_tx_$day')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'date',
            value: day,
          ),
          callback: (payload) {
            debugPrint(
              'CountRecordOfflineSync realtime: ${payload.eventType}',
            );
            _notifyRemoteChangeListeners();
          },
        )
        .subscribe();
  }

  Future<List<FailedSyncItem>> listFailedItems() async {
    final ops = await _readFailedQueue();
    return ops.map(_toFailedSyncItem).toList();
  }

  FailedSyncItem _toFailedSyncItem(_PendingOp op) {
    final isDelete = op.type == _PendingOpType.delete;
    final label = isDelete
        ? 'ลบ ${op.deleteId ?? 'รายการ'}'
        : (op.transaction?.description.trim().isNotEmpty == true
            ? op.transaction!.description
            : 'บันทึก ${op.transaction?.id ?? ''}');
    return FailedSyncItem(
      key: op.itemKey,
      label: label,
      date: op.date ?? op.transaction?.date ?? '',
      reason: op.failureReason ?? SyncFailureReason.serverError,
      failedAtMs: op.failedAtMs ?? op.queuedAtMs,
      isDelete: isDelete,
    );
  }

  Future<void> retryFailedItem(String key) async {
    final failedOps = await _readFailedQueue();
    final idx = failedOps.indexWhere((o) => o.itemKey == key);
    if (idx < 0) return;
    final op = failedOps.removeAt(idx).resetForRetry();
    await _writeFailedQueue(failedOps);
    final queue = await _readQueue();
    queue.removeWhere((o) => o.itemKey == key);
    queue.add(op);
    await _writeQueue(queue);
    _resetSchedulerBackoff();
    unawaited(_runSchedulerCycle(immediate: true));
  }

  Future<void> discardFailedItem(String key) async {
    final failedOps = await _readFailedQueue();
    failedOps.removeWhere((o) => o.itemKey == key);
    await _writeFailedQueue(failedOps);
  }

  Future<void> retryAllFailed() async {
    final failedOps = await _readFailedQueue();
    if (failedOps.isEmpty) return;
    final queue = await _readQueue();
    for (final op in failedOps) {
      queue.removeWhere((o) => o.itemKey == op.itemKey);
      queue.add(op.resetForRetry());
    }
    await _writeQueue(queue);
    await _writeFailedQueue([]);
    _resetSchedulerBackoff();
    unawaited(_runSchedulerCycle(immediate: true));
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
    unawaited(_startConnectivityWatch());
    _resetSchedulerBackoff();
    unawaited(_ensureFailedQueueLoaded());
    unawaited(_runSchedulerCycle(immediate: true));
    if (_realtimeDateFilter != null) {
      unawaited(_restartRealtime(client));
    }
  }

  void stopAutoSync() {
    _schedulerTimer?.cancel();
    _schedulerTimer = null;
    _syncFlashTimer?.cancel();
    _syncFlashTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    unawaited(_realtimeChannel?.unsubscribe());
    _realtimeChannel = null;
    _autoSyncService = null;
    _autoSyncClient = null;
    _onAutoSynced = null;
    _onServerReachabilityChanged = null;
    _onRemoteDataChanged = null;
    _remoteChangeListeners.clear();
    _schedulerRunning = false;
    _schedulerWakeQueued = false;
    _publishSyncState(activity: SyncActivity.idle);
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
    this.knownServerCreatedAtMs,
    this.failureReason,
    this.failedAtMs,
  });

  factory _PendingOp.upsert({
    required AppTransaction transaction,
    required bool omitCreatedAt,
    int? knownServerCreatedAtMs,
  }) {
    return _PendingOp._(
      type: _PendingOpType.upsert,
      transaction: transaction,
      omitCreatedAt: omitCreatedAt,
      knownServerCreatedAtMs: knownServerCreatedAtMs,
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
  final int? knownServerCreatedAtMs;
  final SyncFailureReason? failureReason;
  final int? failedAtMs;

  String get itemKey {
    if (type == _PendingOpType.delete) {
      return 'del:${deleteId ?? ''}';
    }
    return 'ups:${transaction?.id ?? queuedAtMs}';
  }

  bool isReadyToRetry(int nowMs) {
    if (retryCount >= CountRecordOfflineSync._maxItemRetries) return false;
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
      knownServerCreatedAtMs: knownServerCreatedAtMs,
    );
  }

  _PendingOp asFailed(SyncFailureReason reason) {
    return _PendingOp._(
      type: type,
      transaction: transaction,
      omitCreatedAt: omitCreatedAt,
      deleteId: deleteId,
      date: date,
      queuedAtMs: queuedAtMs,
      retryCount: retryCount,
      nextAttemptMs: nextAttemptMs,
      knownServerCreatedAtMs: knownServerCreatedAtMs,
      failureReason: reason,
      failedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  _PendingOp resetForRetry() {
    return _PendingOp._(
      type: type,
      transaction: transaction,
      omitCreatedAt: omitCreatedAt,
      deleteId: deleteId,
      date: date,
      queuedAtMs: queuedAtMs,
      retryCount: 0,
      nextAttemptMs: null,
      knownServerCreatedAtMs: knownServerCreatedAtMs,
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
      if (knownServerCreatedAtMs != null)
        'known_server_created_at_ms': knownServerCreatedAtMs,
      if (failureReason != null) 'failure_reason': failureReason!.name,
      if (failedAtMs != null) 'failed_at_ms': failedAtMs,
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
    SyncFailureReason? failureReason;
    final reasonRaw = map['failure_reason']?.toString();
    if (reasonRaw != null) {
      for (final r in SyncFailureReason.values) {
        if (r.name == reasonRaw) {
          failureReason = r;
          break;
        }
      }
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
      knownServerCreatedAtMs:
          (map['known_server_created_at_ms'] as num?)?.toInt(),
      failureReason: failureReason,
      failedAtMs: (map['failed_at_ms'] as num?)?.toInt(),
    );
  }
}
