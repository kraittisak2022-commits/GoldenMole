import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// เสียงสั้นตอนกดปุ่มบันทึก — ใช้เสียงระบบ (ทำงานออฟไลน์ได้)
class RecordFeedbackSound {
  RecordFeedbackSound._();

  static Future<void> playRecordTap() async {
    if (kIsWeb) return;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        break;
      default:
        return;
    }
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }
}
