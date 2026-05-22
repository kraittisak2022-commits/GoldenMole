/// ป้องกันส่งรายงานซ้ำหรือถี่เกินไป (ส่งรั่ว)
class MobileErrorReportRateLimitException implements Exception {
  MobileErrorReportRateLimitException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MobileErrorReportSubmitGuard {
  MobileErrorReportSubmitGuard._();

  static const Duration minIntervalAny = Duration(seconds: 45);
  static const Duration duplicateWindow = Duration(minutes: 5);

  static DateTime? _lastSubmitAt;
  static String? _lastFingerprint;
  static DateTime? _lastDuplicateAt;

  /// คีย์สำหรับตรวจรายงานซ้ำ (source + สรุป)
  static String fingerprint({
    required String source,
    required String summary,
  }) {
    final s = '${source.trim()}|${summary.trim().toLowerCase()}';
    if (s.length <= 200) return s;
    return s.substring(0, 200);
  }

  /// คืน null ถ้าส่งได้ — มิฉะนั้นข้อความที่แสดงผู้ใช้
  static String? blockReason({required String fingerprint}) {
    final now = DateTime.now();
    if (_lastFingerprint == fingerprint &&
        _lastDuplicateAt != null &&
        now.difference(_lastDuplicateAt!) < duplicateWindow) {
      return 'ส่งรายงานนี้ไปแล้วเมื่อสักครู่ — ไม่ต้องส่งซ้ำ';
    }
    if (_lastSubmitAt != null) {
      final elapsed = now.difference(_lastSubmitAt!);
      if (elapsed < minIntervalAny) {
        final sec = (minIntervalAny - elapsed).inSeconds;
        return 'กรุณารอ ${sec > 0 ? sec : 1} วินาทีก่อนส่งรายงานอีกครั้ง';
      }
    }
    return null;
  }

  static void recordSuccess(String fingerprint) {
    final now = DateTime.now();
    _lastSubmitAt = now;
    _lastFingerprint = fingerprint;
    _lastDuplicateAt = now;
  }

  /// สำหรับเทสต์เท่านั้น
  static void resetForTest() {
    _lastSubmitAt = null;
    _lastFingerprint = null;
    _lastDuplicateAt = null;
  }
}
