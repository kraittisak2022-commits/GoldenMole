import 'package:flutter/material.dart';

import '../theme/daily_palette.dart';
import '../utils/attendance_board_summary.dart';
import '../utils/macro_vehicle_summary.dart';
import 'app_theme_scope.dart';

/// ตัวเลือกคนขับสำหรับรถแม็คโคร 1 คัน
class MacroDriverOption {
  const MacroDriverOption({
    required this.id,
    required this.displayName,
    required this.isDefault,
  });

  final String id;
  final String displayName;
  final bool isDefault;
}

/// แถบสรุปภาพรวมฝูงรถแม็คโคร + ตัวกรองด้านบนของหน้าบันทึก
class MacroFleetHeader extends StatelessWidget {
  const MacroFleetHeader({
    super.key,
    required this.dateLabel,
    required this.overview,
    required this.filter,
    required this.hasUnsavedChanges,
    required this.onFilterChanged,
  });

  final String dateLabel;
  final MacroFleetOverview overview;
  final MacroFleetFilter filter;
  final bool hasUnsavedChanges;
  final ValueChanged<MacroFleetFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final size = MediaQuery.sizeOf(context);
    final phonePortrait = size.shortestSide < 600 && size.height >= size.width;
    final accent = isDark ? p.brand : const Color(0xFF0F9EA8);
    final showFilters = overview.totalCount >= 3;

