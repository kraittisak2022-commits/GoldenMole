/// จำหน้าจอล่าสุดของแอป — ใช้ตอนส่งรายงาน error ที่ไม่มี SaveErrorContext
class MobileErrorScreenTracker {
  MobileErrorScreenTracker._();

  static String? page;
  static String? module;

  static void set({required String page, String? module}) {
    final p = page.trim();
    MobileErrorScreenTracker.page = p.isEmpty ? null : p;
    final m = module?.trim();
    MobileErrorScreenTracker.module = (m == null || m.isEmpty) ? null : m;
  }

  static void clear() {
    page = null;
    module = null;
  }
}
