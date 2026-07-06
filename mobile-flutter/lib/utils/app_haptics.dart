import 'package:flutter/services.dart';

/// ภาษาสัมผัสกลาง — ใช้แทน [HapticFeedback] ตรงๆ ทั้งแอป
class AppHaptics {
  AppHaptics._();

  static DateTime _lastThrottled = DateTime.fromMillisecondsSinceEpoch(0);

  static bool _throttle([int ms = 40]) {
    final now = DateTime.now();
    if (now.difference(_lastThrottled).inMilliseconds < ms) return false;
    _lastThrottled = now;
    return true;
  }

  /// แตะทั่วไป: เมนู แท็บ ชิป — เบาที่สุด (กดบ่อยได้)
  static void tap() {
    if (_throttle()) HapticFeedback.selectionClick();
  }

  /// ยืนยันการกด: ปุ่มบันทึก นับเที่ยว — ตอนนิ้วลง
  static void confirm() {
    if (_throttle()) HapticFeedback.lightImpact();
  }

  /// สำเร็จ: เซฟเสร็จ ซิงค์เสร็จ
  static void success() => HapticFeedback.mediumImpact();

  /// เตือน/ทำลาย: ลบ กดค้างครบ เป้าหมายสำเร็จ
  static void warn() => HapticFeedback.heavyImpact();
}
