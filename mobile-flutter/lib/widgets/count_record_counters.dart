import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user.dart';
import '../models/app_transaction.dart';
import '../models/employee.dart';
import '../services/count_record_offline_sync.dart';
import '../services/employee_service.dart';
import '../services/transaction_service.dart';
import '../utils/count_record_vehicle_defaults.dart';
import '../utils/touch_profile.dart';
import '../utils/daily_module_transactions.dart';
import '../utils/mobile_error_screen_tracker.dart';
import '../utils/mobile_screen_ids.dart';
import '../utils/app_haptics.dart';
import '../utils/device_perf.dart';
import '../utils/record_feedback_sound.dart';
import '../utils/record_success_speaker.dart';
import 'count_record_panel_skeleton.dart';
import 'soft_press_button.dart';

/// โหมดของแผงนับ — เที่ยวรถ (ต้องเลือกรถ/คนขับก่อน) หรือ ร่อนทราย (หน่วยเดียว)
enum CounterMode { trip, sand }

/// อ่านชั่วโมงจาก lap stamp รูปแบบ `dd/MM HH:mm:ss` — คืน null ถ้าอ่านไม่ได้
int? _lapHourOf(String stamp) {
  final space = stamp.indexOf(' ');
  final timePart = space >= 0 ? stamp.substring(space + 1) : stamp;
  final colon = timePart.indexOf(':');
  if (colon <= 0) return null;
  final h = int.tryParse(timePart.substring(0, colon));
  if (h == null || h < 0 || h > 23) return null;
  return h;
}

/// เวลา `HH:mm` สั้นๆ จาก lap stamp — ใช้บนชิปไทม์ไลน์
String _lapClockOf(String stamp) {
  final space = stamp.indexOf(' ');
  final timePart = space >= 0 ? stamp.substring(space + 1) : stamp;
  final lastColon = timePart.lastIndexOf(':');
  return lastColon > 0 ? timePart.substring(0, lastColon) : timePart;
}

/// 1 หน่วยนับ = 1 ธุรกรรมที่บันทึกสดลงฐานข้อมูล
class _CounterUnit {
  _CounterUnit({
    required this.txId,
    required this.title,
    required this.subtitle,
    this.rounds = 0,
    List<String>? lapTimes,
    this.persisted = false,
    this.vehicleId,
    this.driverId,
    this.workDetails = '',
  }) : lapTimes = lapTimes ?? <String>[];

  String txId;
  String title;
  String subtitle;
  int rounds;
  final List<String> lapTimes;
  bool persisted;
  String? vehicleId;
  String? driverId;
  String workDetails;
  bool busy = false;
  DateTime? recordCooldownUntil;
  int burstTick = 0;

  /// ระบบคอมโบแบบเกม — นับการบันทึกต่อเนื่องภายในช่วงเวลาสั้นๆ
  int comboCount = 0;
  DateTime? lastRecordAt;

  bool get isOnRecordCooldown {
    final until = recordCooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  int get recordCooldownSecondsLeft {
    final until = recordCooldownUntil;
    if (until == null) return 0;
    final left = until.difference(DateTime.now()).inSeconds;
    return left <= 0 ? 0 : left + 1;
  }

  bool get isBrokenReported => isWorkDetailsBroken(workDetails);

  static bool isWorkDetailsBroken(String details) {
    final lastBroken = details.lastIndexOf('รถเสีย');
    if (lastBroken < 0) return false;
    final lastNormal = details.lastIndexOf('รถปกติ');
    return lastNormal < lastBroken;
  }
}

class _Pick {
  String vehicleId = '';
  String driverId = '';
}

enum _UnitEditAction { changeDriver, reportBroken, restoreNormal }

/// แผงนับเที่ยว/รอบแบบฝังในการ์ด — กดปุ่มแล้วบันทึกวันเวลา + เพิ่มจำนวน 1
class CountRecordCounterPanel extends StatefulWidget {
  const CountRecordCounterPanel({
    super.key,
    required this.mode,
    required this.service,
    required this.employeeService,
    required this.currentAdmin,
    required this.dateYmd,
    required this.dayTransactions,
    required this.employees,
    this.tripHistoryTransactions = const [],
    this.embedded = false,
    this.serverOnline = true,
    this.onDataChanged,
  });

  final CounterMode mode;
  final TransactionService service;
  final EmployeeService employeeService;
  final AdminUser currentAdmin;
  final String dateYmd;
  final List<AppTransaction> dayTransactions;
  final List<Employee> employees;
  final List<AppTransaction> tripHistoryTransactions;
  final bool embedded;
  final bool serverOnline;
  final VoidCallback? onDataChanged;

