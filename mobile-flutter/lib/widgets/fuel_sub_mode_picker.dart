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
    this.daySummaries = const FuelSubModeDaySummaries(),
  });

  final ValueChanged<FuelSubMode> onSelect;
  final double mainDieselLiters;
  final double reserveDieselLiters;
  /// วันที่ที่จะบันทึก เช่น 16/08/2569
  final String dateLabel;
  /// สรุปเมื่อมีข้อมูลของวันนี้แล้ว — ว่าง = ใช้ subtitle ปกติ
  final FuelSubModeDaySummaries daySummaries;

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
    required bool compact,
  }) {
    final cap = capacity <= 0 ? 1.0 : capacity;
    final ratio = (liters / cap).clamp(0.0, 1.0);
    final low = ratio <= 0.15;
    final barColor = low ? const Color(0xFFD14343) : _brandTeal;
    return Container(
      padding: EdgeInsets.all(compact ? 8 : (isTablet ? 14 : 12)),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FD),
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
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
                size: compact ? 16 : (isTablet ? 22 : 20),
                color: barColor,
              ),
              SizedBox(width: compact ? 4 : 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 12 : (isTablet ? 14.5 : 13),
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 4 : 6),
          Text(
            compact
                ? '${formatFuelLiters(liters)} ล.'
                : '${formatFuelLiters(liters)} / ${formatFuelLiters(cap)} ลิตร',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 13 : (isTablet ? 15 : 13.5),
              fontWeight: FontWeight.w800,
              color: barColor,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: compact ? 6 : (isTablet ? 10 : 8),
              backgroundColor: const Color(0xFFDDE7F3),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tankGauges({required bool isTablet, required bool phonePortrait}) {
    final main = _singleGauge(
      title: 'ถังหลัก',
      liters: widget.mainDieselLiters,
      capacity: kFuelTankCapacityMainLiters,
      isTablet: isTablet,
      compact: phonePortrait,
    );
    final reserve = _singleGauge(
      title: 'ถังสำรอง',
      liters: widget.reserveDieselLiters,
      capacity: kFuelTankCapacityReserveLiters,
      isTablet: isTablet,
      compact: phonePortrait,
    );
    if (phonePortrait) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: main),
          const SizedBox(width: 8),
          Expanded(child: reserve),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        main,
        SizedBox(height: isTablet ? 10 : 8),
        reserve,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.shortestSide >= 600;
    final phonePortrait = !isTablet && size.height >= size.width;
    final gap = phonePortrait ? 8.0 : (isTablet ? 14.0 : 10.0);

    final stockIn = _FuelModeOption(
      title: 'เพิ่มน้ำมัน',
      subtitle: widget.daySummaries.stockIn.isNotEmpty
          ? widget.daySummaries.stockIn
          : (phonePortrait ? 'เติมดีเซลเข้าถังหลัก' : 'เติมดีเซลเข้าถังหลัก'),
      hasExisting: widget.daySummaries.stockIn.isNotEmpty,
      icon: Icons.local_shipping_rounded,
      accent: const Color(0xFF2E7D32),
      iconTileColor: const Color(0xFFE8F5E9),
      compact: phonePortrait,
      listLayout: phonePortrait,
      onTap: () => widget.onSelect(FuelSubMode.stockIn),
    );
    final withdraw = _FuelModeOption(
      title: 'เบิกน้ำมัน',
      subtitle: widget.daySummaries.withdraw.isNotEmpty
          ? widget.daySummaries.withdraw
          : (phonePortrait
              ? 'เครื่องจักร / อื่นๆ'
              : 'เครื่องจักร→สำรอง · อื่นๆ→ถังหลัก'),
      hasExisting: widget.daySummaries.withdraw.isNotEmpty,
      icon: Icons.output_rounded,
      accent: const Color(0xFFEF6C00),
      iconTileColor: const Color(0xFFFFF3E0),
      compact: phonePortrait,
      listLayout: phonePortrait,
      onTap: () => widget.onSelect(FuelSubMode.withdraw),
    );
    final carFill = _FuelModeOption(
      title: phonePortrait ? 'เติมรถยนต์' : 'เติมน้ำมันรถยนต์',
      subtitle: widget.daySummaries.carFill.isNotEmpty
          ? widget.daySummaries.carFill
          : 'หักจากถังหลัก',
      hasExisting: widget.daySummaries.carFill.isNotEmpty,
      icon: Icons.directions_car_filled_rounded,
      accent: const Color(0xFF6A1B9A),
      iconTileColor: const Color(0xFFF3E5F5),
      compact: phonePortrait,
      listLayout: phonePortrait,
      onTap: () => widget.onSelect(FuelSubMode.carFill),
    );
    final macro = _FuelModeOption(
      title: phonePortrait ? 'น้ำมันแม็คโคร' : 'การใช้น้ำมันรถแม็คโคร',
      subtitle: widget.daySummaries.macroUsage.isNotEmpty
          ? widget.daySummaries.macroUsage
          : (phonePortrait ? 'หักจากถังสำรอง' : 'ค่าเริ่มต้นหักจากถังสำรอง'),
      hasExisting: widget.daySummaries.macroUsage.isNotEmpty,
      icon: Icons.local_gas_station_rounded,
      accent: const Color(0xFF1565C0),
      iconTileColor: const Color(0xFFE3F2FD),
      compact: phonePortrait,
      listLayout: phonePortrait,
      onTap: () => widget.onSelect(FuelSubMode.macroUsage),
    );

    final header = _staggerTile(
      0,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            phonePortrait ? 'บันทึกน้ำมันอะไร?' : 'จะบันทึกน้ำมันอะไร?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: phonePortrait ? 20.0 : (isTablet ? 28.0 : 24.0),
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -0.5,
              color: const Color(0xFF1A2433),
            ),
          ),
          SizedBox(height: phonePortrait ? 4 : 6),
          Text(
            'วันที่ ${widget.dateLabel}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: phonePortrait ? 13.0 : (isTablet ? 16.0 : 14.5),
              fontWeight: FontWeight.w700,
              color: const Color(0xFF546E7A),
            ),
          ),
          SizedBox(height: phonePortrait ? 6 : 10),
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
          SizedBox(height: phonePortrait ? 8 : 12),
          _tankGauges(isTablet: isTablet, phonePortrait: phonePortrait),
        ],
      ),
    );

    final options = phonePortrait
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _staggerTile(1, stockIn),
              SizedBox(height: gap),
              _staggerTile(2, withdraw),
              SizedBox(height: gap),
              _staggerTile(3, carFill),
              SizedBox(height: gap),
              _staggerTile(4, macro),
            ],
          )
        : Column(
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
    this.hasExisting = false,
    this.compact = false,
    this.listLayout = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Color iconTileColor;
  final VoidCallback onTap;
  final bool hasExisting;
  final bool compact;
  final bool listLayout;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final iconBox = listLayout
        ? (compact ? 44.0 : 48.0)
        : (isTablet ? 52.0 : 46.0);
    final iconSize = iconBox * 0.52;
    final titleSize = listLayout
        ? (compact ? 16.0 : 17.0)
        : (isTablet ? 16.0 : 15.0);
    final subtitleSize = listLayout
        ? (compact ? 12.0 : 12.5)
        : (isTablet ? 12.5 : 11.5);

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
        SizedBox(height: compact ? 2 : 3),
        Text(
          subtitle,
          maxLines: listLayout ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: subtitleSize,
            fontWeight: FontWeight.w500,
            height: 1.25,
            color: hasExisting ? accent : const Color(0xFF64748B),
          ),
        ),
      ],
    );

    final body = listLayout
        ? Row(
            children: [
              iconTile,
              SizedBox(width: compact ? 12 : 14),
              Expanded(child: textBlock),
              Icon(
                Icons.chevron_right_rounded,
                color: accent.withValues(alpha: 0.9),
                size: compact ? 24 : 28,
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconTile,
              SizedBox(height: isTablet ? 10 : 8),
              textBlock,
            ],
          );

    final minH = listLayout ? (compact ? 72.0 : 80.0) : 0.0;

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
          border: Border.all(
            color: hasExisting
                ? accent.withValues(alpha: 0.45)
                : const Color(0xFFE7ECF3),
            width: hasExisting ? 1.4 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
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
                        horizontal: listLayout
                            ? (compact ? 12 : 14)
                            : (isTablet ? 12 : 10),
                        vertical: listLayout
                            ? (compact ? 10 : 12)
                            : (isTablet ? 12 : 10),
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
