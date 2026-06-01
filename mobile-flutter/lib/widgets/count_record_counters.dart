import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user.dart';
import '../models/app_transaction.dart';
import '../models/employee.dart';
import '../services/employee_service.dart';
import '../services/transaction_service.dart';
import '../utils/daily_module_transactions.dart';

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
  }) : lapTimes = lapTimes ?? <String>[];

  final String txId;
  String title;
  String subtitle;
  int rounds;
  final List<String> lapTimes;
  bool persisted;
  String? vehicleId;
  String? driverId;
  bool busy = false;
}

class _Pick {
  String vehicleId = '';
  String driverId = '';
}

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
  });

  final CounterMode mode;
  final TransactionService service;
  final EmployeeService employeeService;
  final AdminUser currentAdmin;
  final String dateYmd;
  final List<AppTransaction> dayTransactions;
  final List<Employee> employees;
  final bool embedded;

  @override
  State<CountRecordCounterPanel> createState() =>
      _CountRecordCounterPanelState();
}

class _CountRecordCounterPanelState extends State<CountRecordCounterPanel>
    with AutomaticKeepAliveClientMixin {
  final List<_CounterUnit> _units = [];
  List<String> _cars = const [];
  List<Employee> _drivers = const [];

  @override
  bool get wantKeepAlive => true;

  _CounterUnit? get _sandUnit =>
      _units.isEmpty ? null : _units.first;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  void _bootstrap() {
    _drivers = widget.employees
        .where((e) => !e.inactive)
        .where(_isDriverEmployee)
        .toList(growable: false);

    if (widget.mode == CounterMode.trip) {
      for (final t in widget.dayTransactions) {
        if (t.category != 'DailyLog') continue;
        if ((t.subCategory ?? '').trim().toLowerCase() != 'vehicletrip') {
          continue;
        }
        final vid = (t.vehicleId ?? '').trim();
        if (vid.isEmpty || isMacroVehicleId(vid)) continue;
        _units.add(_unitFromTx(t, title: vid, vehicleId: vid));
      }
      _loadCars();
      if (_units.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openSelectDialog();
        });
      }
    } else {
      AppTransaction? sandRow;
      for (final t in widget.dayTransactions) {
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
    try {
      final client = Supabase.instance.client;
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
      if (!mounted) return;
      setState(() {
        _cars = all.where(isVehicleTripDrumCarName).toList(growable: false);
      });
    } catch (_) {}
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

  Future<void> _save(_CounterUnit u) async {
    final wasPersisted = u.persisted;
    await widget.service.upsertTransaction(
      _txFor(u),
      omitCreatedAt: wasPersisted,
    );
    u.persisted = true;
  }

  /// กดปุ่ม = บันทึกวันเวลา + เพิ่มจำนวน 1
  Future<void> _recordTap(_CounterUnit u) async {
    if (u.busy) return;
    final prevRounds = u.rounds;
    final prevLaps = List<String>.from(u.lapTimes);
    final stamp = _stamp(DateTime.now());
    setState(() {
      u.busy = true;
      u.rounds += 1;
      u.lapTimes.add(stamp);
    });
    HapticFeedback.selectionClick();
    try {
      await _save(u);
      if (mounted) {
        _toast(
          widget.mode == CounterMode.trip
              ? '${u.title} • เที่ยวที่ ${u.rounds} • $stamp'
              : 'รอบที่ ${u.rounds} • $stamp',
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
      if (u.persisted) await widget.service.deleteTransaction(u.txId);
      if (mounted) {
        setState(() => _units.remove(u));
        _toast('ลบ ${u.title} ออกจากรายการแล้ว');
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

  Widget _buildTripPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _units.isEmpty
                ? Center(
                    child: Text(
                      'กด "เพิ่มรถ" เพื่อเลือกรถและคนขับ\nจากนั้นกดปุ่มชื่อรถเพื่อบันทึกเที่ยว',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < _units.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _SwipeRevealDelete(
                            onDelete: () => _confirmRemoveUnit(_units[i]),
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
          if (_units.any((u) => u.lapTimes.isNotEmpty)) ...[
            const SizedBox(height: 8),
            const Text(
              'บันทึกล่าสุด',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7788),
              ),
            ),
            const SizedBox(height: 4),
            ..._units.where((u) => u.lapTimes.isNotEmpty).map(
                  (u) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${u.title}: ${u.lapTimes.last} (${u.rounds} เที่ยว)',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF52647B),
                      ),
                    ),
                  ),
                ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF546E7A),
                backgroundColor: const Color(0xFFF5F7FA),
                side: const BorderSide(color: Color(0xFFB0BEC5), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: _openSelectDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('เพิ่มรถ (ยังไม่บันทึกเที่ยว)'),
            ),
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
                for (var i = 0; i < u.lapTimes.length; i++)
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.mode == CounterMode.trip
        ? _buildTripPanel()
        : _buildSandPanel();
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

/// ปัดการ์ดซ้ายเพื่อแสดงปุ่มลบ
class _SwipeRevealDelete extends StatefulWidget {
  const _SwipeRevealDelete({
    required this.onDelete,
    required this.childBuilder,
  });

  final VoidCallback onDelete;
  final Widget Function(bool interactionsEnabled) childBuilder;

  @override
  State<_SwipeRevealDelete> createState() => _SwipeRevealDeleteState();
}

class _SwipeRevealDeleteState extends State<_SwipeRevealDelete> {
  double _offset = 0;
  bool _revealed = false;
  bool _dragging = false;
  double _actionWidth = 64;

  bool get _interactionsEnabled => !_dragging && !_revealed;

  void _snap({required bool open}) {
    setState(() {
      _revealed = open;
      _offset = open ? -_actionWidth : 0;
      _dragging = false;
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    final dx = event.delta.dx;
    final dy = event.delta.dy;
    if (!_dragging) {
      if (dx.abs() < 4 || dx.abs() <= dy.abs()) return;
      if (dx < 0 || _revealed) {
        setState(() => _dragging = true);
      }
    }
    if (!_dragging) return;
    setState(() {
      _offset = (_offset + dx).clamp(-_actionWidth, 0);
    });
  }

  void _onPointerUp() {
    if (_dragging) {
      _snap(open: _offset <= -_actionWidth / 2);
      return;
    }
    if (_revealed) _snap(open: false);
  }

  void _onPointerCancel() {
    if (_dragging || _revealed) {
      _snap(open: _revealed);
    }
  }

  void _onDeleteTap() {
    _snap(open: false);
    widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _actionWidth = (constraints.maxWidth * 0.36).clamp(52.0, 76.0);
        final offset = _offset.clamp(-_actionWidth, 0.0);
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Material(
                      color: const Color(0xFFD14343),
                      child: InkWell(
                        onTap: _onDeleteTap,
                        child: SizedBox(
                          width: _actionWidth,
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.delete_outline,
                                color: Colors.white,
                                size: 22,
                              ),
                              SizedBox(height: 4),
                              Text(
                                'ลบ',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
            ],
          ),
        );
      },
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
    _pointerDownAt = DateTime.now();
    _holdTriggered = false;
    if (widget.unit.rounds > 0) {
      setState(() => _holdProgress = 0);
      _startHoldTimer();
    }
  }

  void _onPointerUp() {
    final downAt = _pointerDownAt;
    _pointerDownAt = null;
    _holdTimer?.cancel();
    _holdTimer = null;

    if (_holdTriggered) {
      _holdTriggered = false;
      if (mounted) setState(() => _holdProgress = 0);
      return;
    }

    final progress = _holdProgress;
    if (mounted) setState(() => _holdProgress = 0);

    if (widget.unit.busy || downAt == null || !widget.interactionsEnabled) return;
    final elapsed = DateTime.now().difference(downAt);
    if (elapsed <= _tapMax && progress < 0.15) {
      widget.onTap();
    }
  }

  void _onPointerCancel() {
    _pointerDownAt = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    if (mounted) setState(() => _holdProgress = 0);
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    final busy = unit.busy;
    final bg = _vehicleButtonColor(widget.index);
    final carNo = widget.index + 1;
    return Material(
      elevation: busy ? 0 : 2,
      shadowColor: bg.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(16),
      color: busy ? bg.withValues(alpha: 0.55) : bg,
      clipBehavior: Clip.antiAlias,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _onPointerDown(),
        onPointerUp: (_) => _onPointerUp(),
        onPointerCancel: (_) => _onPointerCancel(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
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
                  : Column(
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
                        const SizedBox(height: 8),
                        Text(
                          unit.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          unit.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.88),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_circle,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.95),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${unit.rounds} เที่ยว',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ],
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
                        if (unit.rounds > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            'กดค้าง 3 ว. ลบเที่ยวล่าสุด',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            if (_holdProgress > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: _holdProgress,
                  minHeight: 4,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  color: Colors.white,
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
    _pointerDownAt = DateTime.now();
    _holdTriggered = false;
    if (widget.unit.rounds > 0) {
      setState(() => _holdProgress = 0);
      _startHoldTimer();
    }
  }

  void _onPointerUp() {
    final downAt = _pointerDownAt;
    _pointerDownAt = null;
    _holdTimer?.cancel();
    _holdTimer = null;

    if (_holdTriggered) {
      _holdTriggered = false;
      if (mounted) setState(() => _holdProgress = 0);
      return;
    }

    final progress = _holdProgress;
    if (mounted) setState(() => _holdProgress = 0);

    if (widget.unit.busy || downAt == null) return;
    final elapsed = DateTime.now().difference(downAt);
    if (elapsed <= _tapMax && progress < 0.15) {
      widget.onTap();
    }
  }

  void _onPointerCancel() {
    _pointerDownAt = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    if (mounted) setState(() => _holdProgress = 0);
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    final busy = unit.busy;
    return Material(
      elevation: busy ? 0 : 3,
      shadowColor: _sandBg.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(16),
      color: busy ? _sandBgBusy : _sandBg,
      clipBehavior: Clip.antiAlias,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _onPointerDown(),
        onPointerUp: (_) => _onPointerUp(),
        onPointerCancel: (_) => _onPointerCancel(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: busy
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.water_drop, size: 14, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'บันทึกร่อนทราย',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Icon(Icons.touch_app_rounded,
                            size: 32, color: Colors.white),
                        const SizedBox(height: 8),
                        const Text(
                          'กดบันทึกวันเวลา +1 รอบ',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'รวม ${unit.rounds} รอบ',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        if (unit.lapTimes.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'ล่าสุด ${unit.lapTimes.last}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                        if (unit.rounds > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            'กดค้าง 3 ว. ลบรอบล่าสุด',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            if (_holdProgress > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: _holdProgress,
                  minHeight: 4,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  color: Colors.white,
                ),
              ),
          ],
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