  @override
  State<CountRecordCounterPanel> createState() =>
      _CountRecordCounterPanelState();
}

class _CountRecordCounterPanelState extends State<CountRecordCounterPanel>
    with AutomaticKeepAliveClientMixin {
  static const _recordTapCooldown = Duration(seconds: 3);
  static const _sandRecentLapsVisible = 4;
  static const _kTripGoalPrefKey = 'count_record_trip_goal_v1';

  /// เป้าหมายเที่ยวต่อคันต่อวัน (0 = ปิด)
  int _tripGoal = 0;
  final GlobalKey _shareCardKey = GlobalKey();

  final List<_CounterUnit> _units = [];
  List<String> _cars = const [];
  List<Employee> _drivers = const [];
  Map<String, String> _vehicleDefaultDrivers = const {};
  Timer? _offlineSyncTicker;
  Timer? _dropdownRefreshTicker;
  Timer? _parentRefreshDebounce;
  bool _isOnline = true;
  int _pendingCount = 0;
  bool _addVehiclePanelOpen = false;
  int _skipExternalDayTxReload = 0;
  final Set<String> _hiddenDayTxIds = {};
  bool _panelBootstrapping = true;

  @override
  bool get wantKeepAlive => true;

  _CounterUnit? get _sandUnit =>
      _units.isEmpty ? null : _units.first;

  @override
  void initState() {
    super.initState();
    _syncErrorTrackerStep();
    _isOnline = widget.serverOnline;
    // โหลดรายการรถ/คนขับจากแคชทันที — เปิด popup เพิ่มรถได้เร็ว
    unawaited(_refreshDropdownLists(tryNetwork: false));
    unawaited(_initPanel());
    unawaited(RecordSuccessSpeaker.instance.warmUp());
    _syncDropdownRefreshTimer();
    _syncOfflinePollTimer();
    if (widget.mode == CounterMode.trip) {
      unawaited(_loadTripGoal());
    }
  }

  Future<void> _loadTripGoal() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getInt(_kTripGoalPrefKey) ?? 10;
      if (mounted && v != _tripGoal) setState(() => _tripGoal = v);
    } catch (_) {}
  }

  Future<void> _saveTripGoal(int value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kTripGoalPrefKey, value);
    } catch (_) {}
  }

  void _syncErrorTrackerStep() {
    final isTrip = widget.mode == CounterMode.trip;
    MobileErrorScreenTracker.set(
      page: 'หน้าหลัก (แดชบอร์ด)',
      pageId: MobileScreenIds.pageDashboard,
      module: isTrip ? 'จำนวนเที่ยวรถ' : 'การร่อนทราย',
      stepId: isTrip
          ? MobileScreenIds.stepDashboardCountRecordTrip
          : MobileScreenIds.stepDashboardCountRecordSand,
    );
  }

  @override
  void didUpdateWidget(covariant CountRecordCounterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _syncErrorTrackerStep();
    }
    if (oldWidget.dateYmd != widget.dateYmd) {
      _units.clear();
      _hiddenDayTxIds.clear();
      unawaited(_initPanel());
      return;
    }
    if (_skipExternalDayTxReload > 0) {
      _skipExternalDayTxReload--;
      if (oldWidget.serverOnline != widget.serverOnline) {
        if (mounted) setState(() => _isOnline = widget.serverOnline);
        _syncDropdownRefreshTimer();
        if (widget.serverOnline) {
          unawaited(_handleParentOnlineTransition());
        } else {
          _syncOfflinePollTimer();
        }
      }
      unawaited(_refreshPendingCount());
      return;
    }
    if (!_sameCountRecordDay(
      oldWidget.dayTransactions,
      widget.dayTransactions,
      widget.dateYmd,
    )) {
      _pruneHiddenDayTxIds();
      if (_hasLocalOnlyTripUnits() || _hasLocalSandProgress()) {
        unawaited(_refreshPendingCount());
        return;
      }
      _units.clear();
      unawaited(_initPanel());
    } else if (oldWidget.serverOnline != widget.serverOnline) {
      if (mounted) setState(() => _isOnline = widget.serverOnline);
      _syncDropdownRefreshTimer();
      if (widget.serverOnline) {
        unawaited(_handleParentOnlineTransition());
      } else {
        _syncOfflinePollTimer();
      }
    } else if (oldWidget.dayTransactions != widget.dayTransactions) {
      // ข้อมูลชนิดของการ์ดนี้ไม่เปลี่ยน (เปลี่ยนแค่การ์ดอีกใบ) — อัปเดตเบา ๆ พอ
      unawaited(_refreshPendingCount());
    } else if (oldWidget.employees != widget.employees) {
      unawaited(_refreshDropdownLists(tryNetwork: false));
    }
  }

  bool _sameCountRecordDay(
    List<AppTransaction> a,
    List<AppTransaction> b,
    String ymd,
  ) {
    if (identical(a, b)) return true;
    // ดูเฉพาะชนิดข้อมูลของการ์ดนี้ — การ์ดร่อนทรายจะไม่ reload เมื่อแก้ข้อมูลเที่ยวรถ
    // และในทางกลับกัน (กันการ์ดอีกใบกระพริบ/รีเฟรชโดยไม่จำเป็น)
    final wantSub =
        widget.mode == CounterMode.trip ? 'vehicletrip' : 'sand';
    String fp(List<AppTransaction> txs) {
      final rows = txs
          .where(
            (t) =>
                t.date == ymd &&
                t.category == 'DailyLog' &&
                (t.subCategory ?? '').trim().toLowerCase() == wantSub,
          )
          .map(
            (t) {
              final laps = List<String>.from(
                t.workAssignments?['lapTimes'] ?? const [],
              );
              if (wantSub == 'vehicletrip') {
                final vid = (t.vehicleId ?? '').trim();
                return '$vid|${t.perCarTrips ?? t.tripCount ?? 0}|'
                    '${t.driverId ?? ''}|${laps.join(',')}';
              }
              return '${t.drumsObtained ?? 0}|${laps.join(',')}';
            },
          )
          .toList()
        ..sort();
      return rows.join(';');
    }

    return fp(a) == fp(b);
  }

  @override
  void dispose() {
    _offlineSyncTicker?.cancel();
    _dropdownRefreshTicker?.cancel();
    _parentRefreshDebounce?.cancel();
    super.dispose();
  }

  void _syncDropdownRefreshTimer() {
    _dropdownRefreshTicker?.cancel();
    final offline = !widget.serverOnline || !_isOnline;
    // รายชื่อรถ/คนขับแทบไม่เปลี่ยนระหว่างวัน — รีเฟรชห่างๆ พอ
    // (ตอนเปิด popup เพิ่มรถจะรีเฟรชสดผ่าน _ensureDropdownListsForDialog อยู่แล้ว)
    final interval = offline
        ? const Duration(seconds: 45)
        : const Duration(seconds: 90);
    _dropdownRefreshTicker = Timer.periodic(interval, (_) {
      if (!mounted) return;
      unawaited(
        _refreshDropdownLists(
          tryNetwork: widget.serverOnline || _isOnline,
        ),
      );
    });
  }

  void _armRecordCooldown(_CounterUnit u) {
    // การ์ดแต่ละใบนับถอยหลังเอง (_CardCooldownTicker) — ไม่ต้อง rebuild ทั้งแผง
    u.recordCooldownUntil = DateTime.now().add(_recordTapCooldown);
  }

  int _recentSandLapStartIndex(int total) {
    if (total <= _sandRecentLapsVisible) return 0;
    return total - _sandRecentLapsVisible;
  }

  void _bootstrapFromTransactions(List<AppTransaction> dayTx) {
    _applyDriverList(widget.employees);

    if (widget.mode == CounterMode.trip) {
      for (final t in dayTx) {
        if (t.category != 'DailyLog') continue;
        if ((t.subCategory ?? '').trim().toLowerCase() != 'vehicletrip') {
          continue;
        }
        final vid = (t.vehicleId ?? '').trim();
        if (vid.isEmpty || isMacroVehicleId(vid)) continue;
        _units.add(_unitFromTx(t, title: vid, vehicleId: vid));
      }
    } else {
      AppTransaction? sandRow;
      for (final t in dayTx) {
        if (t.category != 'DailyLog') continue;
        if ((t.subCategory ?? '').trim() != 'Sand') continue;
        if (t.description.contains('ทรายที่ล้างที่บ้าน')) continue;
        if (_sandRowIsEmpty(t)) continue;
        if (sandRow == null || _sandRowScore(t) > _sandRowScore(sandRow)) {
          sandRow = t;
        }
      }
      if (sandRow != null) {
        _units.add(
          _unitFromTx(
            sandRow,
            title: 'การร่อนทราย',
            roundsFromDrums: true,
          ),
        );
      } else {
        _units.add(
          _CounterUnit(
            txId: '${DateTime.now().millisecondsSinceEpoch}_sand',
            title: 'การร่อนทราย',
            subtitle: 'กดบันทึกเพื่อนับรอบ',
          ),
        );
      }
    }
  }

  Future<void> _initPanel() async {
    if (mounted) setState(() => _panelBootstrapping = true);
    // แสดงข้อมูลจากแคช/คิวในเครื่องทันที — งานเครือข่ายทำเบื้องหลังต่อ
    // (ไม่ให้ผู้ใช้เห็นหน้าว่าง/แถบโหลดระหว่างรอ probe หรืออัปโหลดคิว)
    await _refreshDropdownLists(tryNetwork: false);
    if (!mounted) return;
    final merged = await _mergedPanelDayRows();
    if (!mounted) return;
    setState(() {
      _panelBootstrapping = false;
      _units.clear();
      _bootstrapFromTransactions(merged);
      if (widget.mode == CounterMode.trip && _units.isEmpty) {
        _addVehiclePanelOpen = false;
      }
    });
    unawaited(_refreshPendingCount());
    unawaited(_backgroundPanelNetworkSync());
  }

  Future<void> _backgroundPanelNetworkSync() async {
    if (!widget.serverOnline) {
      if (mounted) setState(() => _isOnline = false);
      return;
    }
    await _refreshConnectivity(forceProbe: false);
    if (!mounted) return;
    if (_isOnline) {
      await _trySyncPending(silent: true);
    }
    if (!mounted) return;
    unawaited(
      _refreshDropdownLists(
        tryNetwork: widget.serverOnline || _isOnline,
      ),
    );
  }

  bool _sandRowIsEmpty(AppTransaction t) {
    final laps = List<String>.from(t.workAssignments?['lapTimes'] ?? const []);
    final drums = (t.drumsObtained ?? 0).round();
    return laps.isEmpty && drums <= 0;
  }

  int _sandRowScore(AppTransaction t) {
    final laps = List<String>.from(t.workAssignments?['lapTimes'] ?? const []);
    if (laps.isNotEmpty) return laps.length * 1000;
    return (t.drumsObtained ?? 0).round();
  }

  Future<List<AppTransaction>> _mergedPanelDayRows() {
    return CountRecordOfflineSync.instance.mergeForDayAsync(
      widget.dateYmd,
      _effectiveDayRows(),
    );
  }

  Future<void> _handleParentOnlineTransition() async {
    _syncDropdownRefreshTimer();
    unawaited(_refreshDropdownLists(tryNetwork: true));
    await _trySyncPending(silent: true);
  }

  void _applyDriverList(Iterable<Employee> source) {
    _drivers = source
        .where((e) => !e.inactive)
        .where(_isDriverEmployee)
        .toList(growable: false);
  }

  Future<void> _refreshDropdownLists({required bool tryNetwork}) async {
    final sync = CountRecordOfflineSync.instance;
    final catalog = await sync.loadDropdownCatalog(
      client: Supabase.instance.client,
      employeeService: widget.employeeService,
      widgetEmployees: widget.employees,
      serverOnlineHint: widget.serverOnline,
      forceNetwork: tryNetwork && (widget.serverOnline || _isOnline),
    );
    if (!mounted) return;
    final rawCars =
        catalog.cars.where(isVehicleTripDrumCarName).toList(growable: false);
    final cars = sortCountRecordVehicles(
      cars: rawCars,
      tripHistory: widget.tripHistoryTransactions,
    );
    setState(() {
      if (cars.isNotEmpty) _cars = cars;
      _applyDriverList(catalog.employees);
      if (catalog.vehicleDefaultDrivers.isNotEmpty) {
        _vehicleDefaultDrivers = catalog.vehicleDefaultDrivers;
      }
    });
  }

  /// เติมรายการจากแคชก่อนเปิด dialog — รอเครือข่ายเฉพาะเมื่อแคชว่าง
  Future<bool> _ensureDropdownListsForDialog({
    required bool needCars,
    required bool needDrivers,
  }) async {
    if ((needCars && _cars.isEmpty) || (needDrivers && _drivers.isEmpty)) {
      await _refreshDropdownLists(tryNetwork: false);
    }
    if (!mounted) return false;

    final hasCars = !needCars || _cars.isNotEmpty;
    final hasDrivers = !needDrivers || _drivers.isNotEmpty;
    if (hasCars && hasDrivers) {
      unawaited(_refreshDropdownLists(tryNetwork: true));
      return true;
    }

    await _refreshDropdownLists(tryNetwork: true);
    if (!mounted) return false;
    if (needCars && _cars.isEmpty) return false;
    if (needDrivers && _drivers.isEmpty) return false;
    return true;
  }

  Future<void> _refreshConnectivity({bool forceProbe = false}) async {
    if (!widget.serverOnline && !forceProbe) {
      if (mounted && _isOnline) setState(() => _isOnline = false);
      _syncOfflinePollTimer();
      return;
    }
    final wasOnline = _isOnline;
    final online = await CountRecordOfflineSync.instance.isOnline(
      Supabase.instance.client,
      forceProbe: forceProbe,
    );
    if (mounted) setState(() => _isOnline = online);
    if (online) {
      CountRecordOfflineSync.instance.noteServerReachable();
    }
    if (online && (!wasOnline || _pendingCount > 0)) {
      await _trySyncPending(silent: wasOnline);
      _syncDropdownRefreshTimer();
    }
    _syncOfflinePollTimer();
  }

  void _notifyParentDataChanged({bool shieldPanelReload = false}) {
    if (shieldPanelReload) {
      _skipExternalDayTxReload++;
    }
    _parentRefreshDebounce?.cancel();
    _parentRefreshDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      widget.onDataChanged?.call();
    });
  }

  void _syncOfflinePollTimer() {
    if (_pendingCount > 0 || !_isOnline) {
      _offlineSyncTicker ??= Timer.periodic(
        const Duration(seconds: 5),
        (_) {
          if (!mounted) return;
          unawaited(_pollOfflineQueue());
        },
      );
    } else {
      _offlineSyncTicker?.cancel();
      _offlineSyncTicker = null;
    }
  }

  Future<void> _pollOfflineQueue() async {
    await _refreshConnectivity();
  }

  Future<void> _refreshPendingCount() async {
    final count = await CountRecordOfflineSync.instance.pendingCount();
    if (mounted) {
      setState(() => _pendingCount = count);
      _syncOfflinePollTimer();
    }
  }

  Future<void> _trySyncPending({bool silent = false}) async {
    final synced = await CountRecordOfflineSync.instance.uploadPendingImmediately(
      widget.service,
      Supabase.instance.client,
    );
    if (synced > 0) {
      if (!silent && mounted) {
        _toast('อัปโหลดข้อมูล $synced รายการเข้าระบบแล้ว');
      }
      if (!mounted) return;
      if (_skipExternalDayTxReload > 0 || _shouldPreserveLocalPanelState()) {
        widget.onDataChanged?.call();
        await _refreshPendingCount();
        return;
      }
      widget.onDataChanged?.call();
      final merged = await _mergedPanelDayRows();
      if (!mounted) return;
      _applyMergedInPlace(merged);
    }
    await _refreshPendingCount();
    final online = await CountRecordOfflineSync.instance.isOnline(
      Supabase.instance.client,
      forceProbe: true,
    );
    if (mounted) setState(() => _isOnline = online);
    if (online) {
      CountRecordOfflineSync.instance.noteServerReachable();
    }
    _syncOfflinePollTimer();
  }

  List<AppTransaction> _effectiveDayRows() {
    final base = widget.dayTransactions
        .where((t) => t.date == widget.dateYmd)
        .toList();
    final byId = {for (final t in base) t.id: t};
    for (final id in _hiddenDayTxIds) {
      byId.remove(id);
    }
    for (final u in _units) {
      final empty = u.rounds <= 0 && u.lapTimes.isEmpty;
      if (empty) {
        if (u.txId.isNotEmpty) byId.remove(u.txId);
        continue;
      }
      byId[u.txId] = _txFor(u);
    }
    return byId.values.toList();
  }

  void _pruneHiddenDayTxIds() {
    _hiddenDayTxIds.removeWhere(
      (id) => !widget.dayTransactions.any(
        (t) => t.id == id && t.date == widget.dateYmd,
      ),
    );
  }

  bool _unitIsEmpty(_CounterUnit u) => u.rounds <= 0 && u.lapTimes.isEmpty;

  bool _hasLocalOnlyTripUnits() {
    if (widget.mode != CounterMode.trip) return false;
    return _units.any(
      (u) =>
          (u.vehicleId ?? '').trim().isNotEmpty &&
          (!u.persisted || _unitIsEmpty(u)),
    );
  }

  bool _hasLocalSandProgress() {
    if (widget.mode != CounterMode.sand) return false;
    final u = _sandUnit;
    if (u == null) return false;
    return u.rounds > 0 || u.lapTimes.isNotEmpty;
  }

  bool _shouldPreserveLocalPanelState() =>
      _hasLocalOnlyTripUnits() || _hasLocalSandProgress();

  void _applyMergedInPlace(List<AppTransaction> merged) {
    if (_units.isEmpty) {
      setState(() => _bootstrapFromTransactions(merged));
      return;
    }
    if (widget.mode == CounterMode.trip) {
      for (final u in _units) {
        if (u.busy) continue;
        final vid = (u.vehicleId ?? '').trim();
        if (vid.isEmpty) continue;
        AppTransaction? match;
        for (final t in merged) {
          if (t.category != 'DailyLog') continue;
          if ((t.subCategory ?? '').trim().toLowerCase() != 'vehicletrip') {
            continue;
          }
          if ((t.vehicleId ?? '').trim() == vid) {
            match = t;
            break;
          }
        }
        if (match == null) continue;
        final fresh = _unitFromTx(match, title: u.title, vehicleId: vid);
        u.txId = fresh.txId;
        u.rounds = fresh.rounds;
        u.lapTimes
          ..clear()
          ..addAll(fresh.lapTimes);
        u.driverId = fresh.driverId;
        u.subtitle = fresh.subtitle;
        u.workDetails = fresh.workDetails;
        u.persisted = fresh.persisted;
      }
      setState(() {});
      return;
    }
    final u = _sandUnit;
    if (u == null || u.busy) {
      setState(() {});
      return;
    }
    AppTransaction? sandRow;
    for (final t in merged) {
      if (t.category != 'DailyLog') continue;
      if ((t.subCategory ?? '').trim() != 'Sand') continue;
      if (t.description.contains('ทรายที่ล้างที่บ้าน')) continue;
      if (_sandRowIsEmpty(t)) continue;
      if (sandRow == null || _sandRowScore(t) > _sandRowScore(sandRow)) {
        sandRow = t;
      }
    }
    if (sandRow != null) {
      final fresh = _unitFromTx(
        sandRow,
        title: u.title,
        roundsFromDrums: true,
      );
      u.txId = fresh.txId;
      u.rounds = fresh.rounds;
      u.lapTimes
        ..clear()
        ..addAll(fresh.lapTimes);
      u.persisted = fresh.persisted;
    }
    setState(() {});
  }

  _CounterUnit _unitFromTx(
    AppTransaction t, {
    required String title,
    String? vehicleId,
    bool roundsFromDrums = false,
  }) {
    final wa = t.workAssignments ?? const <String, List<String>>{};
    final laps = List<String>.from(wa['lapTimes'] ?? const []);
    final int rounds;
    if (roundsFromDrums) {
      final fromDrums = (t.drumsObtained ?? 0).round();
      if (laps.isNotEmpty) {
        rounds = laps.length > fromDrums ? laps.length : fromDrums;
      } else {
        rounds = fromDrums;
      }
    } else {
      var tripRounds = (t.perCarTrips ?? t.tripCount ?? 0).round();
      if (laps.length > tripRounds) tripRounds = laps.length;
      rounds = tripRounds;
    }
    return _CounterUnit(
      txId: t.id,
      title: title,
      subtitle: vehicleId != null
          ? 'คนขับ: ${_driverLabel((t.driverId ?? '').trim())}'
          : 'กดบันทึกเพื่อนับรอบ',
      rounds: rounds,
      lapTimes: laps,
      persisted: true,
      vehicleId: vehicleId,
      driverId: (t.driverId ?? '').trim().isEmpty
          ? null
          : (t.driverId ?? '').trim(),
      workDetails: (t.workDetails ?? '').trim(),
    );
  }

  Iterable<String> _positionTokens(Employee e) sync* {
    if (e.positions.isNotEmpty) {
      for (final p in e.positions) {
        final t = p.trim();
        if (t.isNotEmpty) yield t;
      }
      return;
    }
    final single = (e.position ?? '').trim();
    if (single.isNotEmpty) yield single;
  }

  bool _isDriverEmployee(Employee e) =>
      _positionTokens(e).contains('คนขับรถ');

  String _driverLabel(String id) {
    if (id.trim().isEmpty) return 'ยังไม่ระบุ';
    for (final e in _drivers) {
      if (e.id == id) return e.nickname.isNotEmpty ? e.nickname : e.name;
    }
    return id;
  }

  /// บันทึกวันที่+เวลาแบบ dd/MM HH:mm:ss
  String _stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  AppTransaction _txFor(_CounterUnit u) {
    final laps = List<String>.from(u.lapTimes);
    final Map<String, List<String>>? assignments = laps.isEmpty
        ? null
        : <String, List<String>>{'lapTimes': laps};
    if (widget.mode == CounterMode.trip) {
      final r = u.rounds.toDouble();
      return AppTransaction(
        id: u.txId,
        date: widget.dateYmd,
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'VehicleTrip',
        description: '${u.vehicleId}: ${u.rounds} เที่ยว',
        amount: 0,
        note: 'นับเที่ยวโดย ${widget.currentAdmin.displayName}',
        vehicleId: u.vehicleId,
        driverId: u.driverId,
        workDetails: u.workDetails.trim().isEmpty ? null : u.workDetails.trim(),
        tripBillingMode: 'PerTrip',
        tripCount: r,
        perCarTrips: r,
        workAssignments: assignments,
      );
    }
    return AppTransaction(
      id: u.txId,
      date: widget.dateYmd,
      type: 'Expense',
      category: 'DailyLog',
      subCategory: 'Sand',
      description: 'ร่อนทราย: ${u.rounds} รอบ',
      amount: 0,
      note: 'ร่อนทรายโดย ${widget.currentAdmin.displayName}',
      drumsObtained: u.rounds.toDouble(),
      workAssignments: assignments,
    );
  }

  Future<bool> _save(
    _CounterUnit u, {
    bool notifyParent = true,
  }) async {
    if (_unitIsEmpty(u)) {
      await _deleteUnitRecord(u, notifyParent: notifyParent);
      return false;
    }
    final wasPersisted = u.persisted;
    final queued = await CountRecordOfflineSync.instance.persist(
      service: widget.service,
      client: Supabase.instance.client,
      transaction: _txFor(u),
      omitCreatedAt: wasPersisted,
      dayServerRows: _effectiveDayRows(),
      serverOnlineHint: _isOnline,
    );
    u.persisted = true;
    await _refreshPendingCount();
    if (notifyParent) {
      _notifyParentDataChanged(shieldPanelReload: true);
    }
    unawaited(_refreshConnectivity(forceProbe: false));
    return queued;
  }

  Future<void> _deleteUnitRecord(
    _CounterUnit u, {
    bool notifyParent = true,
  }) async {
    final oldId = u.txId;
    if (u.persisted && oldId.isNotEmpty) {
      await CountRecordOfflineSync.instance.delete(
        service: widget.service,
        client: Supabase.instance.client,
        id: oldId,
        ymd: widget.dateYmd,
        dayServerRows: _effectiveDayRows(),
        serverOnlineHint: _isOnline,
      );
      _hiddenDayTxIds.add(oldId);
    }
    u.persisted = false;
    u.rounds = 0;
    u.lapTimes.clear();
    if (widget.mode == CounterMode.sand && mounted) {
      final idx = _units.indexOf(u);
      if (idx >= 0) {
        setState(() {
          _units[idx] = _CounterUnit(
            txId: '${DateTime.now().millisecondsSinceEpoch}_sand',
            title: u.title,
            subtitle: u.subtitle,
          );
        });
      }
    }
    await _refreshPendingCount();
    if (notifyParent) {
      _notifyParentDataChanged(shieldPanelReload: true);
    }
  }

  /// กดปุ่ม = บันทึกวันเวลา + เพิ่มจำนวน 1 (จำกัด 1 ครั้งทุก 3 วินาทีต่อปุ่ม)
  Future<void> _recordTap(_CounterUnit u) async {
    if (u.busy) return;
    if (u.isOnRecordCooldown) return;
    if (widget.mode == CounterMode.trip && u.isBrokenReported) return;
    final prevRounds = u.rounds;
    final prevLaps = List<String>.from(u.lapTimes);
    final prevCombo = u.comboCount;
    final prevLastRecordAt = u.lastRecordAt;
    final now = DateTime.now();
    final stamp = _stamp(now);
    _armRecordCooldown(u);
    _skipExternalDayTxReload++;
    final lastAt = u.lastRecordAt;
    final keepsCombo =
        lastAt != null && now.difference(lastAt) <= const Duration(seconds: 10);
    setState(() {
      u.lapTimes.add(stamp);
      u.rounds = u.lapTimes.length > u.rounds ? u.lapTimes.length : u.rounds + 1;
      u.burstTick++;
      u.comboCount = keepsCombo ? u.comboCount + 1 : 1;
      u.lastRecordAt = now;
    });
    unawaited(RecordFeedbackSound.playRecordTap());
    try {
      final queued = await _save(u);
      if (mounted) {
        AppHaptics.success();
        unawaited(RecordSuccessSpeaker.instance.speakSuccess());
        final reachedGoal = widget.mode == CounterMode.trip &&
            _tripGoal > 0 &&
            u.rounds == _tripGoal;
        if (reachedGoal) {
          AppHaptics.warn();
          _toast('${u.title} ครบเป้า $_tripGoal เที่ยวแล้ว!');
        } else {
          _showRecordSnackBar(u, stamp, queued: queued);
        }
      }
    } catch (e) {
      if (mounted) {
        if (_skipExternalDayTxReload > 0) _skipExternalDayTxReload--;
        setState(() {
          u.rounds = prevRounds;
          u.lapTimes
            ..clear()
            ..addAll(prevLaps);
          if (u.burstTick > 0) u.burstTick--;
          u.comboCount = prevCombo;
          u.lastRecordAt = prevLastRecordAt;
        });
        _toast('บันทึกไม่สำเร็จ: $e', error: true);
      }
    }
  }

  Future<void> _confirmUndoLastRecord(_CounterUnit u) async {
    final isTrip = widget.mode == CounterMode.trip;
    if (u.busy || u.rounds <= 0 || u.lapTimes.isEmpty) {
      if (u.rounds <= 0) {
        _toast(isTrip ? 'ยังไม่มีเที่ยวให้ลบ' : 'ยังไม่มีรอบให้ลบ', error: true);
      }
      return;
    }
    final lastStamp = u.lapTimes.last;
    final recordNo = u.rounds;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(isTrip ? 'ลบเที่ยวล่าสุด?' : 'ลบรอบล่าสุด?'),
        content: Text(
          isTrip
              ? 'ลบเที่ยวที่ $recordNo ของ "${u.title}"\n'
                  'เวลา $lastStamp\n\n'
                  'ข้อมูลนี้จะถูกลบออกจากบันทึกวันนี้'
              : 'ลบรอบที่ $recordNo\n'
                  'เวลา $lastStamp\n\n'
                  'ข้อมูลนี้จะถูกลบออกจากบันทึกวันนี้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD14343),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ยืนยันลบ'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) await _undoRecordAt(u, u.lapTimes.length - 1);
  }

  Future<void> _confirmUndoSandRoundAt(_CounterUnit u, int lapIndex) async {
    if (u.busy || lapIndex < 0 || lapIndex >= u.lapTimes.length) return;
    final stamp = u.lapTimes[lapIndex];
    final roundNo = lapIndex + 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('ลบรอบที่ $roundNo?'),
        content: Text(
          'เวลา $stamp\n\n'
          'ข้อมูลนี้จะถูกลบออกจากบันทึกวันนี้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD14343),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ยืนยันลบ'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) await _undoRecordAt(u, lapIndex);
  }

  Future<void> _undoRecordAt(_CounterUnit u, int lapIndex) async {
    if (u.busy || lapIndex < 0 || lapIndex >= u.lapTimes.length) return;
    if (!mounted) return;
    final isTrip = widget.mode == CounterMode.trip;
    final prevRounds = u.rounds;
    final prevLaps = List<String>.from(u.lapTimes);
    final removedStamp = u.lapTimes[lapIndex];
    // อัปเดตหน้าจอทันที (ไม่ขึ้นสปินเนอร์) แล้วค่อยบันทึกเบื้องหลัง
    setState(() {
      u.lapTimes.removeAt(lapIndex);
      u.rounds = u.lapTimes.isEmpty
          ? 0
          : (u.rounds > u.lapTimes.length ? u.rounds - 1 : u.lapTimes.length);
    });
    if (mounted) {
      _toast(
        isTrip
            ? 'ลบเที่ยวล่าสุดแล้ว • $removedStamp'
            : 'ลบรอบที่ ${lapIndex + 1} แล้ว • $removedStamp',
      );
    }
    try {
      await _save(u, notifyParent: false);
      _notifyParentDataChanged(shieldPanelReload: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          u.rounds = prevRounds;
          u.lapTimes
            ..clear()
            ..addAll(prevLaps);
        });
        _toast('ลบไม่สำเร็จ: $e', error: true);
      }
    }
  }

  Future<void> _confirmRemoveUnit(_CounterUnit u) async {
    if (u.busy) return;
    final tripInfo = u.rounds > 0 ? '\n(มี ${u.rounds} เที่ยวที่บันทึกไว้)' : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('ลบรถออกจากรายการ?'),
        content: Text(
          'ลบ "${u.title}" และข้อมูลเที่ยวทั้งหมดของวันนี้ใช่หรือไม่?$tripInfo',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD14343),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ยืนยันลบ'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) await _removeUnit(u);
  }

  Future<void> _removeUnit(_CounterUnit u) async {
    if (u.busy) return;
    if (!mounted) return;
    setState(() => u.busy = true);
    try {
      var queued = false;
      if (u.persisted) {
        final oldId = u.txId;
        queued = await CountRecordOfflineSync.instance.delete(
          service: widget.service,
          client: Supabase.instance.client,
          id: oldId,
          ymd: widget.dateYmd,
          dayServerRows: _effectiveDayRows(),
          serverOnlineHint: _isOnline,
        );
        if (oldId.isNotEmpty) _hiddenDayTxIds.add(oldId);
        await _refreshConnectivity();
        await _refreshPendingCount();
        _notifyParentDataChanged(shieldPanelReload: true);
      }
      if (mounted) {
        setState(() => _units.remove(u));
        _toast(
          queued
              ? 'ลบ ${u.title} ออฟไลน์ — จะซิงค์เมื่อมีเน็ต'
              : 'ลบ ${u.title} ออกจากรายการแล้ว',
        );
      }
    } catch (e) {
      _toast('ลบไม่สำเร็จ: $e', error: true);
    } finally {
      if (mounted && _units.contains(u)) setState(() => u.busy = false);
    }
  }

  Future<void> _openSelectDialog() async {
    final ready = await _ensureDropdownListsForDialog(
      needCars: true,
      needDrivers: false,
    );
    if (!ready || !mounted) {
      if (mounted && _cars.isEmpty) {
        _toast('ยังไม่พบรายการรถ (ดรัม/หกล้อ/สิบล้อ) ในตั้งค่าแอพ', error: true);
      }
      return;
    }
    final already = _units
        .map((u) => u.vehicleId ?? '')
        .where((v) => v.isNotEmpty)
        .toSet();
    final picks = await showDialog<List<_Pick>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SelectDialog(
        cars: sortCountRecordVehicles(
          cars: _cars,
          tripHistory: widget.tripHistoryTransactions,
        ),
        drivers: _drivers,
        alreadyAdded: already,
        tripHistory: widget.tripHistoryTransactions,
        vehicleDefaultDrivers: _vehicleDefaultDrivers,
      ),
    );
    if (picks == null || !mounted) return;
    for (final p in picks) {
      final vid = p.vehicleId.trim();
      if (vid.isEmpty) continue;
      if (_units.any((u) => u.vehicleId == vid)) continue;
      final unit = _CounterUnit(
        txId: '${DateTime.now().millisecondsSinceEpoch}_'
            '${vid.hashCode.toUnsigned(20)}',
        title: vid,
        subtitle: 'คนขับ: ${_driverLabel(p.driverId.trim())}',
        vehicleId: vid,
        driverId: p.driverId.trim().isEmpty ? null : p.driverId.trim(),
      );
      if (!mounted) continue;
      setState(() => _units.add(unit));
    }
  }

  Future<void> _openEditUnitMenu(_CounterUnit u) async {
    if (u.busy) return;
    final action = await showDialog<_UnitEditAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('แก้ไขข้อมูล — ${u.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.badge_outlined, color: Color(0xFF1565C0)),
              title: const Text(
                'แก้ไขคนขับ',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                u.subtitle,
                style: const TextStyle(fontSize: 12.5),
              ),
              onTap: () =>
                  Navigator.pop(ctx, _UnitEditAction.changeDriver),
            ),
            const Divider(height: 1),
            if (u.isBrokenReported)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.check_circle_outline,
                  color: Color(0xFF2E7D32),
                ),
                title: const Text(
                  'ปรับสถานะรถปกติ',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'รถพร้อมใช้งาน — เปิดบันทึกเที่ยวต่อ',
                  style: TextStyle(fontSize: 12.5),
                ),
                onTap: () =>
                    Navigator.pop(ctx, _UnitEditAction.restoreNormal),
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.car_crash_outlined,
                  color: Color(0xFFE65100),
                ),
                title: const Text(
                  'แจ้งรถเสีย',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'บันทึกสถานะรถเสียลงระบบ',
                  style: TextStyle(fontSize: 12.5),
                ),
                onTap: () =>
                    Navigator.pop(ctx, _UnitEditAction.reportBroken),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _UnitEditAction.changeDriver:
        await _openChangeDriverDialog(u);
      case _UnitEditAction.reportBroken:
        await _confirmReportBrokenVehicle(u);
      case _UnitEditAction.restoreNormal:
        await _confirmRestoreVehicleNormal(u);
    }
  }

  Future<void> _openChangeDriverDialog(_CounterUnit u) async {
    final ready = await _ensureDropdownListsForDialog(
      needCars: false,
      needDrivers: true,
    );
    if (!ready || !mounted) {
      if (mounted && _drivers.isEmpty) {
        _toast('ยังไม่พบพนักงานตำแหน่ง "คนขับรถ"', error: true);
      }
      return;
    }
    final driverId = await showDialog<String>(
      context: context,
      builder: (ctx) => _ChangeDriverDialog(
        vehicleTitle: u.title,
        initialDriverId: u.driverId ?? '',
        drivers: _drivers,
      ),
    );
    if (driverId == null || !mounted) return;
    final did = driverId.trim();
    if (did.isEmpty) return;

    final prevDriverId = u.driverId;
    final prevSubtitle = u.subtitle;
    setState(() {
      u.busy = true;
      u.driverId = did;
      u.subtitle = 'คนขับ: ${_driverLabel(did)}';
    });
    try {
      await _save(u);
      if (mounted) _toast('แก้ไขคนขับ ${u.title} แล้ว');
    } catch (e) {
      if (mounted) {
        setState(() {
          u.driverId = prevDriverId;
          u.subtitle = prevSubtitle;
        });
        _toast('แก้ไขไม่สำเร็จ: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => u.busy = false);
    }
  }

  Future<void> _confirmReportBrokenVehicle(_CounterUnit u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('แจ้งรถเสีย?'),
        content: Text(
          'บันทึกสถานะรถเสียสำหรับ "${u.title}" วันนี้ใช่หรือไม่?\n'
          'ข้อมูลจะถูกเก็บในรายละเอียดงานของคันนี้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE65100),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ยืนยันแจ้ง'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final stamp = _stamp(DateTime.now());
    final tag = 'รถเสีย $stamp';
    final prevDetails = u.workDetails;
    setState(() {
      u.busy = true;
      u.workDetails =
          prevDetails.isEmpty ? tag : '$prevDetails, $tag';
    });
    try {
      await _save(u);
      unawaited(_logVehicleStatusEvent(u, broken: true, stamp: stamp));
      if (mounted) _toast('แจ้งรถเสีย ${u.title} แล้ว');
    } catch (e) {
      if (mounted) {
        setState(() => u.workDetails = prevDetails);
        _toast('บันทึกไม่สำเร็จ: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => u.busy = false);
    }
  }

  /// บันทึกเหตุการณ์ประจำวัน (DailyLog + Event) เมื่อแจ้งรถเสีย/รถกลับมาปกติ
  /// ทำงานเบื้องหลัง รองรับออฟไลน์ (เข้าคิวซิงค์อัตโนมัติ)
  Future<void> _logVehicleStatusEvent(
    _CounterUnit u, {
    required bool broken,
    required String stamp,
  }) async {
    final driver = (u.driverId ?? '').trim().isEmpty
        ? ''
        : ' • คนขับ ${_driverLabel((u.driverId ?? '').trim())}';
    final admin = widget.currentAdmin.displayName;
    final desc = broken
        ? 'แจ้งรถเสีย: ${u.title}$driver • เวลา $stamp (บันทึกโดย $admin)'
        : 'รถกลับมาใช้งานปกติ: ${u.title}$driver • เวลา $stamp '
            '(บันทึกโดย $admin)';
    final event = AppTransaction(
      id: '${DateTime.now().millisecondsSinceEpoch}_vehstatus',
      date: widget.dateYmd,
      type: 'Expense',
      category: 'DailyLog',
      subCategory: 'Event',
      description: desc,
      amount: 0,
      note: 'บันทึกอัตโนมัติจากเมนูบันทึกและนับจำนวน',
      eventType: broken ? 'problem' : 'success',
      eventPriority: broken ? 'urgent' : 'normal',
    );
    try {
      await CountRecordOfflineSync.instance.persist(
        service: widget.service,
        client: Supabase.instance.client,
        transaction: event,
        omitCreatedAt: false,
        dayServerRows: _effectiveDayRows(),
        serverOnlineHint: _isOnline,
      );
      if (!mounted) return;
      await _refreshPendingCount();
      _notifyParentDataChanged(shieldPanelReload: true);
    } catch (e) {
      debugPrint('logVehicleStatusEvent failed: $e');
    }
  }

  Future<void> _confirmRestoreVehicleNormal(_CounterUnit u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('ปรับสถานะรถปกติ?'),
        content: Text(
          'ยืนยันว่า "${u.title}" กลับมาใช้งานได้แล้วใช่หรือไม่?\n'
          'จะเปิดปุ่มบันทึกเที่ยวให้อีกครั้ง',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final stamp = _stamp(DateTime.now());
    final tag = 'รถปกติ $stamp';
    final prevDetails = u.workDetails;
    setState(() {
      u.busy = true;
      u.workDetails =
          prevDetails.isEmpty ? tag : '$prevDetails, $tag';
    });
    try {
      await _save(u);
      unawaited(_logVehicleStatusEvent(u, broken: false, stamp: stamp));
      if (mounted) {
        _toast('ปรับสถานะรถปกติแล้ว — พร้อมบันทึกเที่ยวต่อ');
      }
    } catch (e) {
      if (mounted) {
        setState(() => u.workDetails = prevDetails);
        _toast('บันทึกไม่สำเร็จ: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => u.busy = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            error ? const Color(0xFFC62828) : const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Snackbar หลังบันทึกสำเร็จ — มีปุ่ม «เลิกทำ» ย้อนรายการล่าสุดได้ทันที (Gmail-style)
  void _showRecordSnackBar(_CounterUnit u, String stamp, {required bool queued}) {
    if (!mounted) return;
    final isTrip = widget.mode == CounterMode.trip;
    final base = isTrip
        ? '${u.title} • เที่ยวที่ ${u.rounds} • $stamp'
        : 'รอบที่ ${u.rounds} • $stamp';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            queued ? '$base\n(บันทึกในเครื่อง — จะอัปโหลดเมื่อมีเน็ต)' : base,
          ),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'เลิกทำ',
            textColor: const Color(0xFFFFE082),
            onPressed: () {
              final idx = u.lapTimes.lastIndexOf(stamp);
              if (idx >= 0) unawaited(_undoRecordAt(u, idx));
            },
          ),
        ),
      );
  }

  /// รวมยอดทั้งวันจากทุกหน่วยนับ แยกช่วงเช้า (ก่อน 12:00) / บ่าย
  ({int total, int morning, int afternoon}) _panelPeriodTotals() {
    var total = 0;
    var morning = 0;
    var afternoon = 0;
    for (final u in _units) {
      total += u.rounds;
      for (final lap in u.lapTimes) {
        final h = _lapHourOf(lap);
        if (h != null && h >= 12) {
          afternoon++;
        } else {
          morning++;
        }
      }
      // แถวที่มี rounds มากกว่า lapTimes (ข้อมูลเก่า) นับส่วนเกินเป็นช่วงเช้า
      final extra = u.rounds - u.lapTimes.length;
      if (extra > 0) morning += extra;
    }
    return (total: total, morning: morning, afternoon: afternoon);
  }

  Future<void> _openTripGoalDialog() async {
    var draft = _tripGoal;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('เป้าหมายเที่ยวต่อคัน'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    onPressed: draft > 0
                        ? () => setDialogState(() => draft--)
                        : null,
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      draft == 0 ? 'ปิด' : '$draft',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: draft < 99
                        ? () => setDialogState(() => draft++)
                        : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                draft == 0
                    ? 'ไม่แสดงเป้าหมายบนการ์ดรถ'
                    : 'ครบ $draft เที่ยว/คัน = ถึงเป้า มีฉลองพิเศษ',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF78909C)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, draft),
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _tripGoal = result);
    unawaited(_saveTripGoal(result));
  }

  /// แชร์สรุปประจำวันเป็นรูปภาพ — เปิด sheet พรีวิวการ์ดแล้วกดแชร์
  Future<void> _openShareSummarySheet() async {
    AppHaptics.tap();
    final isTrip = widget.mode == CounterMode.trip;
    final totals = _panelPeriodTotals();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'แชร์สรุปประจำวัน',
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A2433),
                    ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: RepaintBoundary(
                    key: _shareCardKey,
                    child: _DailyShareCard(
                      isTrip: isTrip,
                      dateYmd: widget.dateYmd,
                      units: _units,
                      totals: totals,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0D98A5),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                onPressed: () => _shareSummaryImage(ctx),
                icon: const Icon(Icons.ios_share_rounded, size: 20),
                label: const Text(
                  'แชร์รูปสรุป',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareSummaryImage(BuildContext sheetContext) async {
    try {
      final boundary = _shareCardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/count_summary_${widget.dateYmd}_${widget.mode.name}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
      );
      if (sheetContext.mounted) Navigator.pop(sheetContext);
    } catch (e) {
      _toast('แชร์ไม่สำเร็จ: $e', error: true);
    }
  }

  void _toggleAddVehiclePanel() {
    AppHaptics.confirm();
    if (_units.isEmpty) {
      unawaited(_openSelectDialog());
      return;
    }
    setState(() => _addVehiclePanelOpen = !_addVehiclePanelOpen);
  }

  void _hideAddVehiclePanel() {
    if (!_addVehiclePanelOpen) return;
    setState(() => _addVehiclePanelOpen = false);
  }

  Widget _tripVehicleCard(int index, {required bool compact}) {
    final unit = _units[index];
    return _SwipeRevealActions(
      onDelete: () => _confirmRemoveUnit(unit),
      onEdit: () => _openEditUnitMenu(unit),
      childBuilder: (interactionsEnabled, setHoldLock) => _VehicleRecordButton(
        unit: unit,
        index: index,
        compact: compact,
        goal: _tripGoal,
        interactionsEnabled: interactionsEnabled,
        setHoldLock: setHoldLock,
        onTap: () => _recordTap(unit),
        onHoldToUndo: () => _confirmUndoLastRecord(unit),
      ),
    );
  }

  /// 1–2 คัน: แถวเดียวเต็มความกว้าง | 3+ คัน: กริดปรับจำนวนคอลัมน์อัตโนมัติ
  /// ให้เห็นทุกการ์ดพร้อมกัน — เลื่อนเฉพาะเมื่อย่อสุดแล้วพื้นที่ยังไม่พอจริงๆ
  static const _tripGridRowHeight = 116.0;
  static const _tripGridRowGap = 8.0;
  static const _tripGridMinRowHeight = 56.0;

  Widget _buildTripVehicleScrollableGrid(int rowCount, {required int cols}) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      itemCount: rowCount,
      separatorBuilder: (_, _) => const SizedBox(height: _tripGridRowGap),
      itemBuilder: (context, row) {
        return SizedBox(
          height: _tripGridRowHeight,
          child: _buildTripVehicleGridRow(row * cols, cols: cols),
        );
      },
    );
  }

  Widget _buildTripVehicleCards() {
    if (_units.length <= 2) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // โหมดเต็มต้องการความสูง ~145px+ — แคบกว่านี้ใช้ compact
          final useCompact = constraints.maxHeight < 145;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _units.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _tripVehicleCard(i, compact: useCompact),
                ),
              ],
            ],
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final maxCols = constraints.maxWidth >= 520 ? 4 : 3;

        int rowsFor(int cols) => (_units.length + cols - 1) ~/ cols;
        double rowHeightFor(int cols) {
          final rows = rowsFor(cols);
          return (h - _tripGridRowGap * (rows - 1)) / rows;
        }

        var cols = 2;
        if (h.isFinite) {
          // เพิ่มคอลัมน์เมื่อแถวเตี้ยเกินไป — เฉพาะเมื่อช่วยลดจำนวนแถวได้จริง
          while (cols < maxCols &&
              rowsFor(cols + 1) < rowsFor(cols) &&
              rowHeightFor(cols) < 100) {
            cols++;
          }
        }

        final rows = rowsFor(cols);
        if (!h.isFinite || rowHeightFor(cols) < _tripGridMinRowHeight) {
          return _buildTripVehicleScrollableGrid(rows, cols: cols);
        }

        final rowHeight = rowHeightFor(cols);
        return Column(
          children: [
            for (var row = 0; row < rows; row++) ...[
              if (row > 0) const SizedBox(height: _tripGridRowGap),
              SizedBox(
                height: rowHeight,
                child: _buildTripVehicleGridRow(row * cols, cols: cols),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildTripVehicleGridRow(int startIndex, {required int cols}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cols; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: startIndex + i < _units.length
                ? _tripVehicleCard(startIndex + i, compact: true)
                : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }

  Widget _buildTripPanel() {
    final totals = _panelPeriodTotals();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_units.isNotEmpty) ...[
            _CountStatsStrip(
              isTrip: true,
              totals: totals,
              goal: _tripGoal,
              onGoalTap: _openTripGoalDialog,
              onShareTap: _openShareSummarySheet,
            ),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: _units.isEmpty
                ? _FirstTripSetupCard(onTap: _openSelectDialog)
                : _buildTripVehicleCards(),
          ),
          const SizedBox(height: 8),
          _LatestTripRecordsBar(
            expanded: _addVehiclePanelOpen,
            units: _units,
            onTap: _toggleAddVehiclePanel,
          ),
          if (_addVehiclePanelOpen)
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1565C0),
                        backgroundColor: const Color(0xFFE3F2FD),
                        side: const BorderSide(
                          color: Color(0xFF90CAF9),
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        _openSelectDialog();
                        _hideAddVehiclePanel();
                      },
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text(
                        'เพิ่มรถเพิ่มเติม',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: _hideAddVehiclePanel,
                        child: const Text(
                          'ปิด',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF78909C),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSandPanel() {
    final u = _sandUnit;
    if (u == null) return const SizedBox.shrink();
    final showLapStrip = u.lapTimes.isNotEmpty;
    final totals = _panelPeriodTotals();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (u.rounds > 0) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
            child: _CountStatsStrip(
              isTrip: false,
              totals: totals,
              goal: 0,
              onShareTap: _openShareSummarySheet,
            ),
          ),
        ],
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _SandRecordButton(
                unit: u,
                showLatestLapInline: !showLapStrip,
                onTap: () => _recordTap(u),
                onHoldToUndo: () => _confirmUndoLastRecord(u),
              ),
              if (showLapStrip)
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 44),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var i =
                                  _recentSandLapStartIndex(u.lapTimes.length);
                              i < u.lapTimes.length;
                              i++)
                            _SandLapChip(
                              roundNo: i + 1,
                              stamp: u.lapTimes[i],
                              onLongPress: () => _confirmUndoSandRoundAt(u, i),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget? _buildSyncBanner() {
    final pending = _pendingCount;
    final uploading = CountRecordOfflineSync.instance.uploadInFlight;
    final offlineQueued = !widget.serverOnline || !_isOnline;
    // โหมดออฟไลน์ — ซ่อนแบนเนอร์ (จำนวนรอซิงก์แสดงที่หัวข้อ «บันทึกและนับจำนวน» แทน)
    if (offlineQueued) return null;
    if (pending == 0 && !uploading) return null;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _GameUploadBanner(
        key: ValueKey('upload_${offlineQueued}_$pending'),
        count: pending,
        offlineQueued: offlineQueued,
        syncing: uploading,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_panelBootstrapping) {
      return CountRecordPanelSkeleton(
        isTripMode: widget.mode == CounterMode.trip,
      );
    }
    final banner = _buildSyncBanner();
    final body = widget.mode == CounterMode.trip
        ? _buildTripPanel()
        : _buildSandPanel();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: banner ?? const SizedBox(width: double.infinity),
        ),
        Expanded(child: body),
      ],
    );
  }
}