    return Container(
      padding: EdgeInsets.all(phonePortrait ? 12 : 14),
      decoration: BoxDecoration(
        color: isDark ? p.chipSurface : const Color(0xFFF6FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? p.hairline : const Color(0xFFDCE8F4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: phonePortrait ? 36 : 40,
                height: phonePortrait ? 36 : 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.front_loader,
                  size: phonePortrait ? 20 : 22,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ภาพรวมการใช้รถแม็คโคร',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: phonePortrait ? 15.5 : 17.5,
                        fontWeight: FontWeight.w800,
                        color: p.ink,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'วันที่ $dateLabel · แตะเลือกงานเฉพาะคันที่ทำงาน',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: phonePortrait ? 11.5 : 12.5,
                        fontWeight: FontWeight.w500,
                        color: p.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasUnsavedChanges) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: p.statusIncomplete.withValues(
                      alpha: isDark ? 0.2 : 0.12,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: p.statusIncomplete,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'ยังไม่บันทึก',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: p.statusIncomplete,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: phonePortrait ? 10 : 12),
          Row(
            children: [
              Expanded(
                child: _FleetKpiTile(
                  label: 'ทำงานวันนี้',
                  value: '${overview.activeCount}/${overview.totalCount}',
                  accent: accent,
                  isDark: isDark,
                  compact: phonePortrait,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FleetKpiTile(
                  label: 'บันทึกแล้ว',
                  value: '${overview.savedCount}',
                  accent: p.statusComplete,
                  isDark: isDark,
                  compact: phonePortrait,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FleetKpiTile(
                  label: 'ไม่ได้ทำงาน',
                  value: '${overview.idleCount}',
                  accent: p.inkMuted,
                  isDark: isDark,
                  compact: phonePortrait,
                ),
              ),
            ],
          ),
          if (overview.totalCount > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: overview.activeRatio),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, val, _) => LinearProgressIndicator(
                  value: val,
                  minHeight: 6,
                  backgroundColor: isDark
                      ? const Color(0xFF243444)
                      : const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
            ),
          ],
          if (showFilters) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _FilterPill(
                    label: 'ทั้งหมด (${overview.totalCount})',
                    selected: filter == MacroFleetFilter.all,
                    accent: accent,
                    isDark: isDark,
                    onTap: () => onFilterChanged(MacroFleetFilter.all),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _FilterPill(
                    label: 'ทำงาน (${overview.activeCount})',
                    selected: filter == MacroFleetFilter.working,
                    accent: accent,
                    isDark: isDark,
                    onTap: () => onFilterChanged(MacroFleetFilter.working),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _FilterPill(
                    label: 'ว่าง (${overview.idleCount})',
                    selected: filter == MacroFleetFilter.idle,
                    accent: accent,
                    isDark: isDark,
                    onTap: () => onFilterChanged(MacroFleetFilter.idle),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FleetKpiTile extends StatelessWidget {
  const _FleetKpiTile({
    required this.label,
    required this.value,
    required this.accent,
    required this.isDark,
    required this.compact,
  });

  final String label;
  final String value;
  final Color accent;
  final bool isDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 7 : 9,
      ),
      decoration: BoxDecoration(
        color: isDark ? p.card : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: p.inkMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 17 : 20,
              fontWeight: FontWeight.w800,
              color: accent,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    return Material(
      color: selected ? accent : (isDark ? p.card : Colors.white),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? accent : p.hairline,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected
                  ? (isDark ? const Color(0xFF0B1219) : Colors.white)
                  : p.inkSubtle,
            ),
          ),
        ),
      ),
    );
  }
}

/// ชุดสีประจำคันรถแม็คโคร — แยกสีแต่ละคันชัดเจนทั้ง Light และ Dark mode
@immutable
class MacroVehicleColorTheme {
  const MacroVehicleColorTheme({
    required this.name,
    required this.lightPrimary,
    required this.darkPrimary,
    required this.lightCardBg,
    required this.darkCardBg,
    required this.lightHeaderBg,
    required this.darkHeaderBg,
    required this.lightBorder,
    required this.darkBorder,
  });

  final String name;
  final Color lightPrimary;
  final Color darkPrimary;
  final Color lightCardBg;
  final Color darkCardBg;
  final Color lightHeaderBg;
  final Color darkHeaderBg;
  final Color lightBorder;
  final Color darkBorder;

  Color primary(bool isDark) => isDark ? darkPrimary : lightPrimary;
  Color cardBg(bool isDark) => isDark ? darkCardBg : lightCardBg;
  Color headerBg(bool isDark) => isDark ? darkHeaderBg : lightHeaderBg;
  Color border(bool isDark) => isDark ? darkBorder : lightBorder;

  /// สีตัวอักษร/ไอคอนบนพื้นสี [primary] ให้อ่านชัดเสมอ
  Color onPrimary(bool isDark) =>
      primary(isDark).computeLuminance() > 0.45
          ? const Color(0xFF0B1219)
          : Colors.white;
}

/// 8 โทนสีชัดเจนสำหรับรถแม็คโครแต่ละคัน (ไม่ซ้ำกันในฝูงรถปกติ)
const List<MacroVehicleColorTheme> kMacroVehicleColorPalette = [
  MacroVehicleColorTheme(
    name: 'oceanBlue',
    lightPrimary: Color(0xFF0284C7),
    darkPrimary: Color(0xFF38BDF8),
    lightCardBg: Color(0xFFF4FAFF),
    darkCardBg: Color(0xFF0E2130),
    lightHeaderBg: Color(0xFFE6F4FE),
    darkHeaderBg: Color(0xFF132E42),
    lightBorder: Color(0xFF93D5FB),
    darkBorder: Color(0xFF1E5678),
  ),
  MacroVehicleColorTheme(
    name: 'vividOrange',
    lightPrimary: Color(0xFFEA580C),
    darkPrimary: Color(0xFFFB923C),
    lightCardBg: Color(0xFFFFF8F3),
    darkCardBg: Color(0xFF2B190E),
    lightHeaderBg: Color(0xFFFFEDD5),
    darkHeaderBg: Color(0xFF3E2211),
    lightBorder: Color(0xFFFDBA74),
    darkBorder: Color(0xFF7C3A16),
  ),
  MacroVehicleColorTheme(
    name: 'royalViolet',
    lightPrimary: Color(0xFF7C3AED),
    darkPrimary: Color(0xFFA78BFA),
    lightCardBg: Color(0xFFF8F5FF),
    darkCardBg: Color(0xFF1C1633),
    lightHeaderBg: Color(0xFFEDE9FE),
    darkHeaderBg: Color(0xFF281F4A),
    lightBorder: Color(0xFFC4B5FD),
    darkBorder: Color(0xFF4F3B8A),
  ),
  MacroVehicleColorTheme(
    name: 'emerald',
    lightPrimary: Color(0xFF059669),
    darkPrimary: Color(0xFF34D399),
    lightCardBg: Color(0xFFF2FCF7),
    darkCardBg: Color(0xFF0D261F),
    lightHeaderBg: Color(0xFFD1FAE5),
    darkHeaderBg: Color(0xFF12382D),
    lightBorder: Color(0xFF6EE7B7),
    darkBorder: Color(0xFF1A614C),
  ),
  MacroVehicleColorTheme(
    name: 'magentaRose',
    lightPrimary: Color(0xFFDB2777),
    darkPrimary: Color(0xFFF472B6),
    lightCardBg: Color(0xFFFFF5FA),
    darkCardBg: Color(0xFF2E1222),
    lightHeaderBg: Color(0xFFFCE7F3),
    darkHeaderBg: Color(0xFF421A31),
    lightBorder: Color(0xFFF9A8D4),
    darkBorder: Color(0xFF7D2755),
  ),
  MacroVehicleColorTheme(
    name: 'indigo',
    lightPrimary: Color(0xFF4F46E5),
    darkPrimary: Color(0xFF818CF8),
    lightCardBg: Color(0xFFF4F6FF),
    darkCardBg: Color(0xFF161A38),
    lightHeaderBg: Color(0xFFE0E7FF),
    darkHeaderBg: Color(0xFF202652),
    lightBorder: Color(0xFFA5B4FC),
    darkBorder: Color(0xFF3C448C),
  ),
  MacroVehicleColorTheme(
    name: 'deepTeal',
    lightPrimary: Color(0xFF0D9488),
    darkPrimary: Color(0xFF2DD4BF),
    lightCardBg: Color(0xFFF2FCFB),
    darkCardBg: Color(0xFF0C2626),
    lightHeaderBg: Color(0xFFCCFBF1),
    darkHeaderBg: Color(0xFF113838),
    lightBorder: Color(0xFF5EEAD4),
    darkBorder: Color(0xFF1B5E5B),
  ),
  MacroVehicleColorTheme(
    name: 'amberGold',
    lightPrimary: Color(0xFFCA8A04),
    darkPrimary: Color(0xFFFACC15),
    lightCardBg: Color(0xFFFFFCF0),
    darkCardBg: Color(0xFF2B220B),
    lightHeaderBg: Color(0xFFFEF3C7),
    darkHeaderBg: Color(0xFF3D300F),
    lightBorder: Color(0xFFFCD34D),
    darkBorder: Color(0xFF755B16),
  ),
];

/// คืนชุดสีประจำรถแม็คโครแต่ละคัน — ยึดตามลำดับคัน ([displayIndex]) เพื่อให้คันในหน้าเดียวกันไม่ซ้ำสี
MacroVehicleColorTheme macroVehicleColorFor({
  required int displayIndex,
  String? vehicleName,
}) {
  if (displayIndex >= 1) {
    return kMacroVehicleColorPalette[
        (displayIndex - 1) % kMacroVehicleColorPalette.length];
  }
  final key = (vehicleName ?? '').trim();
  if (key.isEmpty) return kMacroVehicleColorPalette.first;
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  return kMacroVehicleColorPalette[hash % kMacroVehicleColorPalette.length];
}

/// การ์ดบันทึกรถแม็คโครรายคัน — แยกสีเฉพาะคันชัดเจน กะทัดรัด อ่านง่าย ไม่สับสนคัน
class MacroVehicleCard extends StatelessWidget {
  const MacroVehicleCard({
    super.key,
    required this.displayIndex,
    required this.vehicleName,
    required this.status,
    required this.isSaved,
    required this.hasData,
    required this.selectedDriverId,
    required this.drivers,
    required this.driverPickerExpanded,
    required this.workType,
    required this.quickPhrases,
    required this.selectedTags,
    required this.saving,
    required this.onToggleDriverPicker,
    required this.onSelectDriver,
    required this.onSelectWorkType,
    required this.onToggleWorkTag,
    required this.onRemoveCustomTag,
    required this.onAddCustomTag,
    required this.onSaveSingle,
    required this.onDeleteOrClear,
    this.colorTheme,
  });

  final int displayIndex;
  final String vehicleName;
  final MacroVehicleRowStatus status;
  final bool isSaved;
  final bool hasData;
  final String selectedDriverId;
  final List<MacroDriverOption> drivers;
  final bool driverPickerExpanded;
  final String workType;
  final List<String> quickPhrases;
  final List<String> selectedTags;
  final bool saving;
  final VoidCallback onToggleDriverPicker;
  final ValueChanged<String> onSelectDriver;
  final ValueChanged<String> onSelectWorkType;
  final ValueChanged<String> onToggleWorkTag;
  final ValueChanged<String> onRemoveCustomTag;
  final VoidCallback onAddCustomTag;
  final VoidCallback onSaveSingle;
  final VoidCallback onDeleteOrClear;

  /// กำหนดชุดสีเองได้ (ถ้าไม่ส่งจะเลือกอัตโนมัติตาม [displayIndex])
  final MacroVehicleColorTheme? colorTheme;

  MacroDriverOption? get _selectedDriver {
    final id = selectedDriverId.trim();
    if (id.isEmpty) return null;
    for (final d in drivers) {
      if (d.id == id) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final size = MediaQuery.sizeOf(context);
    final phonePortrait = size.shortestSide < 600 && size.height >= size.width;
    final palette = colorTheme ??
        macroVehicleColorFor(
          displayIndex: displayIndex,
          vehicleName: vehicleName,
        );
    final accent = palette.primary(isDark);
    final onAccent = palette.onPrimary(isDark);
    final danger = isDark ? const Color(0xFFF87171) : const Color(0xFFD14343);
    final customTags =
        selectedTags.where((t) => !quickPhrases.contains(t)).toList();
    final selectedDriver = _selectedDriver;
    final showDriverChips =
        driverPickerExpanded || selectedDriver == null || drivers.isEmpty;

    // คงแถบสีและโทนพื้นประจำคันไว้เสมอในทุกสถานะ เพื่อไม่ให้คนคีย์สับสนคัน
    final Color stripeColor = accent;
    final Color headerBg = palette.headerBg(isDark);
    final Color cardBg = status == MacroVehicleRowStatus.missingDriver
        ? (isDark ? const Color(0xFF332512) : const Color(0xFFFFFBF2))
        : palette.cardBg(isDark);
    final Color borderColor = switch (status) {
      MacroVehicleRowStatus.missingDriver =>
        isDark ? const Color(0xFFD97706) : const Color(0xFFF59E0B),
      MacroVehicleRowStatus.saved => accent.withValues(alpha: isDark ? 0.72 : 0.65),
      MacroVehicleRowStatus.readyToSave =>
        accent.withValues(alpha: isDark ? 0.78 : 0.7),
      MacroVehicleRowStatus.idle => palette.border(isDark),
    };

    Widget statusBadge() {
      return switch (status) {
        MacroVehicleRowStatus.saved => _MacroStatusPill(
            label: 'บันทึกแล้ว',
            icon: Icons.check_circle_rounded,
            fg: p.statusComplete,
            bg: isDark
                ? const Color(0xFF0E2F24)
                : const Color(0xFFE6F9F0),
            border: p.statusComplete.withValues(alpha: 0.45),
          ),
        MacroVehicleRowStatus.readyToSave => _MacroStatusPill(
            label: 'พร้อมบันทึก',
            icon: Icons.edit_note_rounded,
            fg: accent,
            bg: isDark ? p.card : Colors.white,
            border: accent.withValues(alpha: 0.55),
          ),
        MacroVehicleRowStatus.missingDriver => _MacroStatusPill(
            label: 'ขาดคนขับ',
            icon: Icons.person_off_outlined,
            fg: p.statusIncomplete,
            bg: p.statusIncomplete.withValues(alpha: isDark ? 0.22 : 0.14),
            border: p.statusIncomplete.withValues(alpha: 0.5),
          ),
        MacroVehicleRowStatus.idle => _MacroStatusPill(
            label: 'ไม่ได้ทำงาน',
            icon: Icons.pause_circle_outline_rounded,
            fg: p.inkMuted,
            bg: isDark ? p.card.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.85),
            border: palette.border(isDark),
          ),
      };
    }

    final driverBar = Material(
      color: isDark ? p.card : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: drivers.isNotEmpty ? onToggleDriverPicker : null,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: phonePortrait ? 10 : 12,
            vertical: phonePortrait ? 8 : 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: status == MacroVehicleRowStatus.missingDriver
                  ? p.statusIncomplete
                  : palette.border(isDark).withValues(alpha: 0.8),
              width: status == MacroVehicleRowStatus.missingDriver ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: selectedDriver != null
                      ? accent.withValues(alpha: isDark ? 0.24 : 0.14)
                      : p.chipSurface,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: selectedDriver != null
                    ? Text(
                        attendanceInitialsOf(selectedDriver.displayName),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: accent,
                          height: 1,
                        ),
                      )
                    : Icon(
                        Icons.person_outline_rounded,
                        size: 16,
                        color: p.inkMuted,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'คนขับรถ',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: p.inkMuted,
                        height: 1.1,
                      ),
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            selectedDriver?.displayName ?? 'เลือกคนขับด้านล่าง',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: phonePortrait ? 14 : 15,
                              fontWeight: FontWeight.w800,
                              color: selectedDriver != null
                                  ? p.ink
                                  : p.statusIncomplete,
                            ),
                          ),
                        ),
                        if (selectedDriver?.isDefault ?? false) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: Color(0xFFF59E0B),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (drivers.length > 1 || selectedDriver != null) ...[
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      driverPickerExpanded ? 'ซ่อน' : 'เปลี่ยน',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    Icon(
                      driverPickerExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: accent,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final shiftToggle = _ShiftSegmentedToggle(
      isHalfDay: workType == 'HalfDay',
      accent: accent,
      onAccent: onAccent,
      isDark: isDark,
      compact: phonePortrait,
      onChanged: (half) => onSelectWorkType(half ? 'HalfDay' : 'FullDay'),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.only(bottom: phonePortrait ? 10 : 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: status == MacroVehicleRowStatus.idle ? 1.25 : 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.14 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // แถบสีประจำคันด้านซ้าย 6px — ชัดเจนทุกสถานะ
              Container(
                key: ValueKey('macro_vehicle_stripe_$displayIndex'),
                width: 6,
                color: stripeColor,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // แถบหัวการ์ดโทนสีเฉพาะคัน
                    Container(
                      key: ValueKey('macro_vehicle_header_$displayIndex'),
                      padding: EdgeInsets.fromLTRB(
                        phonePortrait ? 12 : 14,
                        phonePortrait ? 10 : 12,
                        phonePortrait ? 10 : 12,
                        phonePortrait ? 10 : 12,
                      ),
                      decoration: BoxDecoration(
                        color: headerBg,
                        border: Border(
                          bottom: BorderSide(
                            color: palette.border(isDark).withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // ป้ายเลขคันสีสดเฉพาะคัน
                          Container(
                            key: ValueKey('macro_vehicle_badge_$displayIndex'),
                            width: phonePortrait ? 36 : 40,
                            height: phonePortrait ? 36 : 40,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(11),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.28),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$displayIndex',
                              style: TextStyle(
                                fontSize: phonePortrait ? 16 : 17.5,
                                fontWeight: FontWeight.w900,
                                color: onAccent,
                                height: 1,
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
                                    fontSize: phonePortrait ? 16.5 : 19,
                                    fontWeight: FontWeight.w800,
                                    color: p.ink,
                                    height: 1.18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          statusBadge(),
                          if (hasData) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip:
                                  isSaved ? 'ลบรายการที่บันทึก' : 'ล้างแถว',
                              onPressed: onDeleteOrClear,
                              visualDensity: VisualDensity.compact,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(36, 36),
                                backgroundColor: isSaved
                                    ? danger.withValues(
                                        alpha: isDark ? 0.22 : 0.12,
                                      )
                                    : (isDark
                                        ? p.card.withValues(alpha: 0.7)
                                        : Colors.white.withValues(alpha: 0.85)),
                              ),
                              icon: Icon(
                                isSaved
                                    ? Icons.delete_outline_rounded
                                    : Icons.close_rounded,
                                size: 18,
                                color: isSaved ? danger : p.inkMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(phonePortrait ? 12 : 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (phonePortrait) ...[
                            driverBar,
                            const SizedBox(height: 8),
                            shiftToggle,
                          ] else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(flex: 3, child: driverBar),
                                const SizedBox(width: 10),
                                Expanded(flex: 2, child: shiftToggle),
                              ],
                            ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            child: showDriverChips
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: drivers.isEmpty
                                        ? Text(
                                            'ยังไม่พบคนขับแม็คโคร / คนขับเริ่มต้นของรถคันนี้',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: danger,
                                            ),
                                          )
                                        : Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: [
                                              for (final d in drivers)
                                                _DriverChoiceChip(
                                                  option: d,
                                                  selected:
                                                      selectedDriverId == d.id,
                                                  accent: accent,
                                                  onAccent: onAccent,
                                                  isDark: isDark,
                                                  compact: phonePortrait,
                                                  onTap: () =>
                                                      onSelectDriver(d.id),
                                                ),
                                            ],
                                          ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text(
                                'งานวันนี้',
                                style: TextStyle(
                                  fontSize: phonePortrait ? 12.5 : 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: p.inkMuted,
                                ),
                              ),
                              if (selectedTags.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(
                                      alpha: isDark ? 0.24 : 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${selectedTags.length} งาน',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: accent,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'เลือกได้หลายงาน',
                                  textAlign: TextAlign.end,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: p.inkMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: phonePortrait ? 6 : 8,
                            runSpacing: phonePortrait ? 6 : 8,
                            children: [
                              for (final phrase in quickPhrases)
                                _WorkTagChip(
                                  label: phrase,
                                  selected: selectedTags.contains(phrase),
                                  orderNumber: selectedTags.length > 1
                                      ? selectedTags.indexOf(phrase) + 1
                                      : 0,
                                  accent: accent,
                                  onAccent: onAccent,
                                  isDark: isDark,
                                  compact: phonePortrait,
                                  onTap: () => onToggleWorkTag(phrase),
                                ),
                              for (final tag in customTags)
                                _WorkTagChip(
                                  label: tag,
                                  selected: true,
                                  orderNumber: selectedTags.length > 1
                                      ? selectedTags.indexOf(tag) + 1
                                      : 0,
                                  accent: accent,
                                  onAccent: onAccent,
                                  isDark: isDark,
                                  compact: phonePortrait,
                                  onTap: () => onToggleWorkTag(tag),
                                  onRemove: () => onRemoveCustomTag(tag),
                                ),
                              _AddWorkTagChip(
                                accent: accent,
                                isDark: isDark,
                                compact: phonePortrait,
                                onTap: onAddCustomTag,
                              ),
                            ],
                          ),
                          if (selectedTags.length > 1) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(
                                  alpha: isDark ? 0.18 : 0.1,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.route_rounded,
                                    size: 15,
                                    color: accent,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'ลำดับงาน: ${selectedTags.join(' → ')}',
                                      style: TextStyle(
                                        fontSize: phonePortrait ? 12.5 : 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: accent,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (status == MacroVehicleRowStatus.saved) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: saving ? null : onSaveSingle,
                              icon: Icon(
                                Icons.sync_rounded,
                                size: phonePortrait ? 17 : 19,
                              ),
                              label: Text(
                                'อัปเดตคันนี้',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: phonePortrait ? 14 : 15,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size.fromHeight(
                                  phonePortrait ? 42 : 46,
                                ),
                                foregroundColor: p.statusComplete,
                                side: BorderSide(
                                  color:
                                      p.statusComplete.withValues(alpha: 0.55),
                                  width: 1.3,
                                ),
                                backgroundColor: isDark ? p.card : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(11),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShiftSegmentedToggle extends StatelessWidget {
  const _ShiftSegmentedToggle({
    required this.isHalfDay,
    required this.accent,
    required this.onAccent,
    required this.isDark,
    required this.compact,
    required this.onChanged,
  });

  final bool isHalfDay;
  final Color accent;
  final Color onAccent;
  final bool isDark;
  final bool compact;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    Widget seg({
      required String label,
      required IconData icon,
      required bool active,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Material(
          color: active ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 8,
                vertical: compact ? 8 : 10,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: compact ? 15 : 17,
                    color: active ? onAccent : p.inkMuted,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 13 : 14,
                        fontWeight: FontWeight.w800,
                        color: active ? onAccent : p.inkSubtle,
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

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? p.card : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          seg(
            label: 'เต็มวัน',
            icon: Icons.wb_sunny_rounded,
            active: !isHalfDay,
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: 3),
          seg(
            label: 'ครึ่งวัน',
            icon: Icons.brightness_4_rounded,
            active: isHalfDay,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _DriverChoiceChip extends StatelessWidget {
  const _DriverChoiceChip({
    required this.option,
    required this.selected,
    required this.accent,
    required this.onAccent,
    required this.isDark,
    required this.compact,
    required this.onTap,
  });

  final MacroDriverOption option;
  final bool selected;
  final Color accent;
  final Color onAccent;
  final bool isDark;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    return Material(
      color: selected
          ? accent.withValues(alpha: isDark ? 0.24 : 0.13)
          : (isDark ? p.card : Colors.white),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            compact ? 6 : 8,
            compact ? 6 : 7,
            compact ? 10 : 12,
            compact ? 6 : 7,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? accent : p.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected
                      ? accent
                      : accent.withValues(alpha: isDark ? 0.18 : 0.1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 13.5,
                        color: onAccent,
                      )
                    : Text(
                        attendanceInitialsOf(option.displayName),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: accent,
                          height: 1,
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              if (option.isDefault) ...[
                const Icon(
                  Icons.star_rounded,
                  size: 14,
                  color: Color(0xFFF59E0B),
                ),
                const SizedBox(width: 2),
              ],
              Text(
                option.displayName,
                style: TextStyle(
                  fontSize: compact ? 13.5 : 14.5,
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkTagChip extends StatelessWidget {
  const _WorkTagChip({
    required this.label,
    required this.selected,
    required this.orderNumber,
    required this.accent,
    required this.onAccent,
    required this.isDark,
    required this.compact,
    required this.onTap,
    this.onRemove,
  });

  final String label;
  final bool selected;
  final int orderNumber;
  final Color accent;
  final Color onAccent;
  final bool isDark;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final danger = isDark ? const Color(0xFFF87171) : const Color(0xFFD14343);
    return Material(
      color: selected
          ? accent.withValues(alpha: isDark ? 0.24 : 0.13)
          : (isDark ? p.card : Colors.white),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? accent : p.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected && orderNumber > 0) ...[
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$orderNumber',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: onAccent,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
              ] else if (selected) ...[
                Icon(Icons.check_circle_rounded, size: 16, color: accent),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: compact ? 13.5 : 15,
                  fontWeight: FontWeight.w700,
                  color: selected ? (isDark ? p.ink : accent) : p.inkSubtle,
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onRemove,
                  child: Icon(Icons.close_rounded, size: 16, color: danger),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AddWorkTagChip extends StatelessWidget {
  const _AddWorkTagChip({
    required this.accent,
    required this.isDark,
    required this.compact,
    required this.onTap,
  });

  final Color accent;
  final bool isDark;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    return Material(
      color: isDark ? p.chipSurface : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: p.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16, color: accent),
              const SizedBox(width: 4),
              Text(
                'งานอื่น',
                style: TextStyle(
                  fontSize: compact ? 13.5 : 14.5,
                  fontWeight: FontWeight.w700,
                  color: p.inkSubtle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacroStatusPill extends StatelessWidget {
  const _MacroStatusPill({
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
