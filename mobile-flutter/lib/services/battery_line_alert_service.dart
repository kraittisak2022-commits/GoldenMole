import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/advance_line_notify.dart';
import 'session_service.dart';

/// ขั้นที่แจ้งแบตต่ำ (ต่ำกว่า 15%, ≤10%, ≤5%)
const List<int> kBatteryAlertSteps = [15, 10, 5];

/// แบตกลับขึ้นถึงระดับนี้ = เริ่มนับรอบแจ้งใหม่ (กันแจ้งรัวตอนแบตแกว่งรอบ 15%)
const int kBatteryAlertResetLevel = 20;

const _kBatteryAlertStepPrefsKey = 'gm_battery_alert_step_v1';

enum BatteryAlertKind { none, low, chargingStarted, reset }

class BatteryAlertDecision {
  const BatteryAlertDecision._(this.kind, [this.step]);

  const BatteryAlertDecision.none() : this._(BatteryAlertKind.none);
  const BatteryAlertDecision.low(int step) : this._(BatteryAlertKind.low, step);
  const BatteryAlertDecision.chargingStarted()
      : this._(BatteryAlertKind.chargingStarted);
  const BatteryAlertDecision.reset() : this._(BatteryAlertKind.reset);

  final BatteryAlertKind kind;

  /// ขั้นที่ต้องแจ้ง — มีค่าเฉพาะ [BatteryAlertKind.low]
  final int? step;
}

bool _levelReachesStep(int level, int step) =>
    step == kBatteryAlertSteps.first ? level < step : level <= step;

/// ตัดสินว่าต้องแจ้ง LINE หรือไม่ — [lastStep] = ขั้นที่แจ้งไปแล้วรอบนี้ (null = ยังไม่แจ้ง)
///
/// ลดข้ามหลายขั้นในรอบเดียวจะแจ้งครั้งเดียวที่ขั้นต่ำสุด
BatteryAlertDecision decideBatteryAlert({
  required int level,
  required bool charging,
  required int? lastStep,
}) {
  if (charging) {
    return lastStep != null
        ? const BatteryAlertDecision.chargingStarted()
        : const BatteryAlertDecision.none();
  }
  if (level >= kBatteryAlertResetLevel) {
    return lastStep != null
        ? const BatteryAlertDecision.reset()
        : const BatteryAlertDecision.none();
  }
  int? target;
  for (final step in kBatteryAlertSteps) {
    if (_levelReachesStep(level, step)) target = step;
  }
  if (target == null) return const BatteryAlertDecision.none();
  if (lastStep != null && target >= lastStep) {
    return const BatteryAlertDecision.none();
  }
  return BatteryAlertDecision.low(target);
}

String _formatBatteryAlertTimeTh(DateTime t) {
  const mm = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];
  final hh = t.hour.toString().padLeft(2, '0');
  final mi = t.minute.toString().padLeft(2, '0');
  return '${t.day} ${mm[t.month - 1]} ${t.year + 543} $hh:$mi';
}

String buildBatteryLowLineText({
  required int level,
  required String device,
  required String user,
  required DateTime now,
}) {
  return [
    '━━━━ GoldenMole ━━━━',
    '',
    'แบตแท็บเล็ตใกล้หมด',
    'เครื่อง: $device',
    if (user.trim().isNotEmpty) 'ผู้ใช้: ${user.trim()}',
    'แบตเหลือ: $level%',
    'เวลา: ${_formatBatteryAlertTimeTh(now)}',
    '',
    'กรุณาเสียบชาร์จ เพื่อไม่ให้การนับเที่ยว/ร่อนทรายหยุด',
  ].join('\n');
}

String buildBatteryChargingLineText({
  required int level,
  required String device,
  required DateTime now,
}) {
  return [
    '━━━━ GoldenMole ━━━━',
    '',
    'แท็บเล็ตเริ่มชาร์จแล้ว (แบต $level%)',
    'เครื่อง: $device',
    'เวลา: ${_formatBatteryAlertTimeTh(now)}',
  ].join('\n');
}

