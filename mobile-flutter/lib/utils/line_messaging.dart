import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_function_session.dart';

/// ข้อความสำหรับแสดงใน UI เมื่อเรียก Edge notify-advance-line แล้ว error (รวม Auth session missing)
String lineNotifyAdvanceInvokeErrorMessage(Object error) {
  if (error is AuthSessionMissingException) {
    return 'ไม่มี session การล็อกอิน Supabase — ออกจากระบบแล้วล็อกอินใหม่ แล้วลองอีกครั้ง';
  }
  if (error is AuthException) {
    return 'การยืนยันตัวตนล้มเหลว: ${error.message}';
  }
  if (error is StateError) {
    return error.message;
  }
  return error.toString();
}

String? normalizeLineUserId(String raw) {
  final s = raw.trim();
  final re = RegExp(r'^U([a-fA-F0-9]{32})$');
  final m = re.firstMatch(s);
  if (m == null) return null;
  return 'U${m.group(1)!.toLowerCase()}';
}

List<String> parseLineUserIdsField(String raw) {
  final out = <String>{};
  for (final part in raw.split(RegExp(r'[\s,]+'))) {
    final u = normalizeLineUserId(part);
    if (u != null) out.add(u);
  }
  return out.toList();
}

/// เรียก Edge notify-advance-line
/// - ถ้ามี `NOTIFY_ADVANCE_INVOKER_SECRET` ใน .env (ตรงกับ Edge secret เดียวกัน) ไม่ต้องเปิด Anonymous
/// - ไม่มี secret ใช้ JWT จาก session (ต้องเปิด Anonymous หรือ Supabase Auth)
Future<FunctionResponse> invokeNotifyAdvanceLine({
  required String text,
  required List<String> to,
}) async {
  final client = Supabase.instance.client;
  final invokeSecret = (dotenv.env['NOTIFY_ADVANCE_INVOKER_SECRET'] ?? '').trim();

  Future<FunctionResponse> run(Map<String, String> headers) =>
      client.functions.invoke(
        'notify-advance-line',
        body: <String, dynamic>{'text': text, 'to': to},
        headers: headers,
      );

  if (invokeSecret.isNotEmpty) {
    final anon = (dotenv.env['SUPABASE_ANON_KEY'] ?? '').trim();
    if (anon.isEmpty) {
      throw StateError(
        'มี NOTIFY_ADVANCE_INVOKER_SECRET แต่ไม่มี SUPABASE_ANON_KEY ใน .env — ใส่ anon key ให้ครบ',
      );
    }
    final headers = <String, String>{
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
      'x-cm-notify-advance-secret': invokeSecret,
    };
    return run(headers);
  }

  await ensureSupabaseSessionForEdgeFunctions(client);

  final session = client.auth.currentSession;
  final token = session?.accessToken;
  if (token == null || token.isEmpty) {
    throw StateError(
      'ยังไม่มี JWT — ตั้ง NOTIFY_ADVANCE_INVOKER_SECRET ใน .env ให้ตรงกับ Edge (แนะนำ) หรือเปิด Anonymous sign-in ใน Supabase',
    );
  }

  final headers = <String, String>{
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  var res = await run(headers);
  if (res.status == 401) {
    try {
      await client.auth.refreshSession();
    } on AuthSessionMissingException catch (e) {
      throw StateError(lineNotifyAdvanceInvokeErrorMessage(e));
    }
    final t2 = client.auth.currentSession?.accessToken;
    if (t2 != null && t2.isNotEmpty) {
      res = await run(<String, String>{
        'Authorization': 'Bearer $t2',
        'Content-Type': 'application/json',
      });
    }
  }
  return res;
}
