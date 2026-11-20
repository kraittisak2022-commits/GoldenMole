import 'package:flutter/material.dart';

import '../models/app_transaction.dart';
import '../theme/daily_palette.dart';
import '../utils/fuel_stock.dart';
import 'app_theme_scope.dart';

/// วัตถุประสงค์มาตรฐานที่ให้เลือกในหน้า «เบิกน้ำมัน»
const List<FuelWithdrawPurpose> kFuelWithdrawSelectablePurposes = [
  FuelWithdrawPurpose.machine,
  FuelWithdrawPurpose.generator,
  FuelWithdrawPurpose.mayor,
  FuelWithdrawPurpose.car,
  FuelWithdrawPurpose.tenWheelerMayor,
];

/// ชื่อแสดงผลของแต่ละวัตถุประสงค์ในหน้า «เบิกน้ำมัน»
String fuelWithdrawPurposeDisplayLabel(FuelWithdrawPurpose purpose) {
  if (purpose == FuelWithdrawPurpose.car) {
    return fuelCarFillVehicleLabelOf(FuelCarFillVehicle.taplien);
  }
  return fuelWithdrawPurposeLabelOf(purpose);
}

/// ไอคอนประจำวัตถุประสงค์
IconData fuelWithdrawPurposeIcon(FuelWithdrawPurpose purpose) {
  switch (purpose) {
    case FuelWithdrawPurpose.machine:
      return Icons.precision_manufacturing_outlined;
    case FuelWithdrawPurpose.generator:
      return Icons.bolt_outlined;
    case FuelWithdrawPurpose.mayor:
      return Icons.account_balance_outlined;
    case FuelWithdrawPurpose.car:
      return Icons.airport_shuttle_outlined;
    case FuelWithdrawPurpose.tenWheelerMayor:
      return Icons.local_shipping_outlined;
    case FuelWithdrawPurpose.other:
      return Icons.local_gas_station_outlined;
  }
}

/// สีเน้นประจำวัตถุประสงค์ (ปรับโทนให้ชัดทั้ง Light/Dark)
Color fuelWithdrawPurposeAccent(
  FuelWithdrawPurpose purpose, {
  required bool isDark,
}) {
  switch (purpose) {
    case FuelWithdrawPurpose.machine:
      return isDark ? const Color(0xFFFFB74D) : const Color(0xFFEF6C00);
    case FuelWithdrawPurpose.generator:
      return isDark ? const Color(0xFF4FC3F7) : const Color(0xFF0288D1);
    case FuelWithdrawPurpose.mayor:
      return isDark ? const Color(0xFF4DB6AC) : const Color(0xFF00897B);
    case FuelWithdrawPurpose.car:
      return isDark ? const Color(0xFFCE93D8) : const Color(0xFF6A1B9A);
    case FuelWithdrawPurpose.tenWheelerMayor:
      return isDark ? const Color(0xFF9FA8DA) : const Color(0xFF3949AB);
    case FuelWithdrawPurpose.other:
      return isDark ? const Color(0xFFB0BEC5) : const Color(0xFF546E7A);
  }
}

String fuelWithdrawTankFlowLabel(FuelWithdrawPurpose purpose) =>
    purpose == FuelWithdrawPurpose.machine
        ? 'โอน ถังหลัก → ถังสำรอง'
        : 'หักจากถังหลัก';

/// ชุดเลือกวัตถุประสงค์เบิกน้ำมัน — แสดงจำนวนรอบและลิตรสะสมของแต่ละหมวดในวันนี้
class FuelWithdrawPurposeSelector extends StatelessWidget {
  const FuelWithdrawPurposeSelector({
    super.key,
    required this.selectedPurpose,
    required this.summariesByPurpose,
    required this.onSelect,
    this.compact = false,
  });

  final FuelWithdrawPurpose selectedPurpose;
  final Map<FuelWithdrawPurpose, FuelWithdrawDaySummary> summariesByPurpose;
  final ValueChanged<FuelWithdrawPurpose> onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < kFuelWithdrawSelectablePurposes.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _PurposeTile(
            purpose: kFuelWithdrawSelectablePurposes[i],
            selected: selectedPurpose == kFuelWithdrawSelectablePurposes[i],
            summary:
                summariesByPurpose[kFuelWithdrawSelectablePurposes[i]] ??
                const FuelWithdrawDaySummary(),
            compact: compact,
            isDark: isDark,
            palette: p,
            onTap: () => onSelect(kFuelWithdrawSelectablePurposes[i]),
          ),
        ],
      ],
    );
  }
}

class _PurposeTile extends StatelessWidget {
  const _PurposeTile({
    required this.purpose,
    required this.selected,
    required this.summary,
    required this.compact,
    required this.isDark,
    required this.palette,
    required this.onTap,
  });