/// ตรวจแบตขณะเปิดเมนู «บันทึกและนับจำนวน» แล้วแจ้งกลุ่ม LINE เมื่อแบตต่ำ
class BatteryLineAlertService {
  BatteryLineAlertService._();

  static final BatteryLineAlertService instance = BatteryLineAlertService._();

  static const _checkInterval = Duration(seconds: 60);

  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _stateSub;
  Timer? _timer;
  int _activeUsers = 0;
  bool _checking = false;
  String? _deviceLabel;

  void start() {
    _activeUsers++;
    if (_activeUsers > 1) return;
    try {
      _stateSub = _battery.onBatteryStateChanged.listen(
        (_) => unawaited(check()),
        onError: (Object e) => debugPrint('battery state stream: $e'),
      );
    } catch (e) {
      debugPrint('battery state stream: $e');
    }
    _timer = Timer.periodic(_checkInterval, (_) => unawaited(check()));
    unawaited(check());
  }

  void stop() {
    if (_activeUsers == 0) return;
    _activeUsers--;
    if (_activeUsers > 0) return;
    _timer?.cancel();
    _timer = null;
    unawaited(_stateSub?.cancel());
    _stateSub = null;
  }

  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      final level = await _battery.batteryLevel;
      if (level < 0 || level > 100) return;
      final state = await _battery.batteryState;
      final charging = state == BatteryState.charging ||
          state == BatteryState.full ||
          state == BatteryState.connectedNotCharging;
      final prefs = await SharedPreferences.getInstance();
      final lastStep = prefs.getInt(_kBatteryAlertStepPrefsKey);
      final decision = decideBatteryAlert(
        level: level,
        charging: charging,
        lastStep: lastStep,
      );
      switch (decision.kind) {
        case BatteryAlertKind.none:
          return;
        case BatteryAlertKind.reset:
          await prefs.remove(_kBatteryAlertStepPrefsKey);
          return;
        case BatteryAlertKind.low:
          // บันทึกขั้นก่อนส่ง — กันส่งซ้ำทุกนาทีถ้าส่งไม่สำเร็จ (ออฟไลน์จะเข้าคิวส่งซ้ำเอง)
          await prefs.setInt(_kBatteryAlertStepPrefsKey, decision.step!);
          final admin = await SessionService().getSavedAdmin();
          final user = (admin?.displayName.trim().isNotEmpty ?? false)
              ? admin!.displayName
              : (admin?.username ?? '');
          await notifyAdminLineGroups(
            text: buildBatteryLowLineText(
              level: level,
              device: await _resolveDeviceLabel(),
              user: user,
              now: DateTime.now(),
            ),
            debugTag: 'batteryLowLineAlert',
          );
          return;
        case BatteryAlertKind.chargingStarted:
          await prefs.remove(_kBatteryAlertStepPrefsKey);
          await notifyAdminLineGroups(
            text: buildBatteryChargingLineText(
              level: level,
              device: await _resolveDeviceLabel(),
              now: DateTime.now(),
            ),
            debugTag: 'batteryChargingLineAlert',
          );
          return;
      }
    } catch (e, st) {
      debugPrint('BatteryLineAlertService.check: $e\n$st');
    } finally {
      _checking = false;
    }
  }

  Future<String> _resolveDeviceLabel() async {
    final cached = _deviceLabel;
    if (cached != null) return cached;
    var label = 'แท็บเล็ต';
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final l = '${info.brand} ${info.model}'.trim();
        if (l.isNotEmpty) label = l;
      } else if (Platform.isIOS) {
        label = (await plugin.iosInfo).utsname.machine;
      }
    } catch (e) {
      debugPrint('battery alert device info: $e');
    }
    _deviceLabel = label;
    return label;
  }
}
