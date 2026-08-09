import 'package:flutter/material.dart';

import '../utils/device_perf.dart';
import 'soft_press_button.dart';

/// เมนูย่อยของ «เช็คชื่อ»
enum AttendanceSection {
  /// พนักงานท่าทราย — ทำงาน / ลางาน (จับเวลาอัตโนมัติ)
  sandYard,

  /// คนขับรถ — แม็คโคร / ดรัม / ลางาน
  driver,
}

/// ขั้นเลือกเมนูย่อยก่อนเข้ากระดานเช็คชื่อเต็มจอ
class AttendanceSubModePicker extends StatefulWidget {
  const AttendanceSubModePicker({
    super.key,
    required this.onSelect,
    required this.sandYardSummary,
    required this.driverSummary,
  });

  final ValueChanged<AttendanceSection> onSelect;
  final String sandYardSummary;
  final String driverSummary;

  @override
  State<AttendanceSubModePicker> createState() =>
      _AttendanceSubModePickerState();
}

class _AttendanceSubModePickerState extends State<AttendanceSubModePicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final List<Animation<double>> _staggerAnims;
  late final bool _lite;

  static const _brandTeal = Color(0xFF0D98A5);

  @override
  void initState() {
    super.initState();
    _lite = DevicePerf.isConstrainedDevice;
    _entrance = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _lite ? 300 : 560),
    );
    _staggerAnims = List.generate(3, (index) {
      final start = (0.08 + index * 0.16).clamp(0.0, 0.72);
      final end = (start + (_lite ? 0.22 : 0.32)).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _entrance,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );
    });
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Widget _staggerTile(int index, Widget child) {
    return AnimatedBuilder(
      animation: _staggerAnims[index],
      builder: (context, _) {
        final t = _staggerAnims[index].value;
        final scaled = _lite
            ? child
            : Transform.scale(scale: 0.96 + (0.04 * t), child: child);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 16),
            child: scaled,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.shortestSide >= 600;
    final isLandscape = size.width > size.height;
    final useColumns = isTablet && isLandscape;
    final gap = isTablet ? 16.0 : 12.0;

    final sand = _AttendanceModeOption(
      title: 'เช็คชื่อพนักงานท่าทราย',
      subtitle: widget.sandYardSummary,
      icon: Icons.groups_rounded,
      accent: const Color(0xFF2FB6A6),
      iconTileColor: const Color(0xFFE0F7F4),
      vertical: useColumns,
      onTap: () => widget.onSelect(AttendanceSection.sandYard),
    );
    final driver = _AttendanceModeOption(
      title: 'เช็คชื่อคนขับรถ',
      subtitle: widget.driverSummary,
      icon: Icons.local_shipping_rounded,
      accent: const Color(0xFF00897B),
      iconTileColor: const Color(0xFFE0F2F1),
      vertical: useColumns,
      onTap: () => widget.onSelect(AttendanceSection.driver),
    );

    final header = _staggerTile(
      0,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'จะเช็คชื่อกลุ่มไหน?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isTablet ? 30.0 : 25.0,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -0.5,
              color: const Color(0xFF1A2433),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: isTablet ? 56 : 44,
              height: 4,
              decoration: BoxDecoration(
                color: _brandTeal,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'แยกกระดานเต็มจอ — ลากวางรายชื่อเหมือนเกม',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isTablet ? 15.0 : 13.5,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
              height: 1.35,
            ),
          ),
        ],
      ),
    );

    final options = useColumns
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _staggerTile(1, sand)),
              SizedBox(width: gap),
              Expanded(child: _staggerTile(2, driver)),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _staggerTile(1, sand),
              SizedBox(height: gap),
              _staggerTile(2, driver),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        SizedBox(height: gap),
        // แนวตั้ง (แท็บเล็ตแนวนอน): FittedBox ในแต่ละการ์ดกัน overflow
        useColumns
            ? SizedBox(height: isTablet ? 240 : 220, child: options)
            : options,
      ],
    );
  }
}

class _AttendanceModeOption extends StatelessWidget {
  const _AttendanceModeOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.iconTileColor,
    required this.onTap,
    this.vertical = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Color iconTileColor;
  final VoidCallback onTap;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final iconBox = vertical
        ? (isTablet ? 72.0 : 64.0)
        : (isTablet ? 64.0 : 56.0);
    final iconSize = iconBox * 0.52;
    final titleSize = vertical
        ? (isTablet ? 21.0 : 19.0)
        : (isTablet ? 23.0 : 21.0);
    final subtitleSize = vertical
        ? (isTablet ? 14.5 : 13.5)
        : (isTablet ? 15.0 : 14.0);

    final iconTile = Container(
      width: iconBox,
      height: iconBox,
      decoration: BoxDecoration(
        color: iconTileColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: accent, size: iconSize),
    );

    final textBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          vertical ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          textAlign: vertical ? TextAlign.center : TextAlign.start,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            height: 1.12,
            letterSpacing: -0.25,
            color: const Color(0xFF1A2433),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: vertical ? TextAlign.center : TextAlign.start,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: subtitleSize,
            fontWeight: FontWeight.w500,
            height: 1.25,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );

    final body = vertical
        ? FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  iconTile,
                  SizedBox(height: isTablet ? 12 : 8),
                  textBlock,
                  SizedBox(height: isTablet ? 10 : 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: accent.withValues(alpha: 0.85),
                    size: isTablet ? 26 : 22,
                  ),
                ],
              ),
            ),
          )
        : Row(
            children: [
              iconTile,
              SizedBox(width: isTablet ? 18 : 14),
              Expanded(child: textBlock),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: accent.withValues(alpha: 0.9),
                size: isTablet ? 32 : 28,
              ),
            ],
          );

    // มือถือแนวตั้งอยู่ใน Column ไม่มี max height — ห้ามใช้
    // CrossAxisAlignment.stretch โดยตรง (การ์ดสูงเป็นศูนย์ / แตะไม่ได้)
    // IntrinsicHeight ให้แถบสีซ้ายสูงเต็มการ์ดโดยไม่พัง layout
    final minH = vertical ? 0.0 : (isTablet ? 88.0 : 80.0);
    return SoftPressButton(
      onTap: onTap,
      size: SoftPressSize.large,
      borderRadius: 22,
      isDarkSurface: false,
      liftWhenIdle: true,
      depthShadow: SoftPressDepthShadow(
        color: accent.withValues(alpha: 0.12),
        blurRadius: 14,
        offsetY: 4,
        pressedBlurRadius: 5,
        pressedOffsetY: 1,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE7ECF3)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minH),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: accent),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: vertical
                            ? (isTablet ? 12 : 10)
                            : (isTablet ? 18 : 14),
                        vertical: vertical
                            ? (isTablet ? 14 : 10)
                            : (isTablet ? 16 : 13),
                      ),
                      child: body,
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