  final FuelWithdrawPurpose purpose;
  final bool selected;
  final FuelWithdrawDaySummary summary;
  final bool compact;
  final bool isDark;
  final DailyColors palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = fuelWithdrawPurposeAccent(purpose, isDark: isDark);
    final orangeAccent = const Color(0xFFEF6C00);
    final activeColor = isDark ? const Color(0xFFFFB74D) : orangeAccent;
    final label = fuelWithdrawPurposeDisplayLabel(purpose);
    final summaryText = formatFuelWithdrawPurposeSummary(summary);
    final bg = selected
        ? (isDark ? const Color(0xFF3A2A14) : const Color(0xFFFFF3E0))
        : (isDark ? palette.chipSurface : const Color(0xFFF8FAFD));
    final borderColor = selected
        ? orangeAccent
        : (summary.hasEntries
            ? accent.withValues(alpha: isDark ? 0.45 : 0.35)
            : (isDark ? palette.hairline : const Color(0xFFE1E8F0)));

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 11 : 13,
            vertical: compact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 34 : 38,
                height: compact ? 34 : 38,
                decoration: BoxDecoration(
                  color: (selected ? activeColor : accent).withValues(
                    alpha: isDark ? 0.2 : 0.12,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  fuelWithdrawPurposeIcon(purpose),
                  size: compact ? 18 : 20,
                  color: selected ? activeColor : accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 14.5 : 15.5,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? (isDark
                                ? const Color(0xFFFFCC80)
                                : const Color(0xFF8A4B00))
                            : palette.ink,
                      ),
                    ),
                    if (summaryText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        summaryText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 12 : 13,
                          fontWeight: FontWeight.w700,
                          color: selected ? activeColor : accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (summary.count >= 2) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (selected ? activeColor : accent).withValues(
                      alpha: isDark ? 0.22 : 0.12,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${summary.count} รอบ',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? activeColor : accent,
                    ),
                  ),
                ),
              ],
              if (selected) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: activeColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// แถบแจ้งเตือนเมื่อกำลังแก้ไขรายการเบิกเดิม พร้อมปุ่มยกเลิกกลับโหมดเพิ่มรอบใหม่
class FuelWithdrawEditingBanner extends StatelessWidget {
  const FuelWithdrawEditingBanner({
    super.key,
    required this.entry,
    required this.onCancel,
  });