/// แบนเนอร์อัปโหลดแบบเกม — โชว์ตอนออนไลน์แล้วมีคิวค้างรออัปโหลด
class _GameUploadBanner extends StatefulWidget {
  const _GameUploadBanner({
    super.key,
    required this.count,
    this.offlineQueued = false,
    this.syncing = false,
  });

  final int count;
  final bool offlineQueued;
  final bool syncing;

  @override
  State<_GameUploadBanner> createState() => _GameUploadBannerState();
}

class _GameUploadBannerState extends State<_GameUploadBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: DevicePerf.isConstrainedDevice ? 2200 : 1500,
      ),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradient = widget.offlineQueued
        ? const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFFF8F00), Color(0xFFFFB74D), Color(0xFFFFCC80)],
          )
        : const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF00BFA5), Color(0xFF1DE9B6), Color(0xFF00B0FF)],
          );
    final statusLabel = widget.offlineQueued
        ? (widget.count > 0
            ? 'บันทึกในเครื่อง ${widget.count} รายการ — จะซิงก์เมื่อมีเน็ต'
            : 'บันทึกในเครื่อง — รอซิงก์เมื่อมีเน็ต')
        : (widget.syncing && widget.count == 0
            ? 'กำลังซิงก์เข้าระบบ...'
            : 'กำลังอัปโหลด ${widget.count} รายการเข้าระบบ');
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00BFA5).withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          return Row(
            children: [
              _uploadIcon(t),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.bolt_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              shadows: [
                                Shadow(color: Colors.black26, blurRadius: 2),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _progressBar(t),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _uploadIcon(double t) {
    final bob = math.sin(t * math.pi * 2) * 2.5;
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < 3; i++) _risingParticle(t, i),
          Transform.translate(
            offset: Offset(0, bob),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.65),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.cloud_upload_rounded,
                size: 19,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _risingParticle(double t, int i) {
    final phase = (t + i / 3) % 1.0;
    final y = 15 - phase * 32;
    final fadeIn = phase < 0.15 ? phase / 0.15 : 1.0;
    final opacity = (1 - phase).clamp(0.0, 1.0) * fadeIn;
    final dx = (i - 1) * 6.5;
    return Transform.translate(
      offset: Offset(dx, y),
      child: Opacity(
        opacity: opacity.toDouble(),
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.8),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progressBar(double t) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 5,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final barW = w * 0.35;
            final x = -barW + (w + barW) * t;
            return Stack(
              children: [
                Container(color: Colors.white.withValues(alpha: 0.25)),
                Positioned(
                  left: x,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: barW,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white,
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// สีปุ่มบันทึกต่อคัน — แยกสีชัดเจนไม่ให้กดสับสน
const _kVehicleButtonColors = [
  Color(0xFF1565C0), // น้ำเงิน
  Color(0xFF2E7D32), // เขียว
  Color(0xFFE65100), // ส้ม
  Color(0xFF6A1B9A), // ม่วง
  Color(0xFF00838F), // ฟ้าเขียว
  Color(0xFFC62828), // แดง
  Color(0xFF4527A0), // ม่วงเข้ม
  Color(0xFF558B2F), // มะกอก
];

Color _vehicleButtonColor(int index) =>
    _kVehicleButtonColors[index % _kVehicleButtonColors.length];

/// ปัดการ์ดซ้าย = ลบ, ปัดขวา = แก้ไข
enum _SwipeRevealSide { none, delete, edit }

class _SwipeRevealActions extends StatefulWidget {
  const _SwipeRevealActions({
    required this.onDelete,
    required this.onEdit,
    required this.childBuilder,
  });

  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final Widget Function(
    bool interactionsEnabled,
    void Function(bool locked) setHoldLock,
  ) childBuilder;

  @override
  State<_SwipeRevealActions> createState() => _SwipeRevealActionsState();
}

class _SwipeRevealActionsState extends State<_SwipeRevealActions> {
  double _offset = 0;
  _SwipeRevealSide _revealed = _SwipeRevealSide.none;
  bool _dragging = false;
  double _actionWidth = 64;

  bool get _interactionsEnabled =>
      !_dragging && _revealed == _SwipeRevealSide.none;

  bool get _showEditAction =>
      _revealed == _SwipeRevealSide.edit ||
      (_dragging && _offset >= _actionWidth * 0.22);
  bool get _showDeleteAction =>
      _revealed == _SwipeRevealSide.delete ||
      (_dragging && _offset <= -_actionWidth * 0.22);

  void _setStateIfMounted(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  void _snap({required _SwipeRevealSide side}) {
    _setStateIfMounted(() {
      _revealed = side;
      _offset = switch (side) {
        _SwipeRevealSide.delete => -_actionWidth,
        _SwipeRevealSide.edit => _actionWidth,
        _ => 0.0,
      };
      _dragging = false;
    });
  }

  void _setHoldLock(bool locked) {
    // คงไว้เป็น callback ของตัวการ์ด แต่ไม่ทำอะไรกับสถานะปัดอีกต่อไป
    // (เดิมเคยสั่ง _snap(none) ทำให้ปุ่มลบ/แก้ไขที่ปัดเผยแล้วหายทันทีเมื่อปล่อยนิ้ว)
  }

  /// หลีกเลี่ยง setState บน ancestor ระหว่าง build (เช่น didUpdateWidget ของปุ่มลูก)
  void _deferHoldLock(bool locked) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setHoldLock(locked);
    });
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    // ปัดแนวนอน = ตั้งใจปัดการ์ด → เริ่มปัด
    _setStateIfMounted(() => _dragging = true);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!mounted) return;
    _setStateIfMounted(() {
      _offset = (_offset + details.delta.dx).clamp(-_actionWidth, _actionWidth);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!mounted) return;
    final velocity = details.primaryVelocity ?? 0;
    if (_offset <= -_actionWidth / 2 || velocity < -280) {
      _snap(side: _SwipeRevealSide.delete);
    } else if (_offset >= _actionWidth / 2 || velocity > 280) {
      _snap(side: _SwipeRevealSide.edit);
    } else {
      _snap(side: _SwipeRevealSide.none);
    }
  }

  void _onTap() {
    if (_revealed != _SwipeRevealSide.none) {
      _snap(side: _SwipeRevealSide.none);
    }
  }

  void _onDeleteTap() {
    _snap(side: _SwipeRevealSide.none);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onDelete();
    });
  }

  void _onEditTap() {
    _snap(side: _SwipeRevealSide.none);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onEdit();
    });
  }

  Widget _actionButton({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: _actionWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _actionWidth = (constraints.maxWidth * 0.36).clamp(52.0, 76.0);
        final offset = _offset.clamp(-_actionWidth, _actionWidth);
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    SizedBox(
                      width: _actionWidth,
                      child: ColoredBox(color: const Color(0xFF1565C0)),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: _actionWidth,
                      child: ColoredBox(color: const Color(0xFFD14343)),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onTap,
                onHorizontalDragStart: _onHorizontalDragStart,
                onHorizontalDragUpdate: _onHorizontalDragUpdate,
                onHorizontalDragEnd: _onHorizontalDragEnd,
                child: AnimatedContainer(
                  duration: _dragging
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(offset, 0, 0),
                  child: IgnorePointer(
                    ignoring: !_interactionsEnabled,
                    child: widget.childBuilder(
                      _interactionsEnabled,
                      _deferHoldLock,
                    ),
                  ),
                ),
              ),
              if (_showEditAction)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _actionWidth,
                  child: _actionButton(
                    color: const Color(0xFF1565C0),
                    icon: Icons.edit_outlined,
                    label: 'แก้ไข',
                    onTap: _onEditTap,
                  ),
                ),
              if (_showDeleteAction)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: _actionWidth,
                  child: _actionButton(
                    color: const Color(0xFFD14343),
                    icon: Icons.delete_outline,
                    label: 'ลบ',
                    onTap: _onDeleteTap,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// เอฟเฟกต์ popup แบบเกมเมื่อบันทึกรอบ/เที่ยวสำเร็จ
Widget _withRecordBurst({
  required _CounterUnit unit,
  required bool isTrip,
  required Widget child,
}) {
  return Stack(
    clipBehavior: Clip.none,
    fit: StackFit.passthrough,
    children: [
      child,
      Positioned.fill(
        child: IgnorePointer(
          child: _GameRecordBurst(
            burstTick: unit.burstTick,
            roundNo: unit.rounds,
            comboCount: unit.comboCount,
            isTrip: isTrip,
          ),
        ),
      ),
    ],
  );
}

/// 1 ชิ้นคอนเฟตติที่กระเด็นออกตอนบันทึก
class _Confetti {
  _Confetti({
    required this.angle,
    required this.distance,
    required this.size,
    required this.color,
    required this.rotSpeed,
    required this.drift,
    required this.gravity,
    required this.isStar,
  });

  final double angle;
  final double distance;
  final double size;
  final Color color;
  final double rotSpeed;
  final double drift;
  final double gravity;
  final bool isStar;
}

class _GameRecordBurst extends StatefulWidget {
  const _GameRecordBurst({
    required this.burstTick,
    required this.roundNo,
    required this.comboCount,
    required this.isTrip,
  });

  final int burstTick;
  final int roundNo;
  final int comboCount;
  final bool isTrip;

  @override
  State<_GameRecordBurst> createState() => _GameRecordBurstState();
}

class _GameRecordBurstState extends State<_GameRecordBurst>
    with SingleTickerProviderStateMixin {
  static const _party = <Color>[
    Color(0xFFFFD600),
    Color(0xFFFF6D00),
    Color(0xFF00E5FF),
    Color(0xFF76FF03),
    Color(0xFFFF4081),
    Color(0xFFB388FF),
    Colors.white,
  ];

  late final AnimationController _ctrl;
  List<_Confetti> _confetti = const [];

  bool get _isMilestone => widget.roundNo > 0 && widget.roundNo % 5 == 0;

  @override
  void initState() {
    super.initState();
    final ms = DevicePerf.isConstrainedDevice ? 620 : 920;
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: ms),
    );
    if (widget.burstTick > 0) {
      _rebuildConfetti();
      _ctrl.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _GameRecordBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.burstTick != oldWidget.burstTick && widget.burstTick > 0) {
      _rebuildConfetti();
      _ctrl.forward(from: 0);
    }
  }

  void _rebuildConfetti() {
    final rnd = math.Random(widget.burstTick * 911 + widget.roundNo * 7);
    final base = DevicePerf.isConstrainedDevice ? 10 : 16;
    final count = _isMilestone ? (base * 1.8).round() : base;
    _confetti = List<_Confetti>.generate(count, (i) {
      final angle = rnd.nextDouble() * math.pi * 2;
      final spread = _isMilestone ? 128.0 : 84.0;
      return _Confetti(
        angle: angle,
        distance: 38 + rnd.nextDouble() * spread,
        size: 6 + rnd.nextDouble() * 8,
        color: _party[rnd.nextInt(_party.length)],
        rotSpeed: (rnd.nextDouble() - 0.5) * 10,
        drift: (rnd.nextDouble() - 0.5) * 40,
        gravity: 40 + rnd.nextDouble() * 90,
        isStar: rnd.nextBool(),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.burstTick <= 0) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final popIn = Curves.easeOutBack.transform((t / 0.34).clamp(0.0, 1.0));
        final popScale = t < 0.34
            ? 0.15 + popIn * 0.95
            : 1.1 +
                Curves.easeOut.transform(((t - 0.34) / 0.66).clamp(0.0, 1.0)) *
                    0.16;
        final fadeOut =
            1 - Curves.easeIn.transform(((t - 0.55) / 0.45).clamp(0.0, 1.0));
        final riseY = -60 *
            Curves.easeOutCubic.transform(((t - 0.25) / 0.75).clamp(0.0, 1.0));
        final accent = widget.isTrip
            ? const Color(0xFFFFD600)
            : const Color(0xFFFFF176);
        final labelColor =
            widget.isTrip ? const Color(0xFF0D47A1) : const Color(0xFF880E4F);

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            _shockRing(t: t, accent: accent, delay: 0, maxScale: 1.7),
            if (_isMilestone)
              _shockRing(t: t, accent: Colors.white, delay: 0.12, maxScale: 2.3),
            for (final c in _confetti) _confettiWidget(c, t),
            Transform.translate(
              offset: Offset(0, riseY),
              child: Transform.scale(
                scale: popScale,
                child: Opacity(
                  opacity: fadeOut.clamp(0.0, 1.0),
                  child: _burstPopupCard(
                    labelColor: labelColor,
                    accent: accent,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _shockRing({
    required double t,
    required Color accent,
    required double delay,
    required double maxScale,
  }) {
    final lt = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
    final scale = 0.5 + lt * maxScale;
    final fade = (1 - lt).clamp(0.0, 1.0) * 0.6;
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: fade,
        child: Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3.5),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.55),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confettiWidget(_Confetti c, double t) {
    final travel = Curves.easeOut.transform(t);
    final dx = math.cos(c.angle) * c.distance * travel + c.drift * t;
    final dy = math.sin(c.angle) * c.distance * travel + c.gravity * t * t;
    final opacity =
        t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4).clamp(0.0, 1.0).toDouble();
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.rotate(
        angle: c.rotSpeed * t,
        child: Opacity(
          opacity: opacity,
          child: c.isStar
              ? Icon(
                  Icons.star_rounded,
                  size: c.size + 4,
                  color: c.color,
                  shadows: [
                    Shadow(color: c.color.withValues(alpha: 0.8), blurRadius: 6),
                  ],
                )
              : Container(
                  width: c.size,
                  height: c.size * 0.5,
                  decoration: BoxDecoration(
                    color: c.color,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: c.color.withValues(alpha: 0.7),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  ({String text, IconData icon, Color color})? _comboBadge() {
    final combo = widget.comboCount;
    if (_isMilestone) {
      return (
        text: widget.isTrip
            ? 'ครบ ${widget.roundNo} เที่ยว!'
            : 'ครบ ${widget.roundNo} รอบ!',
        icon: Icons.emoji_events_rounded,
        color: const Color(0xFFFF6D00),
      );
    }
    if (combo >= 8) {
      return (text: 'เทพมาก! x$combo', icon: Icons.bolt_rounded, color: const Color(0xFFD500F9));
    }
    if (combo >= 5) {
      return (text: 'สุดยอด! x$combo', icon: Icons.local_fire_department_rounded, color: const Color(0xFFFF3D00));
    }
    if (combo >= 3) {
      return (text: 'ไฟแรง! x$combo', icon: Icons.local_fire_department_rounded, color: const Color(0xFFFF9100));
    }
    if (combo >= 2) {
      return (text: 'คอมโบ x$combo', icon: Icons.flash_on_rounded, color: const Color(0xFF00B0FF));
    }
    return null;
  }

  Widget _burstPopupCard({
    required Color labelColor,
    required Color accent,
  }) {
    final badge = _comboBadge();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badge != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: badge.color,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: badge.color.withValues(alpha: 0.6),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(badge.icon, size: 16, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  badge.text,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.isTrip
                  ? const [Color(0xFFFFF59D), Color(0xFFFFB300)]
                  : const [Color(0xFFFFFDE7), Color(0xFFFFEE58)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
              BoxShadow(
                color: accent.withValues(alpha: 0.55),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '+1',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: labelColor,
                  height: 1,
                  shadows: const [
                    Shadow(color: Colors.white, blurRadius: 10),
                    Shadow(color: Colors.white, blurRadius: 4),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.isTrip
                    ? 'เที่ยวที่ ${widget.roundNo}'
                    : 'รอบที่ ${widget.roundNo}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF37474F),
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ปุ่มบันทึกแบบยกนูน + เอฟเฟกต์ตอนกด
class _RecordButtonShell extends StatelessWidget {
  const _RecordButtonShell({
    required this.bgColor,
    required this.shadowColor,
    required this.busy,
    required this.dimmed,
    required this.pressed,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onPointerCancel,
    required this.child,
    this.onPointerMove,
    this.busyBgColor,
    this.bottomOverlay,
    this.shimmer = false,
    this.borderRadius = 16,
  });

  final Color bgColor;
  final Color shadowColor;
  final bool busy;
  final bool dimmed;
  final bool pressed;
  final VoidCallback onPointerDown;
  final VoidCallback onPointerUp;
  final VoidCallback onPointerCancel;
  final void Function(PointerMoveEvent event)? onPointerMove;
  final Widget child;
  final Color? busyBgColor;
  final Widget? bottomOverlay;
  final bool shimmer;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final animDuration = pressed
        ? SoftPressMotion.downDuration()
        : SoftPressMotion.upDuration();
    final animCurve =
        pressed ? SoftPressMotion.downCurve() : SoftPressMotion.upCurve();
    final bg = busy
        ? (busyBgColor ?? bgColor.withValues(alpha: 0.55))
        : dimmed
            ? bgColor.withValues(alpha: 0.72)
            : bgColor;
    final shadowBlur = busy ? 0.0 : pressed ? 6.0 : 14.0;
    final shadowY = busy ? 0.0 : pressed ? 2.0 : 6.0;

    return SoftPressShell(
      pressed: pressed && !busy,
      size: SoftPressSize.large,
      borderRadius: borderRadius,
      showHighlight: !busy && !dimmed,
      isDarkSurface: true,
      liftWhenIdle: !busy && !dimmed,
      child: AnimatedContainer(
        duration: animDuration,
        curve: animCurve,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: busy
              ? null
              : [
                  BoxShadow(
                    color: shadowColor.withValues(alpha: 0.45),
                    blurRadius: shadowBlur,
                    offset: Offset(0, shadowY),
                  ),
                ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: TouchProfile.of(context).extraHitPadding,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => onPointerDown(),
            onPointerMove: onPointerMove,
            onPointerUp: (_) => onPointerUp(),
            onPointerCancel: (_) => onPointerCancel(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                child,
                if (shimmer && !busy && !dimmed && !pressed)
                  const Positioned.fill(
                    child: IgnorePointer(child: _IdleShimmer()),
                  ),
                ?bottomOverlay,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// แสงวิ่งเฉียงๆ วนซ้ำ เพื่อให้ปุ่มดูมีชีวิตชีวาแบบเกม
class _IdleShimmer extends StatefulWidget {
  const _IdleShimmer();

  @override
  State<_IdleShimmer> createState() => _IdleShimmerState();
}

class _IdleShimmerState extends State<_IdleShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: DevicePerf.isConstrainedDevice ? 4200 : 2900,
      ),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // แสงวิ่งช่วงต้นของรอบ แล้วพักช่วงท้าย
        final sweep = (_ctrl.value / 0.45).clamp(0.0, 1.0);
        final pos = -1.0 + sweep * 2.4;
        return ShaderMask(
          shaderCallback: (rect) {
            return LinearGradient(
              begin: Alignment(pos - 0.5, -1),
              end: Alignment(pos + 0.5, 1),
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: 0.22),
                Colors.white.withValues(alpha: 0),
              ],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(rect);
          },
          child: const SizedBox.expand(
            child: ColoredBox(color: Colors.white),
          ),
        );
      },
    );
  }
}

/// แถบ «บันทึกล่าสุด» — ซ่อนไทม์ไลน์ไว้ก่อน แตะเพื่อแสดง/ซ่อน + เปิดแผงเพิ่มรถ
class _LatestTripRecordsBar extends StatelessWidget {
  const _LatestTripRecordsBar({
    required this.expanded,
    required this.units,
    required this.onTap,
  });

  final bool expanded;
  final List<_CounterUnit> units;
  final VoidCallback onTap;

  int get _lapCount =>
      units.fold<int>(0, (sum, u) => sum + u.lapTimes.length);

  @override
  Widget build(BuildContext context) {
    final hasLaps = _lapCount > 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: expanded ? const Color(0xFFE8F4FD) : const Color(0xFFF4F7FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: expanded
                  ? const Color(0xFF90CAF9)
                  : const Color(0xFFDCE6F2),
              width: expanded ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'บันทึกล่าสุด',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF455A64),
                      ),
                    ),
                    if (!expanded && hasLaps) ...[
                      const SizedBox(width: 6),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          child: Text(
                            '$_lapCount',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1565C0),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      expanded ? 'ซ่อน' : 'ดู',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: expanded
                            ? const Color(0xFF1565C0)
                            : const Color(0xFF78909C),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Transform.rotate(
                      angle: expanded ? 3.14159 : 0,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 22,
                        color: expanded
                            ? const Color(0xFF1565C0)
                            : const Color(0xFF78909C),
                      ),
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 220),
                  crossFadeState: expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstCurve: Curves.easeIn,
                  secondCurve: Curves.easeOut,
                  sizeCurve: Curves.easeOutCubic,
                  firstChild: hasLaps
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'ยังไม่มีเที่ยวที่บันทึก',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasLaps) ...[
                        const SizedBox(height: 8),
                        _buildTimeline(),
                      ] else
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'เลือกรถด้านล่าง',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ไทม์ไลน์เหตุการณ์ล่าสุด — chip มีจุดสีตามคันรถ เรียงล่าสุดก่อน เลื่อนแนวนอน
  Widget _buildTimeline() {
    final events = <({int unitIndex, String title, int roundNo, String stamp})>[];
    for (var i = 0; i < units.length; i++) {
      final u = units[i];
      for (var lap = 0; lap < u.lapTimes.length; lap++) {
        events.add((
          unitIndex: i,
          title: u.title,
          roundNo: lap + 1,
          stamp: u.lapTimes[lap],
        ));
      }
    }
    // stamp รูปแบบ dd/MM HH:mm:ss — วันเดียวกันเทียบ string ได้ตรงตามเวลา
    events.sort((a, b) => b.stamp.compareTo(a.stamp));
    final visible = events.take(14).toList(growable: false);
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final e = visible[i];
          final color = _vehicleButtonColor(e.unitIndex);
          final latest = i == 0;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: latest ? color.withValues(alpha: 0.1) : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: latest
                    ? color.withValues(alpha: 0.55)
                    : const Color(0xFFDCE6F2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${e.title} • เที่ยว ${e.roundNo} • ${_lapClockOf(e.stamp)}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: latest ? color : const Color(0xFF52647B),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// การ์ดเริ่มต้น — แตะครั้งแรกเพื่อเลือกรถและคนขับ (ไม่ต้องเปิดแถบ «บันทึกล่าสุด»)
class _FirstTripSetupCard extends StatefulWidget {
  const _FirstTripSetupCard({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_FirstTripSetupCard> createState() => _FirstTripSetupCardState();
}

class _FirstTripSetupCardState extends State<_FirstTripSetupCard> {
  bool _pressed = false;

  void _onPointerDown() {
    setState(() => _pressed = true);
    AppHaptics.confirm();
  }

  void _onPointerUp() {
    final tapped = _pressed;
    setState(() => _pressed = false);
    if (tapped) widget.onTap();
  }

  void _onPointerCancel() {
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final bg = _vehicleButtonColor(0);
    return _RecordButtonShell(
      bgColor: bg,
      shadowColor: bg,
      busy: false,
      dimmed: false,
      pressed: _pressed,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'คันที่ 1 • บันทึกเที่ยว',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fire_truck_outlined,
                      size: 44,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'เพิ่มรถและคนขับ',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white.withValues(alpha: 0.96),
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              'แตะการ์ดเพื่อเริ่มบันทึกเที่ยว',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.88),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ปุ่มบันทึกต่อคัน — กดแล้ว +1 เที่ยว, กดค้าง 3 ว. เพื่อลบเที่ยวล่าสุด
class _VehicleRecordButton extends StatefulWidget {
  const _VehicleRecordButton({
    required this.unit,
    required this.index,
    required this.onTap,
    required this.onHoldToUndo,
    this.compact = false,
    this.goal = 0,
    this.interactionsEnabled = true,
    required this.setHoldLock,
  });

  final _CounterUnit unit;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onHoldToUndo;
  final bool compact;

  /// เป้าหมายเที่ยวต่อวัน (0 = ไม่แสดง)
  final int goal;
  final bool interactionsEnabled;
  final void Function(bool locked) setHoldLock;

  @override
  State<_VehicleRecordButton> createState() => _VehicleRecordButtonState();
}

/// นับถอยหลัง cooldown ภายในการ์ดของตัวเอง — rebuild เฉพาะการ์ดใบเดียว
/// แทนการตั้ง timer ระดับแผงที่ rebuild การ์ดทุกใบพร้อมกันทุกวินาที
mixin _CardCooldownTicker<T extends StatefulWidget> on State<T> {
  Timer? _cooldownTickTimer;

  _CounterUnit get cooldownUnit;

  /// เรียกตอนต้น build — เริ่ม timer เมื่อการ์ดอยู่ในช่วง cooldown
  void syncCooldownTicker() {
    if (!cooldownUnit.isOnRecordCooldown) return;
    _cooldownTickTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (!cooldownUnit.isOnRecordCooldown) {
        _cooldownTickTimer?.cancel();
        _cooldownTickTimer = null;
      }
    });
  }

  void disposeCooldownTicker() {
    _cooldownTickTimer?.cancel();
    _cooldownTickTimer = null;
  }
}

class _VehicleRecordButtonState extends State<_VehicleRecordButton>
    with _CardCooldownTicker<_VehicleRecordButton> {
  static const _holdDuration = Duration(seconds: 3);
  static const _tapMax = Duration(milliseconds: 400);
  static const _swipeSlop = 6.0;

  Timer? _holdTimer;
  DateTime? _pointerDownAt;
  double _holdProgress = 0;
  bool _holdTriggered = false;
  bool _isPressed = false;
  double _moveAccumX = 0;
  double _moveAccumY = 0;
  bool _swipeTakeover = false;

  bool get _canPress =>
      !widget.unit.busy &&
      widget.interactionsEnabled &&
      !widget.unit.isOnRecordCooldown;

  bool get _canRecordTrip =>
      _canPress && !widget.unit.isBrokenReported;

  @override
  _CounterUnit get cooldownUnit => widget.unit;

  @override
  void dispose() {
    _holdTimer?.cancel();
    disposeCooldownTicker();
    widget.setHoldLock(false);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _VehicleRecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interactionsEnabled && !widget.interactionsEnabled) {
      _holdTimer?.cancel();
      _holdTimer = null;
      _pointerDownAt = null;
      _holdTriggered = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.setHoldLock(false);
        setState(() {
          _holdProgress = 0;
          _isPressed = false;
        });
      });
    }
  }

  void _startHoldTimer() {
    _holdTimer?.cancel();
    final started = DateTime.now();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || _pointerDownAt == null) return;
      final elapsed = DateTime.now().difference(started);
      final progress =
          (elapsed.inMilliseconds / _holdDuration.inMilliseconds).clamp(0.0, 1.0);
      setState(() => _holdProgress = progress);
      if (progress >= 1) {
        _holdTimer?.cancel();
        _holdTimer = null;
        _holdTriggered = true;
        AppHaptics.warn();
        setState(() => _holdProgress = 0);
        widget.onHoldToUndo();
      }
    });
  }

  void _onPointerDown() {
    if (widget.unit.busy || !widget.interactionsEnabled) return;
    _moveAccumX = 0;
    _moveAccumY = 0;
    _swipeTakeover = false;
    if (_canRecordTrip) {
      setState(() => _isPressed = true);
      AppHaptics.confirm();
    }
    _pointerDownAt = DateTime.now();
    _holdTriggered = false;
    if (widget.unit.rounds > 0) {
      setState(() => _holdProgress = 0);
      widget.setHoldLock(true);
      _startHoldTimer();
    }
  }

  /// เมื่อเลื่อนนิ้วแนวนอน = ตั้งใจปัดการ์ด → ยกเลิกการกดค้าง แล้วปลดล็อกให้การ์ดปัดได้
  void _onPointerMove(PointerMoveEvent event) {
    if (_swipeTakeover) return;
    _moveAccumX += event.delta.dx;
    _moveAccumY += event.delta.dy;
    if (_moveAccumX.abs() > _swipeSlop &&
        _moveAccumX.abs() >= _moveAccumY.abs()) {
      _swipeTakeover = true;
      _holdTimer?.cancel();
      _holdTimer = null;
      _holdTriggered = false;
      _pointerDownAt = null;
      widget.setHoldLock(false);
      _releasePress();
      if (mounted && _holdProgress != 0) {
        setState(() => _holdProgress = 0);
      }
    }
  }

  void _releasePress() {
    if (_isPressed && mounted) setState(() => _isPressed = false);
  }

  void _onPointerUp() {
    final downAt = _pointerDownAt;
    _pointerDownAt = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    widget.setHoldLock(false);
    _releasePress();

    if (_holdTriggered) {
      _holdTriggered = false;
      if (mounted) setState(() => _holdProgress = 0);
      return;
    }

    final progress = _holdProgress;
    if (mounted) setState(() => _holdProgress = 0);

    if (widget.unit.busy || downAt == null || !widget.interactionsEnabled) return;
    if (!_canRecordTrip) return;
    final elapsed = DateTime.now().difference(downAt);
    if (elapsed <= _tapMax && progress < 0.15) {
      widget.onTap();
    }
  }

  void _onPointerCancel() {
    _pointerDownAt = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    widget.setHoldLock(false);
    _releasePress();
    if (mounted) setState(() => _holdProgress = 0);
  }

  Widget _buildStandardVehicleBody({
    required _CounterUnit unit,
    required int carNo,
    required bool onCooldown,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _VehicleTripCountRail(
          rounds: unit.rounds,
          burstTick: unit.burstTick,
          onCooldown: onCooldown,
          cooldownSecondsLeft: unit.recordCooldownSecondsLeft,
          recordingEnabled: !unit.isBrokenReported,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          unit.isBrokenReported
                              ? 'คันที่ $carNo • หยุดบันทึกเที่ยว'
                              : 'คันที่ $carNo • บันทึกเที่ยว',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (unit.isBrokenReported) ...[
                        const SizedBox(height: 5),
                        const _BrokenVehicleBadge(compact: false),
                      ],
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          unit.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.12,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        unit.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.95),
                          height: 1.12,
                        ),
                      ),
                      if (unit.lapTimes.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'ล่าสุด ${unit.lapTimes.last}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                        ),
                      ],
                      if (widget.goal > 0) ...[
                        const SizedBox(height: 4),
                        _GoalProgressBar(
                          rounds: unit.rounds,
                          goal: widget.goal,
                          compact: false,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCompactVehicleBody({
    required _CounterUnit unit,
    required int carNo,
    required bool onCooldown,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'คันที่ $carNo',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (unit.isBrokenReported) ...[
                      const SizedBox(width: 4),
                      const _BrokenVehicleBadge(compact: true),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Center(
                  child: _VehicleTripCountRail(
                    compact: true,
                    rounds: unit.rounds,
                    burstTick: unit.burstTick,
                    onCooldown: onCooldown,
                    cooldownSecondsLeft: unit.recordCooldownSecondsLeft,
                    recordingEnabled: !unit.isBrokenReported,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  unit.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unit.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
                if (widget.goal > 0) ...[
                  const SizedBox(height: 4),
                  _GoalProgressBar(
                    rounds: unit.rounds,
                    goal: widget.goal,
                    compact: true,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    syncCooldownTicker();
    final unit = widget.unit;
    final busy = unit.busy;
    final broken = unit.isBrokenReported;
    final onCooldown = unit.isOnRecordCooldown && !busy;
    final bg = _vehicleButtonColor(widget.index);
    final carNo = widget.index + 1;
    return _withRecordBurst(
      unit: unit,
      isTrip: true,
      child: _RecordButtonShell(
      bgColor: bg,
      shadowColor: bg,
      busy: busy,
      dimmed: onCooldown || broken,
      pressed: _isPressed,
      shimmer: false,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      bottomOverlay: _holdProgress > 0
          ? Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: _holdProgress,
                minHeight: 4,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                color: Colors.white,
              ),
            )
          : null,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 6 : 10,
          vertical: widget.compact ? 6 : 8,
        ),
        child: busy
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
              )
            : ClipRect(
                child: widget.compact
                    ? _buildCompactVehicleBody(
                        unit: unit,
                        carNo: carNo,
                        onCooldown: onCooldown,
                      )
                    : _buildStandardVehicleBody(
                        unit: unit,
                        carNo: carNo,
                        onCooldown: onCooldown,
                      ),
              ),
      ),
    ),
    );
  }
}

/// เด้งสเกลแบบ pop เมื่อ trigger เปลี่ยน โดยไม่ remount ลูก
/// (ทำให้ _RollingCount ข้างในยังเล่นอนิเมชั่นเลื่อนตัวเลขได้)
class _PunchScale extends StatefulWidget {
  const _PunchScale({
    required this.trigger,
    required this.punch,
    required this.child,
  });

  final int trigger;
  final double punch;
  final Widget child;

  @override
  State<_PunchScale> createState() => _PunchScaleState();
}

class _PunchScaleState extends State<_PunchScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    value: widget.trigger > 0 ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _PunchScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.trigger > 0) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final s = 1 + (widget.punch - 1) * Curves.elasticOut.transform(_c.value);
        return Transform.scale(scale: s, child: child);
      },
    );
  }
}

/// ตัวเลขที่ "เลื่อนขึ้น" แบบสล็อตเมื่อค่าจำนวนเปลี่ยน
class _RollingCount extends StatelessWidget {
  const _RollingCount({required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) {
        final isIncoming = child.key == ValueKey<int>(value);
        final begin = isIncoming ? const Offset(0, 0.9) : const Offset(0, -0.9);
        return ClipRect(
          child: SlideTransition(
            position: Tween<Offset>(begin: begin, end: Offset.zero).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
        );
      },
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.center,
        children: [...previousChildren, ?currentChild],
      ),
      child: Text('$value', key: ValueKey<int>(value), style: style),
    );
  }
}

/// แถบซ้ายของการ์ดรถ — ไอคอน + จำนวนเที่ยว
class _VehicleTripCountRail extends StatelessWidget {
  const _VehicleTripCountRail({
    required this.rounds,
    required this.onCooldown,
    required this.cooldownSecondsLeft,
    this.burstTick = 0,
    this.compact = false,
    this.recordingEnabled = true,
  });

  final int rounds;
  final int burstTick;
  final bool onCooldown;
  final int cooldownSecondsLeft;
  final bool compact;
  final bool recordingEnabled;

  Widget _punchCount(Widget child, {double punchScale = 1.2}) {
    return _PunchScale(trigger: burstTick, punch: punchScale, child: child);
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.28),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (recordingEnabled)
              Icon(
                Icons.add_circle_rounded,
                size: 20,
                color: Colors.white.withValues(alpha: onCooldown ? 0.55 : 0.98),
              )
            else
              Icon(
                Icons.block_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            if (recordingEnabled) const SizedBox(width: 5),
            _punchCount(
              _RollingCount(
                value: rounds,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withValues(alpha: onCooldown ? 0.7 : 1),
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 3),
            Text(
              'เที่ยว',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
            if (onCooldown) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.timer_outlined,
                size: 12,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              Text(
                '$cooldownSecondsLeft',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.28),
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (recordingEnabled)
            Icon(
              Icons.add_circle_rounded,
              size: 30,
              color: Colors.white.withValues(alpha: onCooldown ? 0.55 : 0.98),
            )
          else
            Icon(
              Icons.block_rounded,
              size: 26,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          SizedBox(height: recordingEnabled ? 6 : 4),
          _punchCount(
            _RollingCount(
              value: rounds,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: onCooldown ? 0.7 : 1),
                height: 1,
              ),
            ),
            punchScale: 1.22,
          ),
          const SizedBox(height: 2),
          Text(
            'เที่ยว',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          if (onCooldown) ...[
            const SizedBox(height: 6),
            Icon(
              Icons.timer_outlined,
              size: 14,
              color: Colors.white.withValues(alpha: 0.85),
            ),
            Text(
              '$cooldownSecondsLeft',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BrokenVehicleBadge extends StatelessWidget {
  const _BrokenVehicleBadge({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE0B2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.car_crash_outlined,
            size: compact ? 10 : 12,
            color: const Color(0xFFE65100),
          ),
          SizedBox(width: compact ? 2 : 4),
          Text(
            'แจ้งรถเสีย',
            style: TextStyle(
              fontSize: compact ? 8.5 : 10,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFE65100),
            ),
          ),
        ],
      ),
    );
  }
}

/// ชิปแสดงรอบร่อนทราย — กดค้างเพื่อลบรอบนั้น
class _SandLapChip extends StatefulWidget {
  const _SandLapChip({
    required this.roundNo,
    required this.stamp,
    required this.onLongPress,
  });

  final int roundNo;
  final String stamp;
  final VoidCallback onLongPress;

  @override
  State<_SandLapChip> createState() => _SandLapChipState();
}

class _SandLapChipState extends State<_SandLapChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) {
        AppHaptics.confirm();
        setState(() => _pressed = true);
      },
      onLongPressEnd: (_) => setState(() => _pressed = false),
      onLongPressCancel: () => setState(() => _pressed = false),
      onLongPress: () {
        AppHaptics.warn();
        setState(() => _pressed = false);
        widget.onLongPress();
      },
      child: SoftPressShell(
        pressed: _pressed,
        size: SoftPressSize.small,
        borderRadius: 8,
        isDarkSurface: false,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _pressed ? const Color(0xFFFFEBEE) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _pressed ? const Color(0xFFEF9A9A) : const Color(0xFFDCE6F2),
          ),
        ),
        child: Text(
          'รอบ ${widget.roundNo} • ${widget.stamp}',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: _pressed ? FontWeight.w700 : FontWeight.w500,
            color: _pressed ? const Color(0xFFC62828) : const Color(0xFF52647B),
          ),
        ),
      ),
      ),
    );
  }
}

/// วงกลมกลางการ์ดร่อนทราย — แสดงรวมจำนวนรอบ
class _SandRoundCountHero extends StatelessWidget {
  const _SandRoundCountHero({
    required this.rounds,
    required this.dimmed,
    this.burstTick = 0,
  });

  final int rounds;
  final bool dimmed;
  final int burstTick;

  @override
  Widget build(BuildContext context) {
    final core = Opacity(
      opacity: dimmed ? 0.72 : 1,
      child: Container(
        width: 132,
        height: 132,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.55),
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.12),
              blurRadius: 8,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'รวม',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.9),
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            _RollingCount(
              value: rounds < 0 ? 0 : rounds,
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1,
                letterSpacing: -1.5,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'รอบ',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
    return _PunchScale(trigger: burstTick, punch: 1.16, child: core);
  }
}

class _SandRecordButton extends StatefulWidget {
  const _SandRecordButton({
    required this.unit,
    required this.onTap,
    required this.onHoldToUndo,
    this.showLatestLapInline = true,
  });

  final _CounterUnit unit;
  final VoidCallback onTap;
  final VoidCallback onHoldToUndo;
  /// แสดงแถบ «ล่าสุด» ในการ์ด — ปิดเมื่อมีชิปรอบด้านล่างแล้ว (กันพื้นที่ซ้ำ/ล้น)
  final bool showLatestLapInline;

  @override
  State<_SandRecordButton> createState() => _SandRecordButtonState();
}

class _SandRecordButtonState extends State<_SandRecordButton>
    with _CardCooldownTicker<_SandRecordButton> {
  static const _holdDuration = Duration(seconds: 3);
  static const _tapMax = Duration(milliseconds: 400);
  static const _sandBg = Color(0xFFAD1457);
  static const _sandBgBusy = Color(0xFF880E4F);

  Timer? _holdTimer;
  DateTime? _pointerDownAt;
  double _holdProgress = 0;
  bool _holdTriggered = false;
  bool _isPressed = false;

  bool get _canPress =>
      !widget.unit.busy && !widget.unit.isOnRecordCooldown;

  @override
  _CounterUnit get cooldownUnit => widget.unit;

  @override
  void dispose() {
    _holdTimer?.cancel();
    disposeCooldownTicker();
    super.dispose();
  }

  void _startHoldTimer() {
    _holdTimer?.cancel();
    final started = DateTime.now();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || _pointerDownAt == null) return;
      final elapsed = DateTime.now().difference(started);
      final progress =
          (elapsed.inMilliseconds / _holdDuration.inMilliseconds).clamp(0.0, 1.0);
      setState(() => _holdProgress = progress);
      if (progress >= 1) {
        _holdTimer?.cancel();
        _holdTimer = null;
        _holdTriggered = true;
        AppHaptics.warn();
        setState(() => _holdProgress = 0);
        widget.onHoldToUndo();
      }
    });
  }

  void _onPointerDown() {
    if (widget.unit.busy) return;
    if (_canPress) {
      setState(() => _isPressed = true);
      AppHaptics.confirm();
    }
    _pointerDownAt = DateTime.now();
    _holdTriggered = false;
    if (widget.unit.rounds > 0) {
      setState(() => _holdProgress = 0);
      _startHoldTimer();
    }
  }

  void _releasePress() {
    if (_isPressed && mounted) setState(() => _isPressed = false);
  }

  void _onPointerUp() {
    final downAt = _pointerDownAt;
    _pointerDownAt = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    _releasePress();

    if (_holdTriggered) {
      _holdTriggered = false;
      if (mounted) setState(() => _holdProgress = 0);
      return;
    }

    final progress = _holdProgress;
    if (mounted) setState(() => _holdProgress = 0);

    if (widget.unit.busy || downAt == null) return;
    if (widget.unit.isOnRecordCooldown) return;
    final elapsed = DateTime.now().difference(downAt);
    if (elapsed <= _tapMax && progress < 0.15) {
      widget.onTap();
    }
  }

  void _onPointerCancel() {
    _pointerDownAt = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    _releasePress();
    if (mounted) setState(() => _holdProgress = 0);
  }

  @override
  Widget build(BuildContext context) {
    syncCooldownTicker();
    final unit = widget.unit;
    final busy = unit.busy;
    final onCooldown = unit.isOnRecordCooldown && !busy;
    return SizedBox.expand(
      child: _withRecordBurst(
      unit: unit,
      isTrip: false,
      child: _RecordButtonShell(
      bgColor: _sandBg,
      busyBgColor: _sandBgBusy,
      shadowColor: _sandBg,
      busy: busy,
      dimmed: onCooldown,
      pressed: _isPressed,
      shimmer: false,
      borderRadius: 0,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      bottomOverlay: _holdProgress > 0
          ? Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: _holdProgress,
                minHeight: 4,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                color: Colors.white,
              ),
            )
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFEC407A),
                    Color(0xFFC2185B),
                    Color(0xFF880E4F),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: busy
                  ? const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final header = Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.water_drop_rounded,
                              size: 22,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'บันทึกการร่อนทราย',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color:
                                      Colors.white.withValues(alpha: 0.95),
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ],
                        );
                        final hint = Text(
                          onCooldown
                              ? 'รอ ${unit.recordCooldownSecondsLeft} วินาที'
                              : 'แตะการ์ดเพื่อบันทึก +1 รอบ',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(
                              alpha: onCooldown ? 0.75 : 0.88,
                            ),
                          ),
                        );
                        final latest = (widget.showLatestLapInline &&
                                unit.lapTimes.isNotEmpty)
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.22),
                                  ),
                                ),
                                child: Text(
                                  'ล่าสุด ${unit.lapTimes.last}',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : null;
                        final hero = _SandRoundCountHero(
                          rounds: unit.rounds,
                          burstTick: unit.burstTick,
                          dimmed: onCooldown,
                        );
                        // ถ้าไม่มีความสูงจำกัด (เช่นถูกวางในกล่องยืด) — ไม่ใช้ Expanded
                        if (!constraints.hasBoundedHeight) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              header,
                              const SizedBox(height: 8),
                              hero,
                              const SizedBox(height: 8),
                              hint,
                              if (latest != null) ...[
                                const SizedBox(height: 8),
                                latest,
                              ],
                            ],
                          );
                        }
                        return SizedBox(
                          height: constraints.maxHeight,
                          width: constraints.maxWidth,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              header,
                              const SizedBox(height: 8),
                              // วงกลมรอบขยายเต็มพื้นที่ที่เหลือ
                              Expanded(
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.contain,
                                    child: hero,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              hint,
                              if (latest != null) ...[
                                const SizedBox(height: 8),
                                latest,
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
    ),
    );
  }
}

