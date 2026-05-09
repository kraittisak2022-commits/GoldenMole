import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/thai_phone.dart';

/// ทดสอบ SMS ผ่าน Edge `send-sms-test` (ไม่ต้องล็อกอิน — ใช้ anon key ของโปรเจกต์)
/// แนะนำตั้ง Edge secret `SMS_TEST_INVOKE_SECRET` และในแอป `SMS_TEST_INVOKE_KEY` ให้ตรงกัน
class SmsTestScreen extends StatefulWidget {
  const SmsTestScreen({super.key});

  @override
  State<SmsTestScreen> createState() => _SmsTestScreenState();
}

class _SmsTestScreenState extends State<SmsTestScreen> {
  late final TextEditingController _phoneController;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: _prefillPhone());
  }

  String _prefillPhone() {
    final extra = dotenv.env['SMS_ADVANCE_NOTIFY_EXTRA'] ?? '';
    for (final part in extra.split(',')) {
      final t = part.trim();
      if (t.isNotEmpty) return t;
    }
    final test = dotenv.env['SMS_TEST_DEST'] ?? '';
    if (test.trim().isNotEmpty) {
      final first = test.split(',').map((e) => e.trim()).firstWhere(
            (e) => e.isNotEmpty,
            orElse: () => '',
          );
      if (first.isNotEmpty) return first;
    }
    return '';
  }

  Map<String, String> _invokeHeaders() {
    final key = (dotenv.env['SMS_TEST_INVOKE_KEY'] ?? '').trim();
    if (key.isEmpty) return {};
    return {'x-goldenmole-sms-test-secret': key};
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendTest() async {
    final normalized = normalizeThaiPhone(_phoneController.text.trim());
    if (normalized == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'เบอร์ไม่ถูกต้อง (ใส่ 0xxxxxxxxx หรือ +66…)',
            style: GoogleFonts.kanit(),
          ),
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'send-sms-test',
        headers: _invokeHeaders(),
        body: {
          'text':
              'GoldenMole ทดสอบ SMS ${DateTime.now().toIso8601String().substring(0, 19)}',
          'destinations': [normalized],
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF168A45),
          content: Text(
            'ส่งแล้ว (HTTP ${res.status})',
            style: GoogleFonts.kanit(color: Colors.white),
          ),
        ),
      );
    } on FunctionException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB71C1C),
          content: Text(
            'ล้มเหลว ${e.status}: ${e.details}',
            style: GoogleFonts.kanit(color: Colors.white),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB71C1C),
          content: Text(
            'ผิดพลาด: $e',
            style: GoogleFonts.kanit(color: Colors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasInvokeKey = (dotenv.env['SMS_TEST_INVOKE_KEY'] ?? '').trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF3FBFC),
      appBar: AppBar(
        title: Text('ทดสอบส่ง SMS', style: GoogleFonts.kanit(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF00838F),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'เรียกฟังก์ชัน send-sms-test บน Supabase (ไม่ต้องล็อกอิน — สูงสุด 5 เบอร์ต่อครั้ง)',
            style: GoogleFonts.kanit(
              fontSize: 14,
              color: const Color(0xFF314C6D),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasInvokeKey
                ? 'ส่งหัวข้อ x-goldenmole-sms-test-secret จาก SMS_TEST_INVOKE_KEY ใน .env'
                : 'แนะนำ: ตั้ง SMS_TEST_INVOKE_KEY ใน .env และ SMS_TEST_INVOKE_SECRET บน Edge ให้ตรงกัน (กันยิงปลอม)',
            style: GoogleFonts.kanit(
              fontSize: 12,
              color: const Color(0xFF5B6D83),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'เบอร์ปลายทาง',
              hintText: '0812345678',
              border: const OutlineInputBorder(),
              labelStyle: GoogleFonts.kanit(),
              hintStyle: GoogleFonts.kanit(),
            ),
            style: GoogleFonts.kanit(fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'ค่าเริ่มต้นดึงจาก SMS_ADVANCE_NOTIFY_EXTRA / SMS_TEST_DEST ใน .env ถ้ามี',
            style: GoogleFonts.kanit(fontSize: 12, color: const Color(0xFF5B6D83)),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _sending ? null : _sendTest,
            icon: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sms_outlined),
            label: Text(
              _sending ? 'กำลังส่ง…' : 'ส่งข้อความทดสอบ',
              style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00838F),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            ),
          ),
        ],
      ),
    );
  }
}
