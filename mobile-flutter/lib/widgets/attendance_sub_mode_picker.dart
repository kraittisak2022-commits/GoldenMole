import 'package:flutter/material.dart';

import '../theme/daily_palette.dart';
import '../utils/attendance_board_summary.dart';
import '../utils/device_perf.dart';
import 'app_theme_scope.dart';
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
    this.dateLabel = '',
    this.sandProgress = const AttendanceGroupProgress(),
    this.driverProgress = const AttendanceGroupProgress(),
    this.sandStats = const [],
    this.driverStats = const [],
  });

  final ValueChanged<AttendanceSection> onSelect;
  final String sandYardSummary;
  final String driverSummary;
  final String dateLabel;
  final AttendanceGroupProgress sandProgress;
  final AttendanceGroupProgress driverProgress;
  final List<AttendanceStatBadgeData> sandStats;
  final List<AttendanceStatBadgeData> driverStats;

  @override
  State<AttendanceSubModePicker> createState() =>
      _AttendanceSubModePickerState();
}

class _AttendanceSubModePickerState extends State<AttendanceSubModePicker>
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
    final titleSize = phonePortrait ? 21.0 : (isTablet ? 28.0 : 24.0);

    final totalAll =
        widget.sandProgress.totalCount + widget.driverProgress.totalCount;
    final checkedAll =
        widget.sandProgress.checkedCount + widget.driverProgress.checkedCount;
    final allDone = totalAll > 0 && checkedAll >= totalAll;

    final sandAccent = isDark ? p.brand : const Color(0xFF0D9488);
    final sandIconBg = isDark
        ? const Color(0xFF133330)
        : const Color(0xFFE0F7F4);
    final driverAccent = isDark
        ? const Color(0xFF38BDF8)
        : const Color(0xFF0284C7);
    final driverIconBg = isDark
        ? const Color(0xFF132D42)
        : const Color(0xFFE0F2FE);

    final header = _staggerTile(
      0,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.dateLabel.trim().isNotEmpty) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: p.brandSurface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: p.brandBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 13.5,
                      color: p.brandDateInk,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'วันที่ ${widget.dateLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: phonePortrait ? 12 : 13,
                          fontWeight: FontWeight.w700,
                          color: p.brandDateInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: phonePortrait ? 8 : 10),
          ],
          Text(
            'เลือกกลุ่มเช็คชื่อ',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w800,
              height: 1.12,
              letterSpacing: -0.4,
              color: p.ink,
            ),
          ),
          SizedBox(height: phonePortrait ? 4 : 6),
          Text(
            totalAll > 0
                ? (allDone
                    ? 'เช็คชื่อครบทั้งหมด $checkedAll / $totalAll คนแล้ว'
                    : 'ภาพรวมวันนี้ เช็คชื่อแล้ว $checkedAll / $totalAll คน')
                : 'แตะเลือกกลุ่มเพื่อเข้ากระดานเช็คชื่อแบบเต็มจอ',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: phonePortrait ? 13.0 : (isTablet ? 15.0 : 14.0),
              fontWeight: allDone ? FontWeight.w700 : FontWeight.w500,
              color: allDone ? p.statusComplete : p.inkMuted,
              height: 1.3,
            ),
          ),
          SizedBox(height: phonePortrait ? 8 : 10),
          Center(
            child: Container(
              width: isTablet ? 56 : 44,
              height: 4,
              decoration: BoxDecoration(
                color: allDone ? p.statusComplete : p.brand,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );

    final sandCard = _AttendanceGroupCard(
      title: 'เช็คชื่อพนักงานท่าทราย',
      roleHint: 'มาทำงาน · ลางาน (เต็มวัน / เช้า / บ่าย)',
      fallbackSummary: widget.sandYardSummary,
      progress: widget.sandProgress,
      stats: widget.sandStats,
      icon: Icons.groups_rounded,
      accent: sandAccent,
      iconBg: sandIconBg,
      compact: phonePortrait,
      isTablet: isTablet,
      isDark: isDark,
      onTap: () => widget.onSelect(AttendanceSection.sandYard),
    );

    final driverCard = _AttendanceGroupCard(
      title: 'เช็คชื่อคนขับรถ',
      roleHint: 'ขับรถแม็คโคร · ขับรถดรัม · ลางาน',
      fallbackSummary: widget.driverSummary,
      progress: widget.driverProgress,
      stats: widget.driverStats,
      icon: Icons.local_shipping_rounded,
      accent: driverAccent,
      iconBg: driverIconBg,
      compact: phonePortrait,
      isTablet: isTablet,
      isDark: isDark,
      onTap: () => widget.onSelect(AttendanceSection.driver),
    );

    final options = useColumns
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _staggerTile(1, sandCard)),
                SizedBox(width: gap),
                Expanded(child: _staggerTile(2, driverCard)),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _staggerTile(1, sandCard),
              SizedBox(height: gap),
              _staggerTile(2, driverCard),
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

class _AttendanceGroupCard extends StatelessWidget {
  const _AttendanceGroupCard({
    required this.title,
    required this.roleHint,
    required this.fallbackSummary,
    required this.progress,
    required this.stats,
    required this.icon,
    required this.accent,
    required this.iconBg,
    required this.compact,
    required this.isTablet,
    required this.isDark,
    required this.onTap,
  });

  final String title;
  final String roleHint;
  final String fallbackSummary;
  final AttendanceGroupProgress progress;
  final List<AttendanceStatBadgeData> stats;
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
    final isComplete = progress.isComplete;
    final hasAny = progress.hasAny || stats.isNotEmpty;
    final stripeColor = isComplete ? p.statusComplete : accent;

    Widget statusBadge() {
      if (isComplete) {
        return _MiniStatusPill(
          label: 'ครบแล้ว',
          icon: Icons.check_circle_rounded,
          fg: p.statusComplete,
          bg: p.statusComplete.withValues(alpha: isDark ? 0.2 : 0.11),
          border: p.statusComplete.withValues(alpha: 0.4),
        );
      }
      if (progress.totalCount > 0 && progress.hasAny) {
        return _MiniStatusPill(
          label: 'เหลือ ${progress.remainingCount} คน',
          icon: Icons.schedule_rounded,
          fg: accent,
          bg: accent.withValues(alpha: isDark ? 0.18 : 0.1),
          border: accent.withValues(alpha: 0.35),
        );
      }
      if (progress.totalCount > 0) {
        return _MiniStatusPill(
          label: '${progress.totalCount} คน',
          icon: Icons.person_outline_rounded,
          fg: p.inkMuted,
          bg: p.chipSurface,
          border: p.hairline,
        );
      }
      return const SizedBox.shrink();
    }

    return Semantics(
      button: true,
      label: title,
      child: SoftPressButton(
        onTap: onTap,
        size: SoftPressSize.large,
        borderRadius: 20,
        isDarkSurface: isDark,
        liftWhenIdle: true,
        depthShadow: SoftPressDepthShadow(
          color: stripeColor.withValues(alpha: isDark ? 0.22 : 0.11),
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
              color: hasAny
                  ? stripeColor.withValues(alpha: isDark ? 0.5 : 0.38)
                  : p.hairline,
              width: hasAny ? 1.4 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 5, color: stripeColor),
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
                                  size: compact ? 25 : 28,
                                ),
                              ),
                              SizedBox(width: compact ? 12 : 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: compact ? 17.5 : 20,
                                        fontWeight: FontWeight.w800,
                                        height: 1.15,
                                        letterSpacing: -0.25,
                                        color: p.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      roleHint,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: compact ? 12 : 13,
                                        fontWeight: FontWeight.w500,
                                        color: p.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: stripeColor,
                                size: compact ? 26 : 30,
                              ),
                            ],
                          ),
                          if (progress.totalCount > 0) ...[
                            SizedBox(height: compact ? 12 : 14),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'เช็คชื่อแล้ว ${progress.checkedCount} / ${progress.totalCount} คน',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: compact ? 13 : 14,
                                      fontWeight: FontWeight.w700,
                                      color: isComplete
                                          ? p.statusComplete
                                          : p.inkSubtle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                statusBadge(),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: progress.ratio,
                                minHeight: compact ? 6.5 : 7.5,
                                backgroundColor: isDark
                                    ? const Color(0xFF243444)
                                    : const Color(0xFFE2E8F0),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  stripeColor,
                                ),
                              ),
                            ),
                          ],
                          SizedBox(height: compact ? 10 : 12),
                          if (stats.isNotEmpty)
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final s in stats)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: s.color.withValues(
                                        alpha: isDark ? 0.18 : 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: s.color.withValues(
                                          alpha: isDark ? 0.42 : 0.28,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6.5,
                                          height: 6.5,
                                          decoration: BoxDecoration(
                                            color: s.color,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          '${s.label} ${s.count}',
                                          style: TextStyle(
                                            fontSize: compact ? 12 : 13,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? p.ink
                                                : s.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: p.chipSurface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: p.hairline),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.touch_app_rounded,
                                    size: 15,
                                    color: p.inkMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      fallbackSummary.trim().isNotEmpty
                                          ? fallbackSummary
                                          : 'แตะเพื่อเริ่มเช็คชื่อวันนี้',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: compact ? 12.5 : 13.5,
                                        fontWeight: FontWeight.w500,
                                        color: p.inkMuted,
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

class _MiniStatusPill extends StatelessWidget {
  const _MiniStatusPill({
    required this.label,
    required this.icon,
    required this.fg,
    required this.bg,
    required this.border,
  });

  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
