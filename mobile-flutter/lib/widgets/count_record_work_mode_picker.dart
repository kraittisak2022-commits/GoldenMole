import 'package:flutter/material.dart';

import '../theme/daily_palette.dart';
import '../utils/count_record_work_mode.dart';
import '../utils/device_perf.dart';
import 'soft_press_button.dart';

export '../utils/count_record_work_mode.dart' show CountRecordWorkMode;

/// ขั้นเลือกงานก่อนเข้าแผงบันทึกและนับจำนวน — หัวข้อชัด + การ์ดขาว accent bar
class CountRecordWorkModePicker extends StatefulWidget {
  const CountRecordWorkModePicker({super.key, required this.onSelect});

  final ValueChanged<CountRecordWorkMode> onSelect;

  @override
  State<CountRecordWorkModePicker> createState() =>
      _CountRecordWorkModePickerState();
}

class _CountRecordWorkModePickerState extends State<CountRecordWorkModePicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final List<Animation<double>> _staggerAnims;
  late final bool _lite;

  static const _brandTeal = DailyPalette.brand;

  @override
  void initState() {
    super.initState();
    _lite = DevicePerf.isConstrainedDevice;
    _entrance = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _lite ? 300 : 560),
    );
    _staggerAnims = List.generate(4, (index) {
      final start = (0.08 + index * 0.14).clamp(0.0, 0.72);
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
        final scaled = _lite ? child : Transform.scale(
          scale: 0.96 + (0.04 * t),
          child: child,
        );
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
    final titleSize = isTablet ? 34.0 : 28.0;
    final subtitleSize = isTablet ? 17.0 : 15.0;
    final gap = isTablet ? 16.0 : 12.0;

    final trip = _WorkModeOption(
      title: 'ขนอย่างเดียว',
      subtitle: 'บันทึกจำนวนเที่ยวรถ',
      icon: Icons.fire_truck_rounded,
      accent: DailyPalette.countTripIcon,
      iconTileColor: DailyPalette.chipSurface,
      vertical: useColumns,
      onTap: () => widget.onSelect(CountRecordWorkMode.trip),
    );
    final sand = _WorkModeOption(
      title: 'ร่อนทรายอย่างเดียว',
      subtitle: 'บันทึกการร่อนทราย',
      icon: Icons.water_drop_rounded,
      accent: DailyPalette.countSandIcon,
      iconTileColor: DailyPalette.chipSurface,
      vertical: useColumns,
      onTap: () => widget.onSelect(CountRecordWorkMode.sand),
    );
    final both = _WorkModeOption(
      title: 'ขนและร่อนทราย',
      subtitle: 'ทั้ง 2 อย่าง — แสดงสองการ์ด',
      icon: Icons.layers_rounded,
      accent: _brandTeal,
      iconTileColor: DailyPalette.chipSurface,
      vertical: useColumns,
      dualIcons: true,
      onTap: () => widget.onSelect(CountRecordWorkMode.both),
    );

    final header = _staggerTile(
      0,
      Column(
        children: [
          Text(
            'วันนี้ทำงานอะไร?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -0.5,
              color: const Color(0xFF1A2433),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: isTablet ? 56 : 44,
            height: 4,
            decoration: BoxDecoration(
              color: _brandTeal,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'เลือกประเภทงานก่อนเริ่มบันทึก',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: subtitleSize,
              fontWeight: FontWeight.w500,
              height: 1.25,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );

    final options = useColumns
        ? Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _staggerTile(1, trip)),
                SizedBox(width: gap),
                Expanded(child: _staggerTile(2, sand)),
                SizedBox(width: gap),
                Expanded(child: _staggerTile(3, both)),
              ],
            ),
          )
        : Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _staggerTile(1, trip)),
                SizedBox(height: gap),
                Expanded(child: _staggerTile(2, sand)),
                SizedBox(height: gap),
                Expanded(child: _staggerTile(3, both)),
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        SizedBox(height: gap),
        options,
      ],
    );
  }
}

class _WorkModeOption extends StatelessWidget {
  const _WorkModeOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.iconTileColor,
    required this.onTap,
    this.vertical = false,
    this.dualIcons = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Color iconTileColor;
  final VoidCallback onTap;
  final bool vertical;
  final bool dualIcons;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final iconBox = vertical
        ? (isTablet ? 72.0 : 64.0)
        : (isTablet ? 64.0 : 56.0);
    final iconSize = iconBox * 0.52;
    final titleSize = vertical
        ? (isTablet ? 22.0 : 20.0)
        : (isTablet ? 24.0 : 22.0);
    final subtitleSize = vertical
        ? (isTablet ? 14.5 : 13.5)
        : (isTablet ? 15.5 : 14.5);

    Widget iconTile() {
      if (dualIcons) {
        return Container(
          width: vertical ? iconBox + 12 : iconBox + 8,
          height: iconBox,
          decoration: BoxDecoration(
            color: iconTileColor,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.fire_truck_rounded,
                color: DailyPalette.countTripIcon,
                size: iconSize * 0.9,
              ),
              SizedBox(width: isTablet ? 6 : 4),
              Icon(
                Icons.water_drop_rounded,
                color: DailyPalette.countSandIcon,
                size: iconSize * 0.9,
              ),
            ],
          ),
        );
      }
      return Container(
        width: iconBox,
        height: iconBox,
        decoration: BoxDecoration(
          color: iconTileColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, color: accent, size: iconSize),
      );
    }

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
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconTile(),
              SizedBox(height: isTablet ? 16 : 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: textBlock,
              ),
              SizedBox(height: isTablet ? 14 : 10),
              Icon(
                Icons.arrow_forward_rounded,
                color: accent.withValues(alpha: 0.85),
                size: isTablet ? 26 : 22,
              ),
            ],
          )
        : Row(
            children: [
              iconTile(),
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
      child: SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE7ECF3)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: accent),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: vertical
                          ? (isTablet ? 14 : 12)
                          : (isTablet ? 18 : 14),
                      vertical: vertical
                          ? (isTablet ? 18 : 14)
                          : (isTablet ? 16 : 12),
                    ),
                    child: body,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