  final AppTransaction entry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final accent = isDark ? const Color(0xFF60A5FA) : const Color(0xFF1565C0);
    final purpose = fuelWithdrawPurposeOfTx(entry);
    final purposeLabel = fuelWithdrawPurposeDisplayLabel(purpose);
    final time = fuelWithdrawTimeLabel(entry);
    final liters = formatFuelLiters(fuelTxLiters(entry));
    final detailParts = <String>[
      purposeLabel,
      if (time.isNotEmpty) time,
      '$liters ลิตร',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162C44) : const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.55 : 0.45),
          width: 1.3,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_note_rounded, size: 22, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'กำลังแก้ไขรายการเดิม',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                Text(
                  detailParts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: p.inkSubtle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: accent,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'ยกเลิก',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// รายการเบิกน้ำมันทั้งหมดของวันนี้ (เรียงตามเวลาเช้า → บ่าย) พร้อมแก้ไขและลบทีละรายการ
class FuelWithdrawDayLogSection extends StatelessWidget {
  const FuelWithdrawDayLogSection({
    super.key,
    required this.entries,
    required this.selectedPurpose,
    required this.showAllPurposes,
    required this.onToggleShowAll,
    required this.onEdit,
    required this.onDelete,
    this.editingTxId,
    this.customDetailResolver,
  });

  final List<AppTransaction> entries;
  final FuelWithdrawPurpose selectedPurpose;
  final bool showAllPurposes;
  final String? editingTxId;
  final ValueChanged<bool> onToggleShowAll;
  final ValueChanged<AppTransaction> onEdit;
  final ValueChanged<AppTransaction> onDelete;
  final String? Function(AppTransaction tx)? customDetailResolver;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final orange = isDark ? const Color(0xFFFFB74D) : const Color(0xFFEF6C00);

    var totalLiters = 0.0;
    final distinctPurposes = <FuelWithdrawPurpose>{};
    var selectedPurposeCount = 0;
    for (final e in entries) {
      totalLiters += fuelTxLiters(e);
      final purpose = fuelWithdrawPurposeOfTx(e);
      distinctPurposes.add(purpose);
      if (purpose == selectedPurpose) selectedPurposeCount++;
    }

    final visibleEntries = showAllPurposes
        ? entries
        : entries
            .where((e) => fuelWithdrawPurposeOfTx(e) == selectedPurpose)
            .toList();
    final showFilterBar = distinctPurposes.length > 1 || !showAllPurposes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, size: 19, color: orange),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'รายการเบิกวันนี้',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: p.ink,
                ),
              ),
            ),
            if (entries.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: orange.withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${entries.length} รายการ · รวม ${formatFuelLiters(totalLiters)} ลิตร',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: orange,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (entries.isEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: isDark ? p.chipSurface : const Color(0xFFF8FAFD),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.local_gas_station_outlined,
                  size: 26,
                  color: p.inkMuted,
                ),
                const SizedBox(height: 6),
                Text(
                  'ยังไม่มีรายการเบิกน้ำมันของวันนี้',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: p.inkSubtle,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'กรอกจำนวนลิตรและเวลาด้านบนเพื่อเพิ่มรายการแรก สามารถเพิ่มได้หลายรอบต่อวัน',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: p.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          if (showFilterBar) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _FilterChipButton(
                    label: 'ทั้งหมด (${entries.length})',
                    selected: showAllPurposes,
                    accent: orange,
                    isDark: isDark,
                    palette: p,
                    onTap: () => onToggleShowAll(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FilterChipButton(
                    label: 'เฉพาะที่เลือก ($selectedPurposeCount)',
                    selected: !showAllPurposes,
                    accent: orange,
                    isDark: isDark,
                    palette: p,
                    onTap: () => onToggleShowAll(false),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (visibleEntries.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? p.chipSurface : const Color(0xFFF8FAFD),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'ยังไม่มีรายการในหมวดนี้',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: p.inkMuted,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => onToggleShowAll(true),
                    child: Text(
                      'แสดงทั้งหมด',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: orange,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < visibleEntries.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _WithdrawLogEntryCard(
                    index: i + 1,
                    entry: visibleEntries[i],
                    isEditing:
                        editingTxId != null &&
                        editingTxId!.isNotEmpty &&
                        editingTxId == visibleEntries[i].id,
                    customDetail: customDetailResolver?.call(visibleEntries[i]),
                    isDark: isDark,
                    palette: p,
                    onEdit: () => onEdit(visibleEntries[i]),
                    onDelete: () => onDelete(visibleEntries[i]),
                  ),
                ],
              ],
            ),
        ],
      ],
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.accent,
    required this.isDark,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final bool isDark;
  final DailyColors palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? accent.withValues(alpha: isDark ? 0.22 : 0.14)
          : (isDark ? palette.chipSurface : const Color(0xFFF4F7FB)),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? accent : palette.hairline,
              width: selected ? 1.3 : 1,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: selected ? accent : palette.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _WithdrawLogEntryCard extends StatelessWidget {
  const _WithdrawLogEntryCard({
    required this.index,
    required this.entry,
    required this.isEditing,
    required this.isDark,
    required this.palette,
    required this.onEdit,
    required this.onDelete,
    this.customDetail,
  });

  final int index;
  final AppTransaction entry;
  final bool isEditing;
  final String? customDetail;
  final bool isDark;
  final DailyColors palette;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final purpose = fuelWithdrawPurposeOfTx(entry);
    final accent = fuelWithdrawPurposeAccent(purpose, isDark: isDark);
    final editAccent =
        isDark ? const Color(0xFF60A5FA) : const Color(0xFF1565C0);
    final dangerColor =
        isDark ? const Color(0xFFF87171) : const Color(0xFFD14343);
    final stripeColor = isEditing ? editAccent : accent;
    final timeLabel = fuelWithdrawTimeLabel(entry);
    final litersLabel = '${formatFuelLiters(fuelTxLiters(entry))} ลิตร';
    final detail = customDetail?.trim() ?? '';
    final title = detail.isNotEmpty
        ? '${fuelWithdrawPurposeDisplayLabel(purpose)} · $detail'
        : fuelWithdrawPurposeDisplayLabel(purpose);
    final tooltipKey = timeLabel.isNotEmpty ? timeLabel : '#$index';

    return Material(
      color: isEditing
          ? (isDark ? const Color(0xFF162C44) : const Color(0xFFEAF3FF))
          : (isDark ? palette.chipSurface : const Color(0xFFFAFCFF)),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: isEditing ? null : onEdit,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isEditing
                  ? editAccent
                  : (isDark ? palette.hairline : const Color(0xFFE1E8F0)),
              width: isEditing ? 1.5 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4.5, color: stripeColor),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
                      child: Row(
                        children: [
                          Container(
                            constraints: const BoxConstraints(minWidth: 56),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: stripeColor.withValues(
                                alpha: isDark ? 0.18 : 0.11,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '#$index',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: palette.inkMuted,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  timeLabel.isNotEmpty ? timeLabel : '--:--',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: stripeColor,
                                    height: 1.15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: palette.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      litersLabel,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: stripeColor,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '· ${fuelWithdrawTankFlowLabel(purpose)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: palette.inkMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          if (isEditing)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: editAccent.withValues(
                                  alpha: isDark ? 0.22 : 0.14,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'กำลังแก้ไข',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: editAccent,
                                ),
                              ),
                            )
                          else ...[
                            IconButton(
                              tooltip: 'แก้ไขรายการ $tooltipKey',
                              onPressed: onEdit,
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 38,
                                minHeight: 38,
                              ),
                              icon: Icon(
                                Icons.edit_outlined,
                                size: 19,
                                color: palette.inkSubtle,
                              ),
                            ),
                            IconButton(
                              tooltip: 'ลบรายการ $tooltipKey',
                              onPressed: onDelete,
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 38,
                                minHeight: 38,
                              ),
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 19,
                                color: dangerColor,
                              ),
                            ),
                          ],
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