/// Dialog แก้ไขคนขับของคันที่มีอยู่
class _ChangeDriverDialog extends StatefulWidget {
  const _ChangeDriverDialog({
    required this.vehicleTitle,
    required this.initialDriverId,
    required this.drivers,
  });

  final String vehicleTitle;
  final String initialDriverId;
  final List<Employee> drivers;

  @override
  State<_ChangeDriverDialog> createState() => _ChangeDriverDialogState();
}

class _ChangeDriverDialogState extends State<_ChangeDriverDialog> {
  late String _driverId;

  @override
  void initState() {
    super.initState();
    _driverId = widget.initialDriverId.trim();
  }

  bool get _canSave => _driverId.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.badge_outlined, color: Color(0xFF1565C0)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'แก้ไขคนขับ — ${widget.vehicleTitle}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A2433),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: (_driverId.isEmpty ||
                        !widget.drivers.any((e) => e.id == _driverId))
                    ? null
                    : _driverId,
                decoration: const InputDecoration(
                  labelText: 'คนขับ',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
                items: widget.drivers
                    .map(
                      (e) => DropdownMenuItem<String>(
                        value: e.id,
                        child: Text(
                          e.nickname.isNotEmpty ? e.nickname : e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _driverId = v ?? ''),
              ),
              if (widget.drivers.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'ยังไม่พบพนักงานตำแหน่ง "คนขับรถ"',
                    style: TextStyle(
                      color: Color(0xFFD14343),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('ยกเลิก'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                      ),
                      onPressed:
                          _canSave ? () => Navigator.pop(context, _driverId) : null,
                      child: const Text('บันทึก'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog เลือกรถ + คนขับ (หลายคันได้)
class _SelectDialog extends StatefulWidget {
  const _SelectDialog({
    required this.cars,
    required this.drivers,
    required this.alreadyAdded,
    required this.tripHistory,
    required this.vehicleDefaultDrivers,
  });

  final List<String> cars;
  final List<Employee> drivers;
  final Set<String> alreadyAdded;
  final List<AppTransaction> tripHistory;
  final Map<String, String> vehicleDefaultDrivers;

  @override
  State<_SelectDialog> createState() => _SelectDialogState();
}

class _SelectDialogState extends State<_SelectDialog> {
  final List<_Pick> _rows = [_Pick()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_rows.length != 1 || _rows.first.vehicleId.isNotEmpty) return;
      final available = _availableCars;
      if (available.isEmpty) return;
      _onVehicleChanged(_rows.first, available.first);
    });
  }

  List<String> get _availableCars => sortCountRecordVehicles(
        cars: widget.cars
            .where((c) => !widget.alreadyAdded.contains(c))
            .toList(growable: false),
        tripHistory: widget.tripHistory,
      );

  void _applyDefaultDriverForRow(_Pick row) {
    final vehicleId = row.vehicleId.trim();
    if (vehicleId.isEmpty) return;
    final defaultId = resolveCountRecordDefaultDriverId(
      vehicleId: vehicleId,
      drivers: widget.drivers,
      tripHistory: widget.tripHistory,
      vehicleDefaultDrivers: widget.vehicleDefaultDrivers,
    );
    if (defaultId != null) {
      row.driverId = defaultId;
    }
  }

  void _onVehicleChanged(_Pick row, String? vehicleId) {
    row.vehicleId = vehicleId ?? '';
    if (row.vehicleId.isNotEmpty) {
      _applyDefaultDriverForRow(row);
    } else {
      row.driverId = '';
    }
    setState(() {});
  }

  bool get _canSave => _rows.any(
        (r) => r.vehicleId.trim().isNotEmpty && r.driverId.trim().isNotEmpty,
      );

  void _save() {
    final seen = <String>{};
    final out = <_Pick>[];
    for (final r in _rows) {
      final v = r.vehicleId.trim();
      final d = r.driverId.trim();
      if (v.isEmpty || d.isEmpty) continue;
      if (!seen.add(v)) continue;
      out.add(r);
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final available = _availableCars;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.fire_truck_outlined,
                      color: Color(0xFF1D8FE1)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'เลือกรถและคนขับ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A2433),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < _rows.length; i++)
                        _SelectRow(
                          key: ValueKey('row_$i'),
                          index: i,
                          row: _rows[i],
                          cars: available,
                          drivers: widget.drivers,
                          tripHistory: widget.tripHistory,
                          vehicleDefaultDrivers: widget.vehicleDefaultDrivers,
                          canRemove: _rows.length > 1,
                          onRemove: () =>
                              setState(() => _rows.removeAt(i)),
                          onVehicleChanged: (v) => _onVehicleChanged(_rows[i], v),
                          onChanged: () => setState(() {}),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _rows.add(_Pick())),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('เพิ่มรถอีกคัน'),
                ),
              ),
              if (widget.drivers.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'ยังไม่พบพนักงานตำแหน่ง "คนขับรถ" — ตั้งค่าในเมนูพนักงาน',
                    style: TextStyle(
                      color: Color(0xFFD14343),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('ยกเลิก'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1D8FE1),
                      ),
                      onPressed: _canSave ? _save : null,
                      child: const Text('บันทึก'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectRow extends StatelessWidget {
  const _SelectRow({
    super.key,
    required this.index,
    required this.row,
    required this.cars,
    required this.drivers,
    required this.tripHistory,
    required this.vehicleDefaultDrivers,
    required this.canRemove,
    required this.onRemove,
    required this.onVehicleChanged,
    required this.onChanged,
  });

  final int index;
  final _Pick row;
  final List<String> cars;
  final List<Employee> drivers;
  final List<AppTransaction> tripHistory;
  final Map<String, String> vehicleDefaultDrivers;
  final bool canRemove;
  final VoidCallback onRemove;
  final ValueChanged<String?> onVehicleChanged;
  final VoidCallback onChanged;

  String? _defaultDriverIdForVehicle(String vehicleId) {
    if (vehicleId.trim().isEmpty) return null;
    return resolveCountRecordDefaultDriverId(
      vehicleId: vehicleId,
      drivers: drivers,
      tripHistory: tripHistory,
      vehicleDefaultDrivers: vehicleDefaultDrivers,
    );
  }

  @override
  Widget build(BuildContext context) {
    final carOptions = <String>[
      if (row.vehicleId.isNotEmpty && !cars.contains(row.vehicleId))
        row.vehicleId,
      ...cars,
    ];
    final vehicleId = row.vehicleId.trim();
    final defaultDriverId = _defaultDriverIdForVehicle(vehicleId);
    final driverOptions = vehicleId.isEmpty
        ? drivers
        : orderDriversForVehicle(
            vehicleId: vehicleId,
            drivers: drivers,
            tripHistory: tripHistory,
            vehicleDefaultDrivers: vehicleDefaultDrivers,
          );
    final driverValue = (row.driverId.isEmpty ||
            !drivers.any((e) => e.id == row.driverId))
        ? null
        : row.driverId;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FCFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE8F5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'คันที่ ${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF205A9A),
                ),
              ),
              const Spacer(),
              if (canRemove)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Color(0xFFD14343)),
                ),
            ],
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('veh_${row.vehicleId}_$index'),
            isExpanded: true,
            initialValue: row.vehicleId.isEmpty ? null : row.vehicleId,
            decoration: const InputDecoration(
              labelText: 'รถ',
              prefixIcon: Icon(Icons.fire_truck_outlined),
              border: OutlineInputBorder(),
            ),
            items: carOptions
                .map(
                  (c) => DropdownMenuItem<String>(
                    value: c,
                    child: Text(
                      c,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: onVehicleChanged,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('drv_${row.vehicleId}_${row.driverId}_$index'),
            isExpanded: true,
            initialValue: driverValue,
            decoration: const InputDecoration(
              labelText: 'คนขับ',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
            items: driverOptions
                .map(
                  (e) => DropdownMenuItem<String>(
                    value: e.id,
                    child: Text(
                      driverDropdownLabel(
                        driver: e,
                        defaultDriverId: defaultDriverId,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: defaultDriverId != null &&
                                e.id == defaultDriverId
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: defaultDriverId != null &&
                                e.id == defaultDriverId
                            ? const Color(0xFF1565C0)
                            : null,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: vehicleId.isEmpty
                ? null
                : (v) {
                    row.driverId = v ?? '';
                    onChanged();
                  },
          ),
        ],
      ),
    );
  }
}

/// แถบสรุปยอดรวมวันนี้ — รวม/เช้า/บ่าย + ป้ายช่วงกะ + ปุ่มเป้าหมาย/แชร์
class _CountStatsStrip extends StatelessWidget {
  const _CountStatsStrip({
    required this.isTrip,
    required this.totals,
    required this.goal,
    this.onGoalTap,
    required this.onShareTap,
  });

  final bool isTrip;
  final ({int total, int morning, int afternoon}) totals;
  final int goal;
  final VoidCallback? onGoalTap;
  final VoidCallback onShareTap;

  @override
  Widget build(BuildContext context) {
    final unitLabel = isTrip ? 'เที่ยว' : 'รอบ';
    final accent =
        isTrip ? const Color(0xFF1565C0) : const Color(0xFFAD1457);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E9F2)),
      ),
      child: Row(
        children: [
          Text(
            'รวม',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(width: 6),
          _PunchScale(
            trigger: totals.total,
            punch: 1.25,
            child: _RollingCount(
              value: totals.total,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: accent,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            unitLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'เช้า ${totals.morning} · บ่าย ${totals.afternoon}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF52647B),
                ),
              ),
            ),
          ),
          const _ShiftBadge(),
          if (isTrip && onGoalTap != null) ...[
            const SizedBox(width: 6),
            _StatsStripIconButton(
              icon: goal > 0 ? Icons.flag_rounded : Icons.flag_outlined,
              color: goal > 0 ? const Color(0xFFE65100) : const Color(0xFF90A4AE),
              tooltip: goal > 0 ? 'เป้า $goal เที่ยว/คัน' : 'ตั้งเป้าหมาย',
              onTap: onGoalTap!,
            ),
          ],
          const SizedBox(width: 6),
          _StatsStripIconButton(
            icon: Icons.ios_share_rounded,
            color: const Color(0xFF0D98A5),
            tooltip: 'แชร์สรุปประจำวัน',
            onTap: onShareTap,
          ),
        ],
      ),
    );
  }
}

