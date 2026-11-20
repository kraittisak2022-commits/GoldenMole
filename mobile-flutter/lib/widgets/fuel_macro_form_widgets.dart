import 'package:flutter/material.dart';

import '../theme/daily_palette.dart';
import '../utils/fuel_stock.dart';
import 'app_theme_scope.dart';

/// สีประจำถังน้ำมันรถแม็คโคร (ถังหลัก = น้ำเงิน, ถังสำรอง = เขียวน้ำทะเล)
Color fuelMacroTankAccent(
  String tank, {
  required bool isDark,
  required DailyColors palette,
}) {
  if (fuelTankIsReserve(tank)) {
    return isDark ? palette.brand : const Color(0xFF0D98A5);
  }
  return isDark ? const Color(0xFF60A5FA) : const Color(0xFF1565C0);
}

Color fuelMacroTankTintBg(String tank, {required bool isDark}) {
  if (fuelTankIsReserve(tank)) {
    return isDark ? const Color(0xFF12323A) : const Color(0xFFE0F7FA);
  }
  return isDark ? const Color(0xFF172B44) : const Color(0xFFE3F2FD);
}

/// แถบหัวฟอร์มน้ำมันรถแม็คโคร: แสดงถังที่เลือก + ยอดคงเหลือเรียลไทม์ + ปุ่มเปลี่ยนถัง
class FuelMacroTankHeader extends StatelessWidget {
  const FuelMacroTankHeader({
    super.key,
    required this.activeTank,
    required this.mainDieselLiters,
    required this.reserveDieselLiters,
    required this.pendingDelta,
    required this.reserveShortfallLiters,
    required this.onSwitchTank,
  });

  final String activeTank;
  final double mainDieselLiters;
  final double reserveDieselLiters;
  final double pendingDelta;
  final double reserveShortfallLiters;
  final VoidCallback onSwitchTank;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final size = MediaQuery.sizeOf(context);
    final phonePortrait = size.shortestSide < 600 && size.height >= size.width;
    final isReserve = fuelTankIsReserve(activeTank);
    final accent = fuelMacroTankAccent(
      activeTank,
      isDark: isDark,
      palette: p,
    );
    final tintBg = fuelMacroTankTintBg(activeTank, isDark: isDark);
    final current = isReserve ? reserveDieselLiters : mainDieselLiters;
    final otherCurrent = isReserve ? mainDieselLiters : reserveDieselLiters;
    final otherTankName = isReserve ? 'ถังหลัก' : 'ถังสำรอง';
    final preview = current + pendingDelta;
    final capacity = isReserve ? kFuelTankCapacityReserveLiters : null;
    final ratio = capacity == null ? null : (preview / capacity).clamp(0.0, 1.0);
    final isNegative = preview < 0;
    final isOverCap = capacity != null && preview > capacity;
    final warn = isNegative || isOverCap;
    final dangerColor = isDark
        ? const Color(0xFFF87171)
        : const Color(0xFFD14343);
    final activeBorder = warn
        ? (isDark ? const Color(0xFF7F1D1D) : const Color(0xFFF5C2C2))
        : accent.withValues(alpha: isDark ? 0.45 : 0.35);

    final hasDelta = pendingDelta.abs() > 1e-9;
    final deltaPrefix = pendingDelta > 0 ? '+' : '-';
    final deltaText = '$deltaPrefix${formatFuelLiters(pendingDelta.abs())} ล.';

