import 'package:flutter/material.dart';

import '../theme/daily_palette.dart';
import '../utils/device_perf.dart';
import '../utils/fuel_stock.dart';
import 'app_theme_scope.dart';
import 'soft_press_button.dart';

/// ขั้นเลือกถังน้ำมัน (ถังหลัก / ถังสำรอง) ก่อนเข้าหน้ากรอกน้ำมันรถแม็คโคร
class FuelMacroTankPicker extends StatefulWidget {
  const FuelMacroTankPicker({
    super.key,
    required this.onSelect,
    required this.mainDieselLiters,
    required this.reserveDieselLiters,
    required this.dateLabel,
    this.mainSummary = const FuelMacroTankDaySummary(),
    this.reserveSummary = const FuelMacroTankDaySummary(),
    this.missingCount = 0,
  });

  final ValueChanged<String> onSelect;
  final double mainDieselLiters;
  final double reserveDieselLiters;
  final String dateLabel;
  final FuelMacroTankDaySummary mainSummary;
  final FuelMacroTankDaySummary reserveSummary;
  final int missingCount;

  @override
  State<FuelMacroTankPicker> createState() => _FuelMacroTankPickerState();
}

class _FuelMacroTankPickerState extends State<FuelMacroTankPicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final List<Animation<double>> _staggerAnims;
  late final bool _lite;

  @override
  void initState() {
    super.initState();
    _lite = DevicePerf.isConstrainedDevice;
    _entrance = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _lite ? 260 : 480),
    );
    _staggerAnims = List.generate(3, (index) {
      final start = (0.06 + index * 0.16).clamp(0.0, 0.72);
      final end = (start + (_lite ? 0.24 : 0.34)).clamp(0.0, 1.0);
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

  Widget _stagger(int index, Widget child) {
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
            offset: Offset(0, (1 - t) * 14),
            child: scaled,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.shortestSide >= 600;
    final isLandscape = size.width > size.height;
    final phonePortrait = !isTablet && !isLandscape;
    final useColumns = isTablet && isLandscape;
    final gap = phonePortrait ? 12.0 : (isTablet ? 16.0 : 12.0);

    final mainAccent = isDark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF1565C0);
    final mainIconBg = isDark
        ? const Color(0xFF172B44)
        : const Color(0xFFE3F2FD);
    final reserveAccent = isDark ? p.brand : const Color(0xFF0D98A5);
    final reserveIconBg = isDark
        ? const Color(0xFF12323A)
        : const Color(0xFFE0F7FA);

    final header = _stagger(
      0,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: phonePortrait ? 10 : 12,
                vertical: phonePortrait ? 4 : 5,
              ),
              decoration: BoxDecoration(
                color: mainIconBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: mainAccent.withValues(alpha: isDark ? 0.4 : 0.28),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_gas_station_rounded,
                    size: phonePortrait ? 14 : 16,
                    color: mainAccent,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'น้ำมันรถแม็คโคร · ขั้นตอน 1/2',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: phonePortrait ? 12 : 13,
                        fontWeight: FontWeight.w700,
                        color: mainAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: phonePortrait ? 8 : 12),
          Text(
            'เติมน้ำมันจากถังไหน?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: phonePortrait ? 22.0 : (isTablet ? 28.0 : 24.0),
              fontWeight: FontWeight.w800,
              height: 1.12,
              letterSpacing: -0.4,
              color: p.ink,
            ),
          ),
          SizedBox(height: phonePortrait ? 4 : 6),
          Text(
            'วันที่ ${widget.dateLabel} · เลือกถังก่อนกรอกปริมาณน้ำมัน',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: phonePortrait ? 13.0 : (isTablet ? 15.5 : 14.0),
              fontWeight: FontWeight.w500,
              color: p.inkMuted,
              height: 1.3,
            ),
          ),
          SizedBox(height: phonePortrait ? 8 : 10),
          Center(
            child: Container(
              width: isTablet ? 56 : 44,
              height: 4,
              decoration: BoxDecoration(
                color: reserveAccent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          if (widget.missingCount > 0) ...[
            SizedBox(height: phonePortrait ? 10 : 12),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3A2A14)
                      : const Color(0xFFFFF8E8),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFFB45309)
                        : const Color(0xFFFFCC80),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: isDark
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFFE65100),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'รถใช้งานวันนี้ยังไม่เติม ${widget.missingCount} คัน',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: phonePortrait ? 12.5 : 13.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFFE65100),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final mainCard = _TankChoiceCard(
      title: 'ถังหลัก',
      locationTag: 'พล่าม',
      hint: 'เติมที่พล่าม · หักสต็อกถังหลัก',
      liters: widget.mainDieselLiters,
      capacity: null,
      summary: widget.mainSummary,
      icon: Icons.propane_tank_rounded,
      accent: mainAccent,
      iconBg: mainIconBg,
      compact: phonePortrait,
      isTablet: isTablet,
      isDark: isDark,
      onTap: () => widget.onSelect(kFuelTankMain),
    );

    final reserveCard = _TankChoiceCard(
      title: 'ถังสำรอง',
      locationTag: 'หน้างาน / เครื่องจักร',
      hint: 'เติมหน้างาน · หักสต็อกถังสำรอง',
      liters: widget.reserveDieselLiters,
      capacity: kFuelTankCapacityReserveLiters,
      summary: widget.reserveSummary,
      icon: Icons.local_gas_station_rounded,
      accent: reserveAccent,
      iconBg: reserveIconBg,
      compact: phonePortrait,
      isTablet: isTablet,
      isDark: isDark,
      onTap: () => widget.onSelect(kFuelTankReserve),
    );

    final options = useColumns
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _stagger(1, mainCard)),
                SizedBox(width: gap),
                Expanded(child: _stagger(2, reserveCard)),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _stagger(1, mainCard),
              SizedBox(height: gap),
              _stagger(2, reserveCard),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        SizedBox(height: phonePortrait ? 14 : 18),
        options,
      ],
    );
  }
}