class _StatsStripIconButton extends StatelessWidget {
  const _StatsStripIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SoftPressButton(
        size: SoftPressSize.small,
        borderRadius: 10,
        isDarkSurface: false,
        onTap: onTap,
        child: Material(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

/// ป้ายช่วงกะอัตโนมัติ — ก่อนเที่ยง «ช่วงเช้า» / ตั้งแต่เที่ยง «ช่วงบ่าย»
class _ShiftBadge extends StatefulWidget {
  const _ShiftBadge();

  @override
  State<_ShiftBadge> createState() => _ShiftBadgeState();
}

class _ShiftBadgeState extends State<_ShiftBadge> {
  Timer? _timer;
  bool _morning = DateTime.now().hour < 12;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      final m = DateTime.now().hour < 12;
      if (mounted && m != _morning) setState(() => _morning = m);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _morning ? const Color(0xFFF57F17) : const Color(0xFF4527A0);
    final bg = _morning ? const Color(0xFFFFF8E1) : const Color(0xFFEDE7F6);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _morning ? Icons.wb_sunny_rounded : Icons.wb_twilight_rounded,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 3),
            Text(
              _morning ? 'ช่วงเช้า' : 'ช่วงบ่าย',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// แถบความคืบหน้าเทียบเป้ารายวันบนการ์ดรถ — ครบเป้าเปลี่ยนเป็นสีทอง + ดาว
class _GoalProgressBar extends StatelessWidget {
  const _GoalProgressBar({
    required this.rounds,
    required this.goal,
    required this.compact,
  });

  final int rounds;
  final int goal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final reached = rounds >= goal;
    final frac = goal <= 0 ? 0.0 : (rounds / goal).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: frac),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: compact ? 4 : 5,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                color: reached
                    ? const Color(0xFFFFD54F)
                    : Colors.white.withValues(alpha: 0.95),
              ),
            ),
          ),
        ),
        const SizedBox(width: 5),
        if (reached)
          const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFD54F))
        else
          Text(
            '$rounds/$goal',
            style: TextStyle(
              fontSize: compact ? 9.5 : 10.5,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
      ],
    );
  }
}

