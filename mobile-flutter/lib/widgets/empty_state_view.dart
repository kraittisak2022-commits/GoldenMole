import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Empty state มาตรฐาน — ไอคอนในวงกลมนุ่มๆ + หัวข้อ + คำอธิบาย + ปุ่ม (ถ้ามี)
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.accentColor = const Color(0xFF11A8BA),
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color accentColor;

  /// true = ย่อขนาดสำหรับพื้นที่จำกัด (เช่นใน bottom sheet)
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final circle = compact ? 68.0 : 96.0;
    final iconSize = compact ? 32.0 : 44.0;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 32,
          vertical: compact ? 16 : 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.86, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                width: circle,
                height: circle,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentColor.withValues(alpha: 0.14),
                      accentColor.withValues(alpha: 0.05),
                    ],
                  ),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.18),
                  ),
                ),
                child: Icon(
                  icon,
                  size: iconSize,
                  color: accentColor.withValues(alpha: 0.75),
                ),
              ),
            ),
            SizedBox(height: compact ? 12 : 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(
                fontSize: compact ? 15 : 16.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF2A3D4D),
              ),
            ),
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(
                  fontSize: 13,
                  height: 1.4,
                  color: const Color(0xFF7A8FA0),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: compact ? 14 : 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(backgroundColor: accentColor),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