class _TankChoiceCard extends StatelessWidget {
  const _TankChoiceCard({
    required this.title,
    required this.locationTag,
    required this.hint,
    required this.liters,
    required this.capacity,
    required this.summary,
    required this.icon,
    required this.accent,
    required this.iconBg,
    required this.compact,
    required this.isTablet,
    required this.isDark,
    required this.onTap,
  });

  final String title;
  final String locationTag;
  final String hint;
  final double liters;
  final double? capacity;
  final FuelMacroTankDaySummary summary;
  final IconData icon;
  final Color accent;
  final Color iconBg;
  final bool compact;
  final bool isTablet;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final cap = capacity == null || capacity! <= 0 ? null : capacity;
    final ratio = cap == null ? null : (liters / cap).clamp(0.0, 1.0);
    final isNegative = liters < 0;
    final isLow = isNegative || (ratio == null ? liters <= 0 : ratio <= 0.15);
    final dangerColor = isDark
        ? const Color(0xFFF87171)
        : const Color(0xFFD14343);
    final balanceColor = isLow ? dangerColor : accent;
    final balanceText = isNegative
        ? 'ติดลบ ${formatFuelLiters(liters.abs())} ลิตร'
        : cap == null
            ? 'คงเหลือ ${formatFuelLiters(liters)} ลิตร'
            : '${formatFuelLiters(liters)} / ${formatFuelLiters(cap)} ลิตร';

    final statusBg = summary.hasEntries
        ? accent.withValues(alpha: isDark ? 0.18 : 0.09)
        : (isDark ? p.chipSurface : const Color(0xFFF8FAFC));
    final statusBorder = summary.hasEntries
        ? accent.withValues(alpha: isDark ? 0.45 : 0.3)
        : p.hairline;

    return Semantics(
      button: true,
      label: '$title ($locationTag) $balanceText',
      child: SoftPressButton(
        onTap: onTap,
        size: SoftPressSize.large,
        borderRadius: 20,
        isDarkSurface: isDark,
        liftWhenIdle: true,
        depthShadow: SoftPressDepthShadow(
          color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
          blurRadius: 14,
          offsetY: 4,
          pressedBlurRadius: 5,
          pressedOffsetY: 1,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: summary.hasEntries
                  ? accent.withValues(alpha: isDark ? 0.55 : 0.45)
                  : p.hairline,
              width: summary.hasEntries ? 1.5 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 5, color: isLow ? dangerColor : accent),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(
                        compact ? 14 : (isTablet ? 18 : 16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: compact ? 48 : 54,
                                height: compact ? 48 : 54,
                                decoration: BoxDecoration(
                                  color: iconBg,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  icon,
                                  color: accent,
                                  size: compact ? 26 : 30,
                                ),
                              ),
                              SizedBox(width: compact ? 12 : 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          title,
                                          style: TextStyle(
                                            fontSize: compact ? 19 : 21,
                                            fontWeight: FontWeight.w800,
                                            height: 1.12,
                                            color: p.ink,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: iconBg,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            locationTag,
                                            style: TextStyle(
                                              fontSize: compact ? 11.5 : 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: accent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (isLow) ...[
                                          Icon(
                                            Icons.warning_amber_rounded,
                                            size: 16,
                                            color: dangerColor,
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        Expanded(
                                          child: Text(
                                            balanceText,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: compact ? 15 : 16.5,
                                              fontWeight: FontWeight.w800,
                                              color: balanceColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: accent,
                                size: compact ? 28 : 32,
                              ),
                            ],
                          ),
                          if (ratio != null) ...[
                            SizedBox(height: compact ? 10 : 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: compact ? 7 : 8,
                                backgroundColor: isDark
                                    ? const Color(0xFF243444)
                                    : const Color(0xFFDDE7F3),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  balanceColor,
                                ),
                              ),
                            ),
                          ],
                          SizedBox(height: compact ? 10 : 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: statusBorder),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  summary.hasEntries
                                      ? Icons.check_circle_rounded
                                      : Icons.touch_app_rounded,
                                  size: 16,
                                  color: summary.hasEntries
                                      ? accent
                                      : p.inkMuted,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    summary.hasEntries
                                        ? 'วันนี้บันทึกแล้ว ${summary.fueledCount} คัน · ${formatFuelLiters(summary.liters)} ลิตร'
                                        : hint,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: compact ? 12.5 : 13.5,
                                      fontWeight: summary.hasEntries
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: summary.hasEntries
                                          ? accent
                                          : p.inkMuted,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