/// การ์ดสรุปประจำวันสำหรับแชร์เป็นรูปภาพ
class _DailyShareCard extends StatelessWidget {
  const _DailyShareCard({
    required this.isTrip,
    required this.dateYmd,
    required this.units,
    required this.totals,
  });

  final bool isTrip;
  final String dateYmd;
  final List<_CounterUnit> units;
  final ({int total, int morning, int afternoon}) totals;

  static const _thMonths = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];

  String get _dateLabel {
    final parts = dateYmd.split('-');
    if (parts.length != 3) return dateYmd;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null || m < 1 || m > 12) return dateYmd;
    return '$d ${_thMonths[m - 1]} ${y + 543}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = isTrip ? const Color(0xFF1565C0) : const Color(0xFFAD1457);
    final unitLabel = isTrip ? 'เที่ยว' : 'รอบ';
    final withData =
        units.where((u) => u.rounds > 0).toList(growable: false);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, Color.lerp(accent, Colors.black, 0.35)!],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isTrip ? Icons.fire_truck_outlined : Icons.water_drop_outlined,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isTrip ? 'สรุปจำนวนเที่ยวรถ' : 'สรุปการร่อนทราย',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                _dateLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${totals.total}',
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '$unitLabel รวมวันนี้',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'เช้า ${totals.morning} $unitLabel',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'บ่าย ${totals.afternoon} $unitLabel',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (isTrip && withData.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.25)),
            const SizedBox(height: 10),
            for (final u in withData)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _vehicleButtonColor(units.indexOf(u)),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${u.title} • ${u.subtitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                    Text(
                      '${u.rounds} เที่ยว',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 8),
          Text(
            'จากแอพบันทึกประจำวัน',
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}