    return Container(
      padding: EdgeInsets.all(phonePortrait ? 12 : 14),
      decoration: BoxDecoration(
        color: warn
            ? (isDark ? const Color(0xFF331818) : const Color(0xFFFFF5F5))
            : (isDark ? p.chipSurface : const Color(0xFFF6FAFE)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: activeBorder, width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: phonePortrait ? 40 : 44,
                height: phonePortrait ? 40 : 44,
                decoration: BoxDecoration(
                  color: tintBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isReserve
                      ? Icons.local_gas_station_rounded
                      : Icons.propane_tank_rounded,
                  size: phonePortrait ? 22 : 24,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'น้ำมันรถแม็คโคร · ดีเซล',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: phonePortrait ? 11.5 : 12.5,
                        fontWeight: FontWeight.w600,
                        color: p.inkMuted,
                      ),
                    ),
                    Text(
                      isReserve ? 'ถังสำรอง (หน้างาน)' : 'ถังหลัก (พล่าม)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: phonePortrait ? 17 : 19,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: isDark ? p.card : Colors.white,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onSwitchTank,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: phonePortrait ? 10 : 12,
                      vertical: phonePortrait ? 7 : 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: accent.withValues(alpha: isDark ? 0.55 : 0.45),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.swap_horiz_rounded,
                          size: 16,
                          color: accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'เปลี่ยนถัง',
                          style: TextStyle(
                            fontSize: phonePortrait ? 12.5 : 13.5,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: phonePortrait ? 10 : 12),
          Divider(height: 1, color: p.hairline),
          SizedBox(height: phonePortrait ? 10 : 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'คงเหลือ ',
                    style: TextStyle(
                      fontSize: phonePortrait ? 13 : 14,
                      fontWeight: FontWeight.w600,
                      color: p.inkMuted,
                    ),
                  ),
                  Text(
                    capacity == null
                        ? '${formatFuelLiters(current)} ล.'
                        : '${formatFuelLiters(current)} / ${formatFuelLiters(capacity)} ล.',
                    style: TextStyle(
                      fontSize: phonePortrait ? 14.5 : 16,
                      fontWeight: FontWeight.w800,
                      color: p.ink,
                    ),
                  ),
                ],
              ),
              if (hasDelta)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: warn
                        ? dangerColor.withValues(alpha: isDark ? 0.22 : 0.12)
                        : accent.withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$deltaText → เหลือ ${formatFuelLiters(preview)} ล.',
                    style: TextStyle(
                      fontSize: phonePortrait ? 12.5 : 13.5,
                      fontWeight: FontWeight.w800,
                      color: warn ? dangerColor : accent,
                    ),
                  ),
                ),
            ],
          ),
          if (ratio != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 7,
                backgroundColor: isDark
                    ? const Color(0xFF243444)
                    : const Color(0xFFDDE7F3),
                valueColor: AlwaysStoppedAnimation<Color>(
                  warn ? dangerColor : accent,
                ),
              ),
            ),
          ],
          if (isNegative) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: dangerColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isReserve
                        ? 'ถังสำรองติดลบ ${formatFuelLiters(preview.abs())} ล. '
                            '(ขาดบันทึกโอนเข้าสำรอง ~${formatFuelLiters(reserveShortfallLiters > 0 ? reserveShortfallLiters : preview.abs())} ล.)'
                        : 'ถังหลักติดลบ ${formatFuelLiters(preview.abs())} ล. (เบิกเกินยอดคงเหลือ)',
                    style: TextStyle(
                      fontSize: phonePortrait ? 12 : 13,
                      fontWeight: FontWeight.w700,
                      color: dangerColor,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (isOverCap) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: dangerColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'เกินความจุถังสำรอง (ยังบันทึกได้)',
                    style: TextStyle(
                      fontSize: phonePortrait ? 12 : 13,
                      fontWeight: FontWeight.w700,
                      color: dangerColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '$otherTankNameคงเหลือ ${formatFuelLiters(otherCurrent)} ลิตร',
            style: TextStyle(
              fontSize: phonePortrait ? 11.5 : 12.5,
              fontWeight: FontWeight.w500,
              color: p.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// การ์ดกรอกน้ำมันรถแม็คโครรายคัน — แยกจากตัวเลือกถังเพื่อให้กรอกเร็วและอ่านง่าย
class FuelMacroVehicleCard extends StatelessWidget {
  const FuelMacroVehicleCard({
    super.key,
    required this.displayIndex,
    required this.vehicleName,
    required this.driverLabel,
    required this.activeTank,
    required this.litersText,
    required this.timeText,
    required this.isSaved,
    required this.workedToday,
    required this.missingFuelAfterWork,
    required this.otherTankSummary,
    required this.onTapLiters,
    required this.onTapTime,
    required this.onClearOrDelete,
    this.dismissKey,
  });

  final int displayIndex;
  final String vehicleName;
  final String driverLabel;
  final String activeTank;
  final String litersText;
  final String timeText;
  final bool isSaved;
  final bool workedToday;
  final bool missingFuelAfterWork;
  final String otherTankSummary;
  final VoidCallback onTapLiters;
  final VoidCallback onTapTime;
  final Future<void> Function() onClearOrDelete;
  final Key? dismissKey;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final size = MediaQuery.sizeOf(context);
    final phonePortrait = size.shortestSide < 600 && size.height >= size.width;

    final liters = double.tryParse(litersText.trim()) ?? 0;
    final hasLiters = liters > 0;
    final hasTime = timeText.trim().isNotEmpty;
    final hasData = isSaved || hasLiters || hasTime || litersText.trim().isNotEmpty;
    final isComplete = hasLiters && hasTime;

    final accent = fuelMacroTankAccent(
      activeTank,
      isDark: isDark,
      palette: p,
    );
    final tintBg = fuelMacroTankTintBg(activeTank, isDark: isDark);
    final amberAccent = isDark
        ? const Color(0xFFFBBF24)
        : const Color(0xFFE65100);
    final greenAccent = isDark
        ? const Color(0xFF4ADE80)
        : const Color(0xFF2E7D32);

    final Color stripeColor;
    final Color cardBg;
    final Color cardBorder;
    if (isSaved && hasLiters) {
      stripeColor = greenAccent;
      cardBg = isDark ? const Color(0xFF132A20) : const Color(0xFFF4FBF6);
      cardBorder = greenAccent.withValues(alpha: isDark ? 0.5 : 0.42);
    } else if (isComplete || hasLiters) {
      stripeColor = accent;
      cardBg = isDark
          ? accent.withValues(alpha: 0.1)
          : accent.withValues(alpha: 0.05);
      cardBorder = accent.withValues(alpha: isDark ? 0.55 : 0.45);
    } else if (missingFuelAfterWork) {
      stripeColor = amberAccent;
      cardBg = isDark ? const Color(0xFF332512) : const Color(0xFFFFFBF2);
      cardBorder = isDark ? const Color(0xFFB45309) : const Color(0xFFFFCC80);
    } else {
      stripeColor = p.hairline;
      cardBg = isDark ? p.chipSurface : const Color(0xFFFAFCFE);
      cardBorder = isDark ? p.hairline : const Color(0xFFDCE8F5);
    }

    Widget statusPill() {
      if (isSaved && hasLiters) {
        return _StatusChip(
          label: 'บันทึกแล้ว',
          icon: Icons.check_circle_rounded,
          fg: greenAccent,
          bg: isDark ? const Color(0xFF1A3A24) : const Color(0xFFE8F5E9),
          border: greenAccent.withValues(alpha: 0.4),
        );
      }
      if (missingFuelAfterWork) {
        return _StatusChip(
          label: 'ยังไม่เติม',
          icon: Icons.schedule_rounded,
          fg: amberAccent,
          bg: isDark ? const Color(0xFF3A2A14) : const Color(0xFFFFF3E0),
          border: isDark ? const Color(0xFFB45309) : const Color(0xFFFFB74D),
        );
      }
      if (workedToday) {
        return _StatusChip(
          label: 'ใช้รถวันนี้',
          icon: Icons.front_loader,
          fg: accent,
          bg: tintBg,
          border: accent.withValues(alpha: 0.35),
        );
      }
      return const SizedBox.shrink();
    }

    final card = Container(
      margin: EdgeInsets.only(bottom: phonePortrait ? 10 : 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cardBorder,
          width: (isSaved || hasLiters || missingFuelAfterWork) ? 1.4 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: stripeColor),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(phonePortrait ? 12 : 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: phonePortrait ? 34 : 38,
                            height: phonePortrait ? 34 : 38,
                            decoration: BoxDecoration(
                              color: (isSaved && hasLiters)
                                  ? greenAccent.withValues(
                                      alpha: isDark ? 0.22 : 0.14,
                                    )
                                  : missingFuelAfterWork
                                      ? amberAccent.withValues(
                                          alpha: isDark ? 0.22 : 0.14,
                                        )
                                      : tintBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: (isSaved && hasLiters)
                                ? Icon(
                                    Icons.check_rounded,
                                    size: 20,
                                    color: greenAccent,
                                  )
                                : Text(
                                    '$displayIndex',
                                    style: TextStyle(
                                      fontSize: phonePortrait ? 15 : 16,
                                      fontWeight: FontWeight.w800,
                                      color: missingFuelAfterWork
                                          ? amberAccent
                                          : accent,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vehicleName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: phonePortrait ? 16.5 : 18.5,
                                    fontWeight: FontWeight.w800,
                                    color: p.ink,
                                    height: 1.18,
                                  ),
                                ),
                                if (driverLabel.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.person_outline_rounded,
                                        size: 13.5,
                                        color: p.inkMuted,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'คนขับ: $driverLabel',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: phonePortrait ? 12.5 : 13.5,
                                            fontWeight: FontWeight.w600,
                                            color: p.inkMuted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          statusPill(),
                          if (hasData) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: isSaved ? 'ลบรายการนี้' : 'ล้างค่า',
                              onPressed: onClearOrDelete,
                              visualDensity: VisualDensity.compact,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(38, 38),
                                backgroundColor: isSaved
                                    ? const Color(0xFFD14343).withValues(
                                        alpha: isDark ? 0.2 : 0.09,
                                      )
                                    : p.hairline.withValues(alpha: 0.4),
                              ),
                              icon: Icon(
                                isSaved
                                    ? Icons.delete_outline_rounded
                                    : Icons.close_rounded,
                                size: 19,
                                color: isSaved
                                    ? (isDark
                                        ? const Color(0xFFF87171)
                                        : const Color(0xFFD14343))
                                    : p.inkMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (otherTankSummary.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? p.card.withValues(alpha: 0.7)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: p.hairline),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 14.5,
                                color: p.inkSubtle,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  otherTankSummary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: phonePortrait ? 12 : 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: p.inkSubtle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _TapInputBox(
                              label: 'ปริมาณน้ำมัน',
                              value: hasLiters ? litersText.trim() : '',
                              unit: hasLiters ? 'ลิตร' : null,
                              placeholder: 'แตะกรอกลิตร',
                              icon: Icons.opacity_rounded,
                              accent: accent,
                              active: hasLiters,
                              isDark: isDark,
                              compact: phonePortrait,
                              onTap: onTapLiters,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: _TapInputBox(
                              label: 'เวลาเติม',
                              value: hasTime ? timeText.trim() : '',
                              unit: null,
                              placeholder: 'เลือกเวลา',
                              icon: Icons.schedule_rounded,
                              accent: accent,
                              active: hasTime,
                              isDark: isDark,
                              compact: phonePortrait,
                              onTap: onTapTime,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!hasData) return card;

    return Dismissible(
      key: dismissKey ?? ValueKey('fuel_macro_card_$vehicleName'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await onClearOrDelete();
        return false;
      },
      background: Container(
        margin: EdgeInsets.only(bottom: phonePortrait ? 10 : 12),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFD14343),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'ลบ',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.delete_outline_rounded, color: Colors.white),
          ],
        ),
      ),
      child: card,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: fg),
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

class _TapInputBox extends StatelessWidget {
  const _TapInputBox({
    required this.label,
    required this.value,
    required this.unit,
    required this.placeholder,
    required this.icon,
    required this.accent,
    required this.active,
    required this.isDark,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final String value;
  final String? unit;
  final String placeholder;
  final IconData icon;
  final Color accent;
  final bool active;
  final bool isDark;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final bg = isDark ? p.card : Colors.white;
    final border = active
        ? accent.withValues(alpha: isDark ? 0.65 : 0.55)
        : p.hairline;

    return Semantics(
      button: true,
      label: active ? '$label $value ${unit ?? ''}'.trim() : '$label $placeholder',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: compact ? 58 : 64),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 7 : 9,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: border, width: active ? 1.5 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: active ? accent : p.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      icon,
                      size: compact ? 17 : 19,
                      color: active ? accent : p.inkMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: active
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Flexible(
                                  child: Text(
                                    value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: compact ? 19 : 21,
                                      fontWeight: FontWeight.w800,
                                      color: p.ink,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                                if (unit != null) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    unit!,
                                    style: TextStyle(
                                      fontSize: compact ? 12.5 : 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: p.inkMuted,
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : Text(
                              placeholder,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: compact ? 14 : 15,
                                fontWeight: FontWeight.w500,
                                color: p.inkMuted.withValues(alpha: 0.8),
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
