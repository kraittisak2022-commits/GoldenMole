import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ไอคอน outline บนพื้นขาว: คงโทนเมนูจาก [accent] แต่ผสมกับสีหมึกเข้มตามความสว่างเพื่อคอนทราสต์
Color _readableMenuIconColor(Color accent) {
  const ink = Color(0xFF1C2834);
  final l = accent.computeLuminance();
  final double mix;
  if (l >= 0.72) {
    mix = 0.62;
  } else if (l >= 0.5) {
    mix = 0.48;
  } else if (l >= 0.32) {
    mix = 0.34;
  } else {
    mix = 0.2;
  }
  return Color.lerp(accent, ink, mix)!;
}

/// การ์ดเมนูบันทึกประจำวัน — โทนและโครงสร้างอ้างอิงจาก UI บันทึกประจำวัน (แท็ก, หัวข้อ, ไอคอน, สถานะด้านล่าง)
class RecordModuleCard extends StatefulWidget {
  const RecordModuleCard({
    super.key,
    required this.title,
    required this.icon,
    required this.recordedForSelectedDay,
    required this.onTap,
    this.tileColor = const Color(0xFF4FC3F7),
    this.showLightStyle = false,
  });

  final String title;
  final IconData icon;
  final bool recordedForSelectedDay;
  final VoidCallback onTap;
  final Color tileColor;
  final bool showLightStyle;

  @override
  State<RecordModuleCard> createState() => _RecordModuleCardState();
}

class _RecordModuleCardState extends State<RecordModuleCard> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final titleColor = const Color(0xFF1A2A3C);
    final statusColor = widget.recordedForSelectedDay
        ? const Color(0xFF1B8E4B)
        : const Color(0xFFD64545);
    final accent = widget.tileColor;
    final iconBg = Color.lerp(accent, Colors.white, 0.92)!;
    final iconColor = _readableMenuIconColor(accent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _pressed ? 0.975 : (_hovered ? 1.018 : 1),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            borderRadius: BorderRadius.circular(22),
            child: Ink(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE4ECF4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _hovered ? 0.055 : 0.03),
                    blurRadius: _hovered ? 14 : 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 10,
                    left: 12,
                    child: Container(
                      width: 28,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4DFEA),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -18,
                    right: -14,
                    child: IgnorePointer(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFF6F9FC),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3EBF3),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(22),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    child: Column(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TweenAnimationBuilder<double>(
                                tween:
                                    Tween(begin: 0.98, end: _hovered ? 1.08 : 1),
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                                builder: (context, scale, child) {
                                  return Transform.scale(
                                    scale: scale,
                                    child: child,
                                  );
                                },
                                child: Container(
                                  width: 92,
                                  height: 92,
                                  decoration: BoxDecoration(
                                    color: iconBg,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.28),
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.03),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: AnimatedRotation(
                                    turns: _pressed ? -0.02 : 0,
                                    duration: const Duration(milliseconds: 160),
                                    child: Icon(
                                      widget.icon,
                                      size: 56,
                                      color: iconColor,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                widget.title,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.kanit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: titleColor,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: (widget.recordedForSelectedDay
                                      ? const Color(0xFFE0F3E8)
                                      : const Color(0xFFFFE7E7))
                                  .withValues(alpha: 1),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: widget.recordedForSelectedDay
                                    ? const Color(0xFF9FD8B5)
                                    : const Color(0xFFF2B6B6),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      statusColor.withValues(alpha: 0.24),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 7,
                                  color: statusColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  widget.recordedForSelectedDay
                                      ? 'บันทึกแล้ว'
                                      : 'ยังไม่บันทึก',
                                  style: GoogleFonts.kanit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
