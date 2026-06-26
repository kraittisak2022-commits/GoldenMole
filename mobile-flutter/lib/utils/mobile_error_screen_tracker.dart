/// จำหน้าจอและขั้นตอนล่าสุด — ใช้ตอนส่งรายงาน error
class MobileErrorScreenTracker {
  MobileErrorScreenTracker._();

  /// ชื่อหน้า (ภาษาไทย สำหรับแสดงผู้ใช้)
  static String? page;

  /// รหัสหน้า (เช่น page.dashboard)
  static String? pageId;

  /// รายการ/โมดูลย่อย
  static String? module;

  /// รหัสขั้นตอน (เช่น step.dashboard.count_record.trip)
  static String? stepId;

  static void set({
    required String page,
    required String pageId,
    String? module,
    String? stepId,
  }) {
    final p = page.trim();
    MobileErrorScreenTracker.page = p.isEmpty ? null : p;
    final pid = pageId.trim();
    MobileErrorScreenTracker.pageId = pid.isEmpty ? null : pid;
    final m = module?.trim();
    MobileErrorScreenTracker.module = (m == null || m.isEmpty) ? null : m;
    final s = stepId?.trim();
    MobileErrorScreenTracker.stepId = (s == null || s.isEmpty) ? null : s;
  }

  /// อัปเดตเฉพาะขั้นตอน (คง page/pageId เดิม)
  static void setStep({
    required String stepId,
    String? module,
  }) {
    final s = stepId.trim();
    MobileErrorScreenTracker.stepId = s.isEmpty ? null : s;
    if (module != null) {
      final m = module.trim();
      MobileErrorScreenTracker.module = m.isEmpty ? null : m;
    }
  }

  static void clear() {
    page = null;
    pageId = null;
    module = null;
    stepId = null;
  }
}
