import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);
    final titleColor = const Color(0xFF1A2A3C);
    final recorded = widget.recordedForSelectedDay;
    final statusColor =
        recorded ? const Color(0xFF168A45) : const Color(0xFFC73E3E);
    final accent = widget.tileColor;
    final isSandWashTitle = widget.title.contains('บันทึกการร่อนทราย');
    final cardTint = Color.lerp(Colors.white, accent, 0.44)!;
    final borderColor = Color.lerp(const Color(0xFFDCE6F0), accent, 0.7)!;
    final iconBg = Color.lerp(accent, Colors.white, 0.92)!;
    final iconColor = _readableMenuIconColor(accent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : (_hovered ? 1.02 : 1),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color.lerp(cardTint, Colors.white, 0.18)!,
                                cardTint,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(color: borderColor, width: 1.4),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: _hovered ? 0.28 : 0.2),
                                blurRadius: _hovered ? 20 : 14,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                top: -24,
                                right: -20,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 96,
                                    height: 96,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: accent.withValues(alpha: 0.22),
                                    ),
                                  ),
                                ),
                              ),
                              Center(
                                child: AnimatedRotation(
                                  turns: _pressed ? -0.014 : 0,
                                  duration: const Duration(milliseconds: 150),
                                  child: Container(
                                    width: 94,
                                    height: 94,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          iconBg,
                                          Color.lerp(iconBg, Colors.white, 0.28)!,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(28),
                                      border: Border.all(
                                        color: accent.withValues(alpha: 0.32),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Icon(
                                      widget.icon,
                                      size: 52,
                                      color: iconColor,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: -8,
                          right: -6,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: recorded ? const Color(0xFF18A352) : const Color(0xFFFFB020),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.4),
                              boxShadow: [
                                BoxShadow(
                                  color: (recorded
                                          ? const Color(0xFF18A352)
                                          : const Color(0xFFFFB020))
                                      .withValues(alpha: 0.38),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Icon(
                              recorded ? Icons.check_rounded : Icons.more_horiz_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: isSandWashTitle ? 21 : 19,
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    recorded ? 'บันทึกแล้ว' : 'แตะเพื่อบันทึก',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
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
