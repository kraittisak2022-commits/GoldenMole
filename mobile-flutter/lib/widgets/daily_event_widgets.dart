import 'package:flutter/material.dart';

import '../models/app_transaction.dart';
import '../theme/daily_palette.dart';
import '../utils/daily_event_summary.dart';
import 'app_theme_scope.dart';

/// แถบสรุปภาพรวมเหตุการณ์ประจำวันด้านบน — วันที่ + KPI (ทั้งหมด / ด่วน / ปัญหา·เตือน)
class DailyEventOverviewHeader extends StatelessWidget {
  const DailyEventOverviewHeader({
    super.key,
    required this.dateLabel,
    required this.overview,
  });

  final String dateLabel;
  final DailyEventDayOverview overview;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final orange = isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
    final urgentRed =
        isDark ? const Color(0xFFF87171) : const Color(0xFFC62828);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? p.chipSurface : const Color(0xFFFFFAF2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: orange.withValues(alpha: isDark ? 0.35 : 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: orange.withValues(alpha: isDark ? 0.2 : 0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.event_note_rounded,
                  size: 20,
                  color: orange,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'บันทึกเหตุการณ์',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: p.ink,
                        height: 1.15,
                      ),
                    ),
                    Text(
                      'วันที่ $dateLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: p.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (overview.totalCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: orange.withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'วันนี้ ${overview.totalCount}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: orange,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (overview.urgentCount > 0 || overview.issueCount > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (overview.urgentCount > 0)
                  _HeaderStatPill(
                    icon: Icons.priority_high_rounded,
                    label: 'ด่วน ${overview.urgentCount}',
                    color: urgentRed,
                    isDark: isDark,
                  ),
                if (overview.issueCount > 0)
                  _HeaderStatPill(
                    icon: Icons.warning_amber_rounded,
                    label: 'ปัญหา/เตือน ${overview.issueCount}',
                    color: orange,
                    isDark: isDark,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderStatPill extends StatelessWidget {
  const _HeaderStatPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13.5, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// แถบแจ้งเตือนเมื่ออยู่ในโหมดแก้ไขเหตุการณ์เดิม พร้อมปุ่มยกเลิกกลับโหมดเพิ่มใหม่
class DailyEventEditingBanner extends StatelessWidget {
  const DailyEventEditingBanner({
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
    final spec = dailyEventTypeSpecOf(entry.eventType);
    final desc = stripDailyEventRecorderSuffix(entry.description);
    final time = dailyEventDisplayTime(entry);
    final preview = [
      spec.shortLabel,
      if (time.isNotEmpty) time,
      if (desc.isNotEmpty) desc,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162C44) : const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.55 : 0.45),
          width: 1.3,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_note_rounded, size: 21, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'กำลังแก้ไขเหตุการณ์เดิม',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
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
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// กริด 3×2 เลือกประเภทเหตุการณ์พร้อมไอคอนและสีสื่อความหมาย
class DailyEventTypeGrid extends StatelessWidget {
  const DailyEventTypeGrid({
    super.key,
    required this.selectedType,
    required this.onSelect,
    this.compact = false,
  });

  final String selectedType;
  final ValueChanged<String> onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final normalized = normalizeDailyEventType(selectedType);
    final gap = compact ? 6.0 : 8.0;

    Widget tile(DailyEventTypeSpec spec) {
      final selected = normalized == spec.code;
      final accent = spec.accent(isDark: isDark);
      return Material(
        color: selected
            ? accent.withValues(alpha: isDark ? 0.24 : 0.13)
            : (isDark ? p.chipSurface : const Color(0xFFF7F9FC)),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onSelect(spec.code),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 10,
              vertical: compact ? 9 : 11,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? accent : p.hairline,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  spec.icon,
                  size: compact ? 20 : 22,
                  color: selected ? accent : p.inkMuted,
                ),
                const SizedBox(height: 4),
                Text(
                  compact ? spec.shortLabel : spec.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: compact ? 12 : 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    color: selected ? accent : p.inkSubtle,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(child: tile(kDailyEventTypes[i])),
            ],
          ],
        ),
        SizedBox(height: gap),
        Row(
          children: [
            for (var i = 3; i < 6; i++) ...[
              if (i > 3) SizedBox(width: gap),
              Expanded(child: tile(kDailyEventTypes[i])),
            ],
          ],
        ),
      ],
    );
  }
}

/// แถบเลือกความสำคัญ (ปกติ | ด่วน) คู่กับเวลาเกิดเหตุแบบแตะเลือกได้
class DailyEventPriorityAndTimeBar extends StatelessWidget {
  const DailyEventPriorityAndTimeBar({
    super.key,
    required this.priority,
    required this.timeText,
    required this.onPriorityChanged,
    required this.onPickTime,
    required this.onClearTime,
    this.compact = false,
  });

  final String priority;
  final String timeText;
  final ValueChanged<String> onPriorityChanged;
  final VoidCallback onPickTime;
  final VoidCallback onClearTime;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final urgent = isDailyEventUrgent(priority);
    final normalColor =
        isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0);
    final urgentColor =
        isDark ? const Color(0xFFF87171) : const Color(0xFFC62828);
    final cleanTime = timeText.trim();
    final hasTime = cleanTime.isNotEmpty;

    Widget priBtn({
      required String value,
      required String label,
      required IconData icon,
      required bool selected,
      required Color activeColor,
    }) {
      return Expanded(
        child: Material(
          color: selected
              ? activeColor.withValues(alpha: isDark ? 0.25 : 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onPriorityChanged(value),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: 6,
                vertical: compact ? 8 : 10,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: selected
                    ? Border.all(color: activeColor, width: 1.4)
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: compact ? 15 : 17,
                    color: selected ? activeColor : p.inkMuted,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 12.5 : 13.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? activeColor : p.inkMuted,
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

    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isDark ? p.chipSurface : const Color(0xFFF4F7FB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                priBtn(
                  value: 'normal',
                  label: 'ปกติ',
                  icon: Icons.check_circle_outline_rounded,
                  selected: !urgent,
                  activeColor: normalColor,
                ),
                const SizedBox(width: 4),
                priBtn(
                  value: 'urgent',
                  label: 'ด่วน',
                  icon: Icons.priority_high_rounded,
                  selected: urgent,
                  activeColor: urgentColor,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: Material(
            color: hasTime
                ? p.brand.withValues(alpha: isDark ? 0.2 : 0.1)
                : (isDark ? p.chipSurface : const Color(0xFFF4F7FB)),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onPickTime,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: compact ? 8 : 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasTime ? p.brand : p.hairline,
                    width: hasTime ? 1.3 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: compact ? 16 : 18,
                      color: hasTime ? p.brand : p.inkMuted,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        hasTime ? cleanTime : 'เวลา (ไม่บังคับ)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 12 : 13,
                          fontWeight: FontWeight.w800,
                          color: hasTime ? p.brand : p.inkMuted,
                        ),
                      ),
                    ),
                    if (hasTime)
                      Tooltip(
                        message: 'ล้างเวลาเกิดเหตุ',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: onClearTime,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: p.inkMuted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// แถบเทมเพลตด่วนหน้างานพร้อมจุดสีตามประเภทเหตุการณ์
class DailyEventQuickTemplatesStrip extends StatelessWidget {
  const DailyEventQuickTemplatesStrip({
    super.key,
    required this.onSelectTemplate,
    this.compact = false,
  });

  final ValueChanged<DailyEventQuickTemplate> onSelectTemplate;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.bolt_rounded, size: 15, color: p.inkMuted),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'เทมเพลตด่วน (แตะเพื่อเติมข้อความอัตโนมัติ)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11.5 : 12.5,
                  fontWeight: FontWeight.w700,
                  color: p.inkMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tmpl in kDailyEventQuickTemplates)
              _QuickTemplateChip(
                template: tmpl,
                compact: compact,
                isDark: isDark,
                palette: p,
                onTap: () => onSelectTemplate(tmpl),
              ),
          ],
        ),
      ],
    );
  }
}

class _QuickTemplateChip extends StatelessWidget {
  const _QuickTemplateChip({
    required this.template,
    required this.compact,
    required this.isDark,
    required this.palette,
    required this.onTap,
  });

  final DailyEventQuickTemplate template;
  final bool compact;
  final bool isDark;
  final DailyColors palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spec = dailyEventTypeSpecOf(template.defaultType);
    final accent = spec.accent(isDark: isDark);
    return Material(
      color: isDark ? palette.chipSurface : const Color(0xFFF8FAFD),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 9 : 11,
            vertical: compact ? 6 : 7,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.35 : 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                template.text,
                style: TextStyle(
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// รายการเหตุการณ์ที่บันทึกแล้วของวันนี้ พร้อมตัวกรองด่วน แก้ไข และลบรายรายการ
class DailyEventDayLogSection extends StatelessWidget {
  const DailyEventDayLogSection({
    super.key,
    required this.entries,
    required this.filter,
    required this.onFilterChanged,
    required this.onEdit,
    required this.onDelete,
    this.editingTxId,
  });

  final List<AppTransaction> entries;
  final DailyEventFilter filter;
  final String? editingTxId;
  final ValueChanged<DailyEventFilter> onFilterChanged;
  final ValueChanged<AppTransaction> onEdit;
  final ValueChanged<AppTransaction> onDelete;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        (AppThemeScope.maybeOf(context)?.isDark ?? false);
    final orange = isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
    final overview = summarizeDailyEvents(entries);
    final visibleEntries = entries
        .where((e) => matchesDailyEventFilter(e, filter))
        .toList();
    final showFilters =
        entries.length >= 2 &&
        (overview.urgentCount > 0 || overview.issueCount > 0) ||
        filter != DailyEventFilter.all;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.timeline_rounded, size: 19, color: orange),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'เหตุการณ์วันนี้',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: p.ink,
                ),
              ),
            ),
            if (entries.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: orange.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${entries.length} รายการ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: orange,
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
                Icon(Icons.event_available_outlined, size: 26, color: p.inkMuted),
                const SizedBox(height: 6),
                Text(
                  'ยังไม่มีเหตุการณ์ของวันนี้',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: p.inkSubtle,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'เลือกประเภท แตะเทมเพลตด่วน หรือพิมพ์รายละเอียดด้านบนเพื่อบันทึก',
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
          if (showFilters) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _EventFilterPill(
                    label: 'ทั้งหมด (${overview.totalCount})',
                    selected: filter == DailyEventFilter.all,
                    accent: orange,
                    isDark: isDark,
                    palette: p,
                    onTap: () => onFilterChanged(DailyEventFilter.all),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _EventFilterPill(
                    label: 'ด่วน (${overview.urgentCount})',
                    selected: filter == DailyEventFilter.urgent,
                    accent: isDark
                        ? const Color(0xFFF87171)
                        : const Color(0xFFC62828),
                    isDark: isDark,
                    palette: p,
                    onTap: () => onFilterChanged(DailyEventFilter.urgent),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _EventFilterPill(
                    label: 'ปัญหา/เตือน (${overview.issueCount})',
                    selected: filter == DailyEventFilter.issues,
                    accent: orange,
                    isDark: isDark,
                    palette: p,
                    onTap: () => onFilterChanged(DailyEventFilter.issues),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (visibleEntries.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? p.chipSurface : const Color(0xFFF8FAFD),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'ไม่พบเหตุการณ์ในตัวกรองนี้',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: p.inkMuted,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => onFilterChanged(DailyEventFilter.all),
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
                  _DailyEventLogCard(
                    index: i + 1,
                    entry: visibleEntries[i],
                    isEditing:
                        editingTxId != null &&
                        editingTxId!.isNotEmpty &&
                        editingTxId == visibleEntries[i].id,
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

class _EventFilterPill extends StatelessWidget {
  const _EventFilterPill({
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
          ? accent.withValues(alpha: isDark ? 0.22 : 0.13)
          : (isDark ? palette.chipSurface : const Color(0xFFF4F7FB)),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? accent : palette.hairline,
              width: selected ? 1.3 : 1,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: selected ? accent : palette.inkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyEventLogCard extends StatelessWidget {
  const _DailyEventLogCard({
    required this.index,
    required this.entry,
    required this.isEditing,
    required this.isDark,
    required this.palette,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final AppTransaction entry;
  final bool isEditing;
  final bool isDark;
  final DailyColors palette;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final spec = dailyEventTypeSpecOf(entry.eventType);
    final urgent = isDailyEventUrgent(entry.eventPriority);
    final typeAccent = spec.accent(isDark: isDark);
    final urgentRed =
        isDark ? const Color(0xFFF87171) : const Color(0xFFC62828);
    final editAccent =
        isDark ? const Color(0xFF60A5FA) : const Color(0xFF1565C0);
    final stripeColor = isEditing
        ? editAccent
        : (urgent ? urgentRed : typeAccent);
    final desc = stripDailyEventRecorderSuffix(entry.description);
    final recorder = extractDailyEventRecorderName(entry.description);
    final timeLabel = dailyEventDisplayTime(entry);
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
                  : (urgent
                      ? urgentRed.withValues(alpha: isDark ? 0.5 : 0.35)
                      : palette.hairline),
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
                      padding: const EdgeInsets.fromLTRB(11, 10, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: typeAccent.withValues(
                                    alpha: isDark ? 0.2 : 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      spec.icon,
                                      size: 13.5,
                                      color: typeAccent,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      spec.shortLabel,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: typeAccent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (urgent) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: urgentRed.withValues(
                                      alpha: isDark ? 0.24 : 0.13,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.priority_high_rounded,
                                        size: 12.5,
                                        color: urgentRed,
                                      ),
                                      Text(
                                        'ด่วน',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: urgentRed,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const Spacer(),
                              if (timeLabel.isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 13,
                                      color: palette.inkMuted,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      timeLabel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: palette.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Text(
                            desc.isEmpty ? '(ไม่มีรายละเอียด)' : desc,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: palette.ink,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: recorder != null
                                    ? Text(
                                        'ผู้กรอก: $recorder',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: palette.inkMuted,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
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
                                  tooltip: 'แก้ไขเหตุการณ์ $tooltipKey',
                                  onPressed: onEdit,
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 38,
                                    minHeight: 38,
                                  ),
                                  icon: Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: palette.inkSubtle,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'ลบเหตุการณ์ $tooltipKey',
                                  onPressed: onDelete,
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 38,
                                    minHeight: 38,
                                  ),
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: urgentRed,
                                  ),
                                ),
                              ],
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
        ),
      ),
    );
  }
}
