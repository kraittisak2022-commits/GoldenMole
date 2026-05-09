import 'package:supabase_flutter/supabase_flutter.dart';

/// แอปล็อกอินผ่านตาราง [admin_users] โดยไม่ได้ใช้ Supabase Auth — ใช้เมื่อเรียก Edge โดยไม่มี NOTIFY_ADVANCE_INVOKER_SECRET
/// สร้าง session แบบ anonymous (ต้องเปิด provider ใน Dashboard) หรือตั้ง NOTIFY_ADVANCE_INVOKER_SECRET แทน
Future<void> ensureSupabaseSessionForEdgeFunctions(SupabaseClient client) async {
  var session = client.auth.currentSession;
  if (session?.accessToken != null && session!.accessToken.isNotEmpty) {
    return;
  }

  try {
    final res = await client.auth.signInAnonymously();
    session = res.session;
  } on AuthException catch (e) {
    throw StateError(
      'ยังไม่มี session สำหรับเรียกฟังก์ชัน Supabase — ${e.message}\n'
      'แนะนำ: ตั้ง NOTIFY_ADVANCE_INVOKER_SECRET บน Edge + ใน .env แอป (ไม่ต้อง Anonymous) หรือเปิด Anonymous: Authentication → Providers → Anonymous',
    );
  }

  if (session?.accessToken == null || session!.accessToken.isEmpty) {
    throw StateError(
      'ยังไม่มี session สำหรับเรียกฟังก์ชัน Supabase — ตั้ง NOTIFY_ADVANCE_INVOKER_SECRET ใน .env ให้ตรงกับ Edge หรือเปิด Anonymous sign-in ใน Authentication → Providers',
    );
  }
}
