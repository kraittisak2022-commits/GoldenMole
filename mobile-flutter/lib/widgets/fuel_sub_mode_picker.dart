import 'package:flutter/material.dart';

import '../utils/device_perf.dart';
import '../utils/fuel_stock.dart';
import 'soft_press_button.dart';

/// เมนูย่อยของ «น้ำมัน»
enum FuelSubMode {
  /// รถน้ำมันมาเติมเข้าถังหลัก
  stockIn,

  /// เบิกน้ำมันออกจากถังสต็อก (รวมเติมถังสำรองเมื่อเลือกเติมเครื่องจักร)
  withdraw,

  /// เติมน้ำมันรถยนต์ — หักจากถังหลัก
  carFill,

  /// บันทึกการใช้น้ำมันรถแม็คโคร
  macroUsage,
}

/// ขั้นเลือกเมนูย่อยก่อนเข้าฟอร์มน้ำมัน — แสดงระดับน้ำมัน 2 ถังด้านบน
class FuelSubModePicker extends StatefulWidget {
  const FuelSubModePicker({
    super.key,
    required this.onSelect,
    required this.mainDieselLiters,
    required this.reserveDieselLiters,
    required this.dateLabel,
  });

  final ValueChanged<FuelSubMode> onSelect;
  final double mainDieselLiters;
  final double reserveDieselLiters;
  /// วันที่ที่จะบันทึก เช่น 16/08/2569
  final String dateLabel;

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
    _staggerAnims = List.generate(5, (index) {
      final start = (0.06 + index * 0.10).clamp(0.0, 0.72);
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

  Widget _singleGauge({
    required String title,
    required double liters,
    required double capacity,
    required bool isTablet,
  }) {
    final cap = capacity <= 0 ? 1.0 : capacity;
    final ratio = (liters / cap).clamp(0.0, 1.0);
    final low = ratio <= 0.15;
    final barColor = low ? const Color(0xFFD14343) : _brandTeal;
    return Container(
      padding: EdgeInsets.all(isTablet ? 14 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FD),
        borderRadius: BorderRadius.circular(14),
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
                size: isTablet ? 22 : 20,
                color: barColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: isTablet ? 14.5 : 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF334155),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${formatFuelLiters(liters)} / ${formatFuelLiters(cap)} ลิตร',
                    style: TextStyle(
                      fontSize: isTablet ? 15 : 13.5,
                      fontWeight: FontWeight.w800,
                      color: barColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: isTablet ? 10 : 8,
              backgroundColor: const Color(0xFFDDE7F3),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tankGauges(bool isTablet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _singleGauge(
          title: 'ถังหลัก',
          liters: widget.mainDieselLiters,
          capacity: kFuelTankCapacityMainLiters,
          isTablet: isTablet,
        ),
        SizedBox(height: isTablet ? 10 : 8),
        _singleGauge(
          title: 'ถังสำรอง',
          liters: widget.reserveDieselLiters,
          capacity: kFuelTankCapacityReserveLiters,
          isTablet: isTablet,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.shortestSide >= 600;
    final gap = isTablet ? 14.0 : 10.0;

    final stockIn = _FuelModeOption(
      title: 'เพิ่มน้ำมัน',
      subtitle: 'เติมดีเซลเข้าถังหลัก',
      icon: Icons.local_shipping_rounded,
      accent: const Color(0xFF2E7D32),
      iconTileColor: const Color(0xFFE8F5E9),
      onTap: () => widget.onSelect(FuelSubMode.stockIn),
    );
    final withdraw = _FuelModeOption(
      title: 'เบิกน้ำมัน',
      subtitle: 'เครื่องจักร→สำรอง · อื่นๆ→ถังหลัก',
      icon: Icons.output_rounded,
      accent: const Color(0xFFEF6C00),
      iconTileColor: const Color(0xFFFFF3E0),
      onTap: () => widget.onSelect(FuelSubMode.withdraw),
    );
    final carFill = _FuelModeOption(
      title: 'เติมน้ำมันรถยนต์',
      subtitle: 'หักจากถังหลัก',
      icon: Icons.directions_car_filled_rounded,
      accent: const Color(0xFF6A1B9A),
      iconTileColor: const Color(0xFFF3E5F5),
      onTap: () => widget.onSelect(FuelSubMode.carFill),
    );
    final macro = _FuelModeOption(
      title: 'การใช้น้ำมันรถแม็คโคร',
      subtitle: 'ค่าเริ่มต้นหักจากถังสำรอง',
      icon: Icons.local_gas_station_rounded,
      accent: const Color(0xFF1565C0),
      iconTileColor: const Color(0xFFE3F2FD),
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
              fontSize: isTablet ? 28.0 : 24.0,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -0.5,
              color: const Color(0xFF1A2433),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'วันที่ ${widget.dateLabel}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isTablet ? 16.0 : 14.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF546E7A),
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
          _tankGauges(isTablet),
        ],
      ),
    );

    final options = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _staggerTile(1, stockIn)),
            SizedBox(width: gap),
            Expanded(child: _staggerTile(2, withdraw)),
          ],
        ),
        SizedBox(height: gap),
        Row(
          children: [
            Expanded(child: _staggerTile(3, carFill)),
            SizedBox(width: gap),
            Expanded(child: _staggerTile(4, macro)),
          ],
        ),
      ],
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

class _FuelModeOption extends StatelessWidget {
  const _FuelModeOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.iconTileColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Color iconTileColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final iconBox = isTablet ? 52.0 : 46.0;
    final iconSize = iconBox * 0.52;
    final titleSize = isTablet ? 16.0 : 15.0;
    final subtitleSize = isTablet ? 12.5 : 11.5;

    final iconTile = Container(
      width: iconBox,
      height: iconBox,
      decoration: BoxDecoration(
        color: iconTileColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: accent, size: iconSize),
    );

    final textBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
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
        const SizedBox(height: 3),
        Text(
          subtitle,
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

    return SoftPressButton(
      onTap: onTap,
      size: SoftPressSize.large,
      borderRadius: 20,
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
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7ECF3)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: accent),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 12 : 10,
                      vertical: isTablet ? 12 : 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        iconTile,
                        SizedBox(height: isTablet ? 10 : 8),
                        textBlock,
                      ],
                    ),
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
