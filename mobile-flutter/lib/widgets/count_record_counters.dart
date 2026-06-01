import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user.dart';
import '../models/app_transaction.dart';
import '../models/employee.dart';
import '../services/count_record_offline_sync.dart';
import '../services/employee_service.dart';
import '../services/transaction_service.dart';
import '../utils/daily_module_transactions.dart';
import '../utils/record_feedback_sound.dart';
import '../utils/record_success_speaker.dart';

/// โหมดของแผงนับ — เที่ยวรถ (ต้องเลือกรถ/คนขับก่อน) หรือ ร่อนทราย (หน่วยเดียว)
enum CounterMode { trip, sand }

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

  final String txId;
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

  bool get isBrokenReported => workDetails.contains('รถเสีย');
}

class _Pick {
  String vehicleId = '';
  String driverId = '';
}

enum _UnitEditAction { changeDriver, reportBroken }

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

  final List<_CounterUnit> _units = [];
  List<String> _cars = const [];
  List<Employee> _drivers = const [];
  Timer? _cooldownTicker;
  Timer? _offlineSyncTicker;
  bool _isOnline = true;
  int _pendingCount = 0;
  bool _addVehiclePanelOpen = false;

  @override
  bool get wantKeepAlive => true;

  _CounterUnit? get _sandUnit =>
      _units.isEmpty ? null : _units.first;

  @override
  void initState() {
    super.initState();
    _isOnline = widget.serverOnline;
    if (!widget.serverOnline) {
      CountRecordOfflineSync.instance.noteServerUnreachable();
    }
    unawaited(_initPanel());
    RecordSuccessSpeaker.instance.warmUp();
  }

  @override
  void didUpdateWidget(covariant CountRecordCounterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateYmd != widget.dateYmd ||
        oldWidget.dayTransactions != widget.dayTransactions) {
      _units.clear();
      unawaited(_initPanel());
    } else if (!oldWidget.serverOnline && widget.serverOnline) {
      unawaited(_onBackOnline());
    } else if (oldWidget.serverOnline != widget.serverOnline) {
      if (!widget.serverOnline) {
        CountRecordOfflineSync.instance.noteServerUnreachable();
      }
      setState(() => _isOnline = widget.serverOnline);
    }
  }

  @override
  void dispose() {
    _cooldownTicker?.cancel();
    _offlineSyncTicker?.cancel();
    super.dispose();
  }

  void _ensureCooldownTicker() {
    if (_cooldownTicker != null) return;
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final active = _units.any((u) => u.isOnRecordCooldown);
      setState(() {});
      if (!active) {
        _cooldownTicker?.cancel();
        _cooldownTicker = null;
      }
    });
  }

  void _armRecordCooldown(_CounterUnit u) {
    u.recordCooldownUntil = DateTime.now().add(_recordTapCooldown);
    _ensureCooldownTicker();
  }

  int _recentSandLapStartIndex(int total) {
    if (total <= _sandRecentLapsVisible) return 0;
    return total - _sandRecentLapsVisible;
  }

  void _bootstrapFromTransactions(List<AppTransaction> dayTx) {
    _drivers = widget.employees
        .where((e) => !e.inactive)
        .where(_isDriverEmployee)
        .toList(growable: false);

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
        if (t.category == 'DailyLog' &&
            (t.subCategory ?? '').trim() == 'Sand' &&
            !t.description.contains('ทรายที่ล้างที่บ้าน')) {
          sandRow = t;
          break;
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
    await _refreshConnectivity();
    await _trySyncPending(silent: true);
    final merged = await CountRecordOfflineSync.instance.mergeForDayAsync(
      widget.dateYmd,
      widget.dayTransactions,
    );
    if (!mounted) return;
    setState(() {
      _units.clear();
      _bootstrapFromTransactions(merged);
    });
    await _loadCars();
    await _refreshPendingCount();
    if (widget.mode == CounterMode.trip && _units.isEmpty && mounted) {
      setState(() => _addVehiclePanelOpen = false);
    }
  }

  Future<void> _onBackOnline() async {
    await _refreshConnectivity();
    await _trySyncPending();
    if (!mounted) return;
    final merged = await CountRecordOfflineSync.instance.mergeForDayAsync(
      widget.dateYmd,
      widget.dayTransactions,
    );
    if (!mounted) return;
    setState(() {
      _units.clear();
      _bootstrapFromTransactions(merged);
    });
    await _loadCars();
  }

  Future<void> _refreshConnectivity() async {
    if (!widget.serverOnline) {
      CountRecordOfflineSync.instance.noteServerUnreachable();
      if (mounted && _isOnline) setState(() => _isOnline = false);
      return;
    }
    final wasOnline = _isOnline;
    final online = widget.serverOnline &&
        await CountRecordOfflineSync.instance
            .isOnline(Supabase.instance.client);
    if (mounted) setState(() => _isOnline = online);
    if (online && !wasOnline) {
      await _trySyncPending(silent: false);
    }
  }

  void _syncOfflinePollTimer() {
    if (_pendingCount > 0) {
      _offlineSyncTicker ??= Timer.periodic(
        const Duration(seconds: 10),
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
    if (_pendingCount == 0) return;
    if (!widget.serverOnline) return;
    if (!await CountRecordOfflineSync.instance
        .isOnline(Supabase.instance.client)) {
      return;
    }
    await _trySyncPending(silent: true);
  }

  Future<void> _refreshPendingCount() async {
    final count = await CountRecordOfflineSync.instance.pendingCount();
    if (mounted) {
      setState(() => _pendingCount = count);
      _syncOfflinePollTimer();
    }
  }

  Future<void> _trySyncPending({bool silent = false}) async {
    final synced = await CountRecordOfflineSync.instance.syncPending(
      widget.service,
      Supabase.instance.client,
    );
    if (synced > 0) {
      widget.onDataChanged?.call();
      if (!silent && mounted) {
        _toast('อัปโหลดข้อมูล $synced รายการเข้าระบบแล้ว');
      }
      if (!mounted) return;
      final merged = await CountRecordOfflineSync.instance.mergeForDayAsync(
        widget.dateYmd,
        widget.dayTransactions,
      );
      if (!mounted) return;
      setState(() {
        _units.clear();
        _bootstrapFromTransactions(merged);
      });
    }
    await _refreshPendingCount();
    if (!widget.serverOnline) {
      if (mounted) setState(() => _isOnline = false);
      return;
    }
    final online = await CountRecordOfflineSync.instance
        .isOnline(Supabase.instance.client);
    if (mounted) setState(() => _isOnline = online);
  }

  List<AppTransaction> _effectiveDayRows() {
    final base = widget.dayTransactions
        .where((t) => t.date == widget.dateYmd)
        .toList();
    final byId = {for (final t in base) t.id: t};
    for (final u in _units) {
      byId[u.txId] = _txFor(u);
    }
    return byId.values.toList();
  }

  _CounterUnit _unitFromTx(
    AppTransaction t, {
    required String title,
    String? vehicleId,
    bool roundsFromDrums = false,
  }) {
    final wa = t.workAssignments ?? const <String, List<String>>{};
    final laps = List<String>.from(wa['lapTimes'] ?? const []);
    final rounds = roundsFromDrums
        ? (t.drumsObtained ?? 0).round()
        : (t.perCarTrips ?? t.tripCount ?? 0).round();
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

  Future<void> _loadCars() async {
    final sync = CountRecordOfflineSync.instance;
    if (!widget.serverOnline) {
      final cached = await sync.readCachedCars();
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _cars = cached.where(isVehicleTripDrumCarName).toList(growable: false);
        });
      }
      return;
    }
    final client = Supabase.instance.client;
    try {
      if (await sync.isOnline(client)) {
        final rows = await client
            .from('app_settings')
            .select('cars')
            .eq('id', 'default')
            .limit(1);
        if (rows.isEmpty) return;
        final raw = rows.first['cars'];
        final all = <String>[
          if (raw is List)
            ...raw.map((e) => '$e').where((e) => e.trim().isNotEmpty),
        ];
        final cars = all.where(isVehicleTripDrumCarName).toList(growable: false);
        await sync.cacheCars(cars);
        if (!mounted) return;
        setState(() => _cars = cars);
        return;
      }
    } catch (_) {}
    final cached = await sync.readCachedCars();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _cars = cached.where(isVehicleTripDrumCarName).toList(growable: false);
      });
    }
  }

  AppTransaction _txFor(_CounterUnit u) {
    final assignments = <String, List<String>>{};
    if (u.lapTimes.isNotEmpty) {
      assignments['lapTimes'] = List<String>.from(u.lapTimes);
    }
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
        workAssignments: assignments.isEmpty ? null : assignments,
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
      workAssignments: assignments.isEmpty ? null : assignments,
    );
  }

  Future<bool> _save(_CounterUnit u) async {
    final wasPersisted = u.persisted;
    final queued = await CountRecordOfflineSync.instance.persist(
      service: widget.service,
      client: Supabase.instance.client,
      transaction: _txFor(u),
      omitCreatedAt: wasPersisted,
      dayServerRows: _effectiveDayRows(),
      serverOnlineHint: widget.serverOnline,
    );
    u.persisted = true;
    if (!widget.serverOnline) {
      if (mounted) setState(() => _isOnline = false);
      await _refreshPendingCount();
    } else {
      await _refreshConnectivity();
      await _refreshPendingCount();
    }
    return queued;
  }

  /// กดปุ่ม = บันทึกวันเวลา + เพิ่มจำนวน 1 (จำกัด 1 ครั้งทุก 3 วินาทีต่อปุ่ม)
  Future<void> _recordTap(_CounterUnit u) async {
    if (u.busy) return;
    if (u.isOnRecordCooldown) return;
    final prevRounds = u.rounds;
    final prevLaps = List<String>.from(u.lapTimes);
    final stamp = _stamp(DateTime.now());
    _armRecordCooldown(u);
    setState(() {
      u.busy = true;
      u.rounds += 1;
      u.lapTimes.add(stamp);
    });
    HapticFeedback.selectionClick();
    unawaited(RecordFeedbackSound.playRecordTap());
    try {
      final queued = await _save(u);
      if (mounted) {
        HapticFeedback.mediumImpact();
        unawaited(RecordSuccessSpeaker.instance.speakSuccess());
        final base = widget.mode == CounterMode.trip
            ? '${u.title} • เที่ยวที่ ${u.rounds} • $stamp'
            : 'รอบที่ ${u.rounds} • $stamp';
        _toast(
          queued
              ? '$base\n(บันทึกในเครื่องแล้ว — จะอัปโหลดทันทีเมื่อมีเน็ต)'
              : base,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          u.rounds = prevRounds;
          u.lapTimes
            ..clear()
            ..addAll(prevLaps);
        });
        _toast('บันทึกไม่สำเร็จ: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => u.busy = false);
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
    if (ok == true) await _undoLastRecord(u);
  }

  Future<void> _undoLastRecord(_CounterUnit u) async {
    if (u.busy || u.rounds <= 0 || u.lapTimes.isEmpty) return;
    final isTrip = widget.mode == CounterMode.trip;
    final prevRounds = u.rounds;
    final prevLaps = List<String>.from(u.lapTimes);
    final removedStamp = u.lapTimes.last;
    setState(() {
      u.busy = true;
      u.rounds -= 1;
      u.lapTimes.removeLast();
    });
    try {
      await _save(u);
      if (mounted) {
        _toast(
          isTrip
              ? 'ลบเที่ยวล่าสุดแล้ว • $removedStamp'
              : 'ลบรอบล่าสุดแล้ว • $removedStamp',
        );
      }
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
    } finally {
      if (mounted) setState(() => u.busy = false);
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
    if (ok == true) await _removeUnit(u);
  }

  Future<void> _removeUnit(_CounterUnit u) async {
    if (u.busy) return;
    setState(() => u.busy = true);
    try {
      var queued = false;
      if (u.persisted) {
        queued = await CountRecordOfflineSync.instance.delete(
          service: widget.service,
          client: Supabase.instance.client,
          id: u.txId,
          ymd: widget.dateYmd,
          dayServerRows: _effectiveDayRows(),
          serverOnlineHint: widget.serverOnline,
        );
        if (!widget.serverOnline) {
          if (mounted) setState(() => _isOnline = false);
          await _refreshPendingCount();
        } else {
          await _refreshConnectivity();
          await _refreshPendingCount();
        }
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
    if (_cars.isEmpty) {
      _toast('ยังไม่พบรายการรถ (ดรัม/หกล้อ/สิบล้อ) ในตั้งค่าแอพ', error: true);
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
        cars: _cars,
        drivers: _drivers,
        alreadyAdded: already,
      ),
    );
    if (picks == null) return;
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
      setState(() => _units.add(unit));
      try {
        await _save(unit);
      } catch (_) {
        if (mounted) setState(() => _units.remove(unit));
      }
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
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.car_crash_outlined, color: Color(0xFFE65100)),
              title: const Text(
                'แจ้งรถเสีย',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                u.isBrokenReported ? 'แจ้งแล้ววันนี้' : 'บันทึกสถานะรถเสียลงระบบ',
                style: const TextStyle(fontSize: 12.5),
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
    }
  }

  Future<void> _openChangeDriverDialog(_CounterUnit u) async {
    if (_drivers.isEmpty) {
      _toast('ยังไม่พบพนักงานตำแหน่ง "คนขับรถ"', error: true);
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
    if (driverId == null) return;
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
    if (ok != true) return;

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

  void _toggleAddVehiclePanel() {
    HapticFeedback.lightImpact();
    setState(() => _addVehiclePanelOpen = !_addVehiclePanelOpen);
  }

  void _hideAddVehiclePanel() {
    if (!_addVehiclePanelOpen) return;
    setState(() => _addVehiclePanelOpen = false);
  }

  Widget _buildTripPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _units.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'แตะแถบ «บันทึกล่าสุด» ด้านล่าง\nเพื่อเพิ่มรถและคนขับ',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < _units.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _SwipeRevealActions(
                            onDelete: () => _confirmRemoveUnit(_units[i]),
                            onEdit: () => _openEditUnitMenu(_units[i]),
                            childBuilder: (interactionsEnabled) =>
                                _VehicleRecordButton(
                              unit: _units[i],
                              index: i,
                              interactionsEnabled: interactionsEnabled,
                              onTap: () => _recordTap(_units[i]),
                              onHoldToUndo: () =>
                                  _confirmUndoLastRecord(_units[i]),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          _LatestTripRecordsBar(
            expanded: _addVehiclePanelOpen,
            units: _units,
            onTap: _toggleAddVehiclePanel,
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: _addVehiclePanelOpen
                ? Padding(
                    key: const ValueKey('add_vehicle_panel'),
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
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
                  )
                : const SizedBox.shrink(key: ValueKey('add_vehicle_hidden')),
          ),
        ],
      ),
    );
  }

  Widget _buildSandPanel() {
    final u = _sandUnit;
    if (u == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _SandRecordButton(
              unit: u,
              onTap: () => _recordTap(u),
              onHoldToUndo: () => _confirmUndoLastRecord(u),
            ),
          ),
          if (u.lapTimes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = _recentSandLapStartIndex(u.lapTimes.length);
                    i < u.lapTimes.length;
                    i++)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFDCE6F2)),
                    ),
                    child: Text(
                      'รอบ ${i + 1} • ${u.lapTimes[i]}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF52647B),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget? _buildSyncBanner() {
    if (_isOnline && _pendingCount == 0) return null;
    final message = !_isOnline
        ? (_pendingCount > 0
            ? 'ไม่มีเน็ต • บันทึกในเครื่อง $_pendingCount รายการ'
            : 'ไม่มีเน็ต — บันทึกเก็บในเครื่องก่อน')
        : 'เชื่อมต่อเน็ตแล้ว • รออัปโหลด $_pendingCount รายการ';
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: !_isOnline ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: !_isOnline ? const Color(0xFFFFCC80) : const Color(0xFFA5D6A7),
        ),
      ),
      child: Row(
        children: [
          Icon(
            !_isOnline ? Icons.cloud_off_outlined : Icons.cloud_upload_outlined,
            size: 18,
            color: !_isOnline ? const Color(0xFFE65100) : const Color(0xFF2E7D32),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: !_isOnline
                    ? const Color(0xFFBF360C)
                    : const Color(0xFF1B5E20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final banner = _buildSyncBanner();
    final body = widget.mode == CounterMode.trip
        ? _buildTripPanel()
        : _buildSandPanel();
    if (banner == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        banner,
        Expanded(child: body),
      ],
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
  final Widget Function(bool interactionsEnabled) childBuilder;

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

  void _snap({required _SwipeRevealSide side}) {
    setState(() {
      _revealed = side;
      _offset = switch (side) {
        _SwipeRevealSide.delete => -_actionWidth,
        _SwipeRevealSide.edit => _actionWidth,
        _ => 0.0,
      };
      _dragging = false;
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    final dx = event.delta.dx;
    final dy = event.delta.dy;
    if (!_dragging) {
      if (dx.abs() < 4 || dx.abs() <= dy.abs()) return;
      if (dx < 0 || _revealed == _SwipeRevealSide.delete) {
        setState(() => _dragging = true);
      } else if (dx > 0 || _revealed == _SwipeRevealSide.edit) {
        setState(() => _dragging = true);
      }
    }
    if (!_dragging) return;
    setState(() {
      _offset = (_offset + dx).clamp(-_actionWidth, _actionWidth);
    });
  }

  void _onPointerUp() {
    if (_dragging) {
      if (_offset <= -_actionWidth / 2) {
        _snap(side: _SwipeRevealSide.delete);
      } else if (_offset >= _actionWidth / 2) {
        _snap(side: _SwipeRevealSide.edit);
      } else {
        _snap(side: _SwipeRevealSide.none);
      }
      return;
    }
    if (_revealed != _SwipeRevealSide.none) {
      _snap(side: _SwipeRevealSide.none);
    }
  }

  void _onPointerCancel() {
    if (_dragging) {
      if (_offset <= -_actionWidth / 2) {
        _snap(side: _SwipeRevealSide.delete);
      } else if (_offset >= _actionWidth / 2) {
        _snap(side: _SwipeRevealSide.edit);
      } else {
        _snap(side: _SwipeRevealSide.none);
      }
      return;
    }
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
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _dragging = false,
                onPointerMove: _onPointerMove,
                onPointerUp: (_) => _onPointerUp(),
                onPointerCancel: (_) => _onPointerCancel(),
                child: AnimatedContainer(
                  duration: _dragging
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(offset, 0, 0),
                  child: widget.childBuilder(_interactionsEnabled),
                ),
              ),
              if (_revealed == _SwipeRevealSide.edit)
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
              if (_revealed == _SwipeRevealSide.delete)
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

/// ปุ่มบันทึกแบบยกนูน + เอฟเฟกต์ตอนกด + อนิเมชัน idle ชวนกด
class _RecordButtonShell extends StatefulWidget {
  const _RecordButtonShell({
    required this.bgColor,
    required this.shadowColor,
    required this.busy,
    required this.dimmed,
    required this.pressed,
    required this.idleAnimate,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onPointerCancel,
    required this.child,
    this.busyBgColor,
    this.bottomOverlay,
    this.idlePhase = 0,
  });

  final Color bgColor;
  final Color shadowColor;
  final bool busy;
  final bool dimmed;
  final bool pressed;
  final bool idleAnimate;
  final double idlePhase;
  final VoidCallback onPointerDown;
  final VoidCallback onPointerUp;
  final VoidCallback onPointerCancel;
  final Widget child;
  final Color? busyBgColor;
  final Widget? bottomOverlay;

  @override
  State<_RecordButtonShell> createState() => _RecordButtonShellState();
}

class _RecordButtonShellState extends State<_RecordButtonShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idleCtrl;
  late final Animation<double> _idleScale;
  late final Animation<double> _idleLift;
  late final Animation<double> _idleGlow;

  @override
  void initState() {
    super.initState();
    _idleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
    _idleScale = Tween<double>(begin: 1.0, end: 1.028).animate(
      CurvedAnimation(parent: _idleCtrl, curve: Curves.easeInOut),
    );
    _idleLift = Tween<double>(begin: -6.0, end: -11.0).animate(
      CurvedAnimation(parent: _idleCtrl, curve: Curves.easeInOut),
    );
    _idleGlow = Tween<double>(begin: 0.12, end: 0.34).animate(
      CurvedAnimation(parent: _idleCtrl, curve: Curves.easeInOut),
    );
    if (widget.idlePhase > 0) {
      _idleCtrl.value = widget.idlePhase % 1.0;
    }
    _syncIdleAnimation();
  }

  @override
  void didUpdateWidget(covariant _RecordButtonShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.idleAnimate != widget.idleAnimate) {
      _syncIdleAnimation();
    }
  }

  void _syncIdleAnimation() {
    if (widget.idleAnimate) {
      if (!_idleCtrl.isAnimating) {
        _idleCtrl.repeat(reverse: true);
      }
    } else {
      _idleCtrl.stop();
      _idleCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _idleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final idle = widget.idleAnimate && !widget.pressed;
    final lifted = !widget.busy && !widget.dimmed;
    final pressScale = widget.pressed ? 0.96 : 1.0;
    final bg = widget.busy
        ? (widget.busyBgColor ?? widget.bgColor.withValues(alpha: 0.55))
        : widget.dimmed
            ? widget.bgColor.withValues(alpha: 0.72)
            : widget.bgColor;

    return AnimatedBuilder(
      animation: _idleCtrl,
      builder: (context, child) {
        final idleScale = idle ? _idleScale.value : 1.0;
        final liftY = widget.pressed
            ? 0.0
            : idle
                ? _idleLift.value
                : (lifted ? -6.0 : 0.0);
        final elevation = widget.busy
            ? 0.0
            : widget.pressed
                ? 3.0
                : idle
                    ? 10.0 + 6.0 * _idleCtrl.value
                    : 12.0;
        final glowAlpha = idle ? _idleGlow.value : 0.0;

        return Transform.scale(
          scale: pressScale * idleScale,
          child: Transform.translate(
            offset: Offset(0, liftY),
            child: Material(
              elevation: elevation,
              shadowColor: widget.shadowColor.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              color: bg,
              clipBehavior: Clip.antiAlias,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => widget.onPointerDown(),
                onPointerUp: (_) => widget.onPointerUp(),
                onPointerCancel: (_) => widget.onPointerCancel(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (glowAlpha > 0)
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: glowAlpha),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    widget.child,
                    ?widget.bottomOverlay,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// แถบ «บันทึกล่าสุด» — แตะเพื่อแสดง/ซ่อนเพิ่มรถ
class _LatestTripRecordsBar extends StatelessWidget {
  const _LatestTripRecordsBar({
    required this.expanded,
    required this.units,
    required this.onTap,
  });

  final bool expanded;
  final List<_CounterUnit> units;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final withLaps =
        units.where((u) => u.lapTimes.isNotEmpty).toList(growable: false);
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
                    const Spacer(),
                    Text(
                      expanded ? 'ซ่อน' : 'เพิ่มรถ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: expanded
                            ? const Color(0xFF1565C0)
                            : const Color(0xFF78909C),
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
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
                if (withLaps.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...withLaps.map(
                    (u) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${u.title}: ${u.lapTimes.last} (${u.rounds} เที่ยว)',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF52647B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      expanded
                          ? 'เลือกรถด้านล่าง'
                          : 'แตะแถบนี้เพื่อเพิ่มรถ',
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
    this.interactionsEnabled = true,
  });

  final _CounterUnit unit;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onHoldToUndo;
  final bool interactionsEnabled;

  @override
  State<_VehicleRecordButton> createState() => _VehicleRecordButtonState();
}

class _VehicleRecordButtonState extends State<_VehicleRecordButton> {
  static const _holdDuration = Duration(seconds: 3);
  static const _tapMax = Duration(milliseconds: 400);

  Timer? _holdTimer;
  DateTime? _pointerDownAt;
  double _holdProgress = 0;
  bool _holdTriggered = false;
  bool _isPressed = false;

  bool get _canPress =>
      !widget.unit.busy &&
      widget.interactionsEnabled &&
      !widget.unit.isOnRecordCooldown;

  @override
  void dispose() {
    _holdTimer?.cancel();
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
        HapticFeedback.heavyImpact();
        setState(() => _holdProgress = 0);
        widget.onHoldToUndo();
      }
    });
  }

  void _onPointerDown() {
    if (widget.unit.busy || !widget.interactionsEnabled) return;
    if (_canPress) {
      setState(() => _isPressed = true);
      HapticFeedback.lightImpact();
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

    if (widget.unit.busy || downAt == null || !widget.interactionsEnabled) return;
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
    final unit = widget.unit;
    final busy = unit.busy;
    final onCooldown = unit.isOnRecordCooldown && !busy;
    final bg = _vehicleButtonColor(widget.index);
    final carNo = widget.index + 1;
    return _RecordButtonShell(
      bgColor: bg,
      shadowColor: bg,
      busy: busy,
      dimmed: onCooldown,
      pressed: _isPressed,
      idleAnimate: !busy &&
          !onCooldown &&
          !_isPressed &&
          widget.interactionsEnabled &&
          _holdProgress <= 0,
      idlePhase: widget.index * 0.17,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _VehicleTripCountRail(
                    rounds: unit.rounds,
                    onCooldown: onCooldown,
                    cooldownSecondsLeft: unit.recordCooldownSecondsLeft,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
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
                            'คันที่ $carNo • บันทึกเที่ยว',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (unit.isBrokenReported) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE0B2),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.car_crash_outlined,
                                    size: 12, color: Color(0xFFE65100)),
                                SizedBox(width: 4),
                                Text(
                                  'แจ้งรถเสีย',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFE65100),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
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
                        const SizedBox(height: 6),
                        Text(
                          unit.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.95),
                            height: 1.15,
                          ),
                        ),
                        if (unit.lapTimes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'ล่าสุด ${unit.lapTimes.last}',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Colors.white.withValues(alpha: 0.82),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// แถบซ้ายของการ์ดรถ — ไอคอน + จำนวนเที่ยว
class _VehicleTripCountRail extends StatelessWidget {
  const _VehicleTripCountRail({
    required this.rounds,
    required this.onCooldown,
    required this.cooldownSecondsLeft,
  });

  final int rounds;
  final bool onCooldown;
  final int cooldownSecondsLeft;

  @override
  Widget build(BuildContext context) {
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
          Icon(
            Icons.add_circle_rounded,
            size: 30,
            color: Colors.white.withValues(alpha: onCooldown ? 0.55 : 0.98),
          ),
          const SizedBox(height: 6),
          Text(
            '$rounds',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white.withValues(alpha: onCooldown ? 0.7 : 1),
              height: 1,
            ),
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

/// วงกลมกลางการ์ดร่อนทราย — แสดงรวมจำนวนรอบ
class _SandRoundCountHero extends StatelessWidget {
  const _SandRoundCountHero({
    required this.rounds,
    required this.dimmed,
  });

  final int rounds;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
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
            Text(
              '$rounds',
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
  }
}

class _SandRecordButton extends StatefulWidget {
  const _SandRecordButton({
    required this.unit,
    required this.onTap,
    required this.onHoldToUndo,
  });

  final _CounterUnit unit;
  final VoidCallback onTap;
  final VoidCallback onHoldToUndo;

  @override
  State<_SandRecordButton> createState() => _SandRecordButtonState();
}

class _SandRecordButtonState extends State<_SandRecordButton> {
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
  void dispose() {
    _holdTimer?.cancel();
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
        HapticFeedback.heavyImpact();
        setState(() => _holdProgress = 0);
        widget.onHoldToUndo();
      }
    });
  }

  void _onPointerDown() {
    if (widget.unit.busy) return;
    if (_canPress) {
      setState(() => _isPressed = true);
      HapticFeedback.lightImpact();
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
    final unit = widget.unit;
    final busy = unit.busy;
    final onCooldown = unit.isOnRecordCooldown && !busy;
    return _RecordButtonShell(
      bgColor: _sandBg,
      busyBgColor: _sandBgBusy,
      shadowColor: _sandBg,
      busy: busy,
      dimmed: onCooldown,
      pressed: _isPressed,
      idleAnimate:
          !busy && !onCooldown && !_isPressed && _holdProgress <= 0,
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
        borderRadius: BorderRadius.circular(16),
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
            Positioned(
              top: -28,
              right: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              bottom: -36,
              left: -24,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                  : Column(
                      children: [
                        Row(
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
                                  color: Colors.white.withValues(alpha: 0.95),
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Center(
                            child: _SandRoundCountHero(
                              rounds: unit.rounds,
                              dimmed: onCooldown,
                            ),
                          ),
                        ),
                        Text(
                          onCooldown
                              ? 'รอ ${unit.recordCooldownSecondsLeft} วินาที'
                              : 'แตะการ์ดเพื่อบันทึก +1 รอบ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(
                              alpha: onCooldown ? 0.75 : 0.88,
                            ),
                          ),
                        ),
                        if (unit.lapTimes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Text(
                              'ล่าสุด ${unit.lapTimes.last}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
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
  });

  final List<String> cars;
  final List<Employee> drivers;
  final Set<String> alreadyAdded;

  @override
  State<_SelectDialog> createState() => _SelectDialogState();
}

class _SelectDialogState extends State<_SelectDialog> {
  final List<_Pick> _rows = [_Pick()];

  List<String> get _availableCars => widget.cars
      .where((c) => !widget.alreadyAdded.contains(c))
      .toList(growable: false);

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
                          canRemove: _rows.length > 1,
                          onRemove: () =>
                              setState(() => _rows.removeAt(i)),
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
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final _Pick row;
  final List<String> cars;
  final List<Employee> drivers;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final carOptions = <String>[
      if (row.vehicleId.isNotEmpty && !cars.contains(row.vehicleId))
        row.vehicleId,
      ...cars,
    ];
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
                    child: Text(c,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (v) {
              row.vehicleId = v ?? '';
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: (row.driverId.isEmpty ||
                    !drivers.any((e) => e.id == row.driverId))
                ? null
                : row.driverId,
            decoration: const InputDecoration(
              labelText: 'คนขับ',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
            items: drivers
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
            onChanged: (v) {
              row.driverId = v ?? '';
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}
