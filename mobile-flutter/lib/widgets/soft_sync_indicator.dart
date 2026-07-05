import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Pill «กำลังซิงก์ข้อมูล» ลอยจากขอบบน — ใช้แทนแถบ progress ดิบ
/// วางไว้ในต้นไม้ตลอดเวลา แล้วสลับ [visible] เพื่อให้อนิเมชันเข้า/ออกนุ่ม
class SoftSyncIndicator extends StatelessWidget {
  const SoftSyncIndicator({
    super.key,
    required this.visible,
    this.label = 'กำลังซิงก์ข้อมูล…',
  });

  final bool visible;
  final String label;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -1.2),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          child: Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFE1E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Color(0xFF11A8BA),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.kanit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF3A4A5E),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
