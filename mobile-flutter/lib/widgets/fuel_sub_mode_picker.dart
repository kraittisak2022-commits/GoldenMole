import 'package:flutter/material.dart';

import '../utils/device_perf.dart';
import '../utils/fuel_stock.dart';
import 'soft_press_button.dart';

/// เมนูย่อยของ «น้ำมัน»
enum FuelSubMode {
  /// รถน้ำมันมาเติมเข้าถังสต็อก
  stockIn,

  /// เบิกน้ำมันออกจากถังสต็อก
  withdraw,

  /// บันทึกการใช้น้ำมันรถแม็คโคร (เหมือนเดิม)
  macroUsage,
}

/// ขั้นเลือกเมนูย่อยก่อนเข้าฟอร์มน้ำมัน — แสดงระดับน้ำมันในถังด้านบน
class FuelSubModePicker extends StatefulWidget {
  const FuelSubModePicker({
    super.key,
    required this.onSelect,
    required this.dieselLiters,
    this.capacityLiters = kFuelTankCapacityLiters,
  });

  final ValueChanged<FuelSubMode> onSelect;
  final double dieselLiters;
  final double capacityLiters;

  @override
  State<FuelSubModePicker> createState() => _FuelSubModePickerState();
}

class _FuelSubModePickerState extends State<FuelSubModePicker>
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

  Widget _tankGauge(bool isTablet) {
    final capacity = widget.capacityLiters <= 0 ? 1.0 : widget.capacityLiters;
    final ratio = (widget.dieselLiters / capacity).clamp(0.0, 1.0);
    final low = ratio <= 0.15;
    final barColor = low ? const Color(0xFFD14343) : _brandTeal;
    return Container(
      padding: EdgeInsets.all(isTablet ? 16 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: low ? const Color(0xFFF5C2C2) : const Color(0xFFBFD8F4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.propane_tank_outlined,
                size: isTablet ? 26 : 22,
                color: barColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'น้ำมันคงเหลือในถัง',
                  style: TextStyle(
                    fontSize: isTablet ? 16 : 14.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF334155),
                  ),
                ),
              ),
              Text(
                '${formatFuelLiters(widget.dieselLiters)} / '
                '${formatFuelLiters(capacity)} ลิตร',
                style: TextStyle(
                  fontSize: isTablet ? 18 : 16,
                  fontWeight: FontWeight.w800,
                  color: barColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: isTablet ? 12 : 10,
              backgroundColor: const Color(0xFFDDE7F3),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.shortestSide >= 600;
    final isLandscape = size.width > size.height;
    final useColumns = isTablet && isLandscape;
    final gap = isTablet ? 16.0 : 12.0;

    final stockIn = _FuelModeOption(
      title: 'เพิ่มน้ำมัน',
      subtitle: 'รถน้ำมันมาเติมเข้าถังสต็อก',
      icon: Icons.local_shipping_rounded,
      accent: const Color(0xFF2E7D32),
      iconTileColor: const Color(0xFFE8F5E9),
      vertical: useColumns,
      onTap: () => widget.onSelect(FuelSubMode.stockIn),
    );
    final withdraw = _FuelModeOption(
      title: 'เบิกน้ำมัน',
      subtitle: 'เอาน้ำมันออกจากถังสต็อก',
      icon: Icons.output_rounded,
      accent: const Color(0xFFEF6C00),
      iconTileColor: const Color(0xFFFFF3E0),
      vertical: useColumns,
      onTap: () => widget.onSelect(FuelSubMode.withdraw),
    );
    final macro = _FuelModeOption(
      title: 'การใช้น้ำมันรถแม็คโคร',
      subtitle: 'บันทึกรายคันที่เติมวันนี้',
      icon: Icons.local_gas_station_rounded,
      accent: const Color(0xFF1565C0),
      iconTileColor: const Color(0xFFE3F2FD),
      vertical: useColumns,
      onTap: () => widget.onSelect(FuelSubMode.macroUsage),
    );

    final header = _staggerTile(
      0,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'จะบันทึกน้ำมันอะไร?',
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
          const SizedBox(height: 12),
          _tankGauge(isTablet),
        ],
      ),
    );

    final options = useColumns
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _staggerTile(1, stockIn)),
              SizedBox(width: gap),
              Expanded(child: _staggerTile(2, withdraw)),
              SizedBox(width: gap),
              Expanded(child: _staggerTile(3, macro)),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _staggerTile(1, stockIn),
              SizedBox(height: gap),
              _staggerTile(2, withdraw),
              SizedBox(height: gap),
              _staggerTile(3, macro),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        SizedBox(height: gap),
        useColumns ? SizedBox(height: 200, child: options) : options,
      ],
    );
  }
}

class _FuelModeOption extends StatelessWidget {
  const _FuelModeOption({
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
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconTile,
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
                        : (isTablet ? 16 : 13),
                  ),
                  child: body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
