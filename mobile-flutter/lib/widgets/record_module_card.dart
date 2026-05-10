import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/daily_module_transactions.dart';

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
    required this.fillStatus,
    required this.onTap,
    this.tileColor = const Color(0xFF4FC3F7),
    this.showLightStyle = false,
  });

  final String title;
  final IconData icon;
  final DailyModuleFillStatus fillStatus;
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
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final titleColor = const Color(0xFF1A2A3C);
    final status = widget.fillStatus;
    final recorded = status == DailyModuleFillStatus.complete;
    final partial = status == DailyModuleFillStatus.incomplete;

    final statusLabel = recorded
        ? 'บันทึกครบแล้ว'
        : partial
        ? 'กรอกข้อมูลไม่ครบ'
        : 'แตะเพื่อบันทึก';

    final statusColor = recorded
        ? const Color(0xFF168A45)
        : partial
        ? const Color(0xFFD97706)
        : const Color(0xFFC73E3E);

    Color badgeBg() {
      if (recorded) return const Color(0xFF18A352);
      if (partial) return const Color(0xFFF59E0B);
      return const Color(0xFFB0BACA);
    }

    IconData badgeIcon() {
      if (recorded) return Icons.check_rounded;
      if (partial) return Icons.more_horiz_rounded;
      return Icons.remove_rounded;
    }

    final accent = widget.tileColor;
    final isSandWashTitle = widget.title.contains('บันทึกการร่อนทราย');
    final cardTint = Colors.white;
    final borderColor = const Color(0xFFE4EAF2);
    final iconBg = const Color(0xFFF5F8FC);
    final iconColor = _readableMenuIconColor(accent);

    final iconSquare = Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: iconBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFFE0E7F0),
          width: 1,
        ),
        boxShadow: isAndroid
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF1A2836).withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Icon(
        widget.icon,
        size: 58,
        color: iconColor,
      ),
    );

    final mainPlate = isAndroid
        ? Container(
            decoration: BoxDecoration(
              color: cardTint,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A2836).withValues(alpha: 0.07),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: accent.withValues(alpha: 0.06),
                  blurRadius: 12,
                  spreadRadius: -2,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              children: [
                Center(child: iconSquare),
              ],
            ),
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: cardTint,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A2836).withValues(
                    alpha: _hovered ? 0.07 : 0.045,
                  ),
                  blurRadius: _hovered ? 6 : 4,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: const Color(0xFF1A2836).withValues(
                    alpha: _hovered ? 0.14 : 0.09,
                  ),
                  blurRadius: _hovered ? 26 : 18,
                  spreadRadius: -3,
                  offset: Offset(0, _hovered ? 10 : 7),
                ),
                BoxShadow(
                  color: accent.withValues(
                    alpha: _hovered ? 0.14 : 0.08,
                  ),
                  blurRadius: _hovered ? 28 : 20,
                  spreadRadius: -6,
                  offset: Offset(0, _hovered ? 12 : 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                Center(
                  child: AnimatedRotation(
                    turns: _pressed ? -0.014 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: iconSquare,
                  ),
                ),
              ],
            ),
          );

    final badge = isAndroid
        ? Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: badgeBg(),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(
              badgeIcon(),
              size: 16,
              color: Colors.white,
            ),
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: badgeBg(),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(
              badgeIcon(),
              size: 16,
              color: Colors.white,
            ),
          );

    final paddedColumn = Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                mainPlate,
                Positioned(
                  top: 8,
                  right: 8,
                  child: badge,
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
              fontSize: isSandWashTitle ? 20 : 18,
              fontWeight: FontWeight.w800,
              color: titleColor,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            statusLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: 11.8,
              fontWeight: FontWeight.w600,
              color: recorded
                  ? statusColor
                  : partial
                  ? statusColor
                  : const Color(0xFF77859A),
            ),
          ),
        ],
      ),
    );

    final ink = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        borderRadius: BorderRadius.circular(24),
        child: paddedColumn,
      ),
    );

    final scaled = AnimatedScale(
      scale: _pressed
          ? 0.96
          : (isAndroid ? 1.0 : (_hovered ? 1.02 : 1)),
      duration: Duration(milliseconds: isAndroid ? 100 : 150),
      curve: Curves.easeOutCubic,
      child: ink,
    );

    if (isAndroid) {
      return scaled;
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: scaled,
    );
  }
}
