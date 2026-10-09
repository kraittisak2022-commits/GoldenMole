import 'package:flutter/material.dart';

import '../logic/calendar.dart';
import '../logic/format.dart';
import '../theme/app_theme.dart';

/// Month calendar in Thai with Buddhist-era years: a bottom sheet on phones, a dialog on wider
/// screens. [counts] are orders per ISO day, known only for the month of [value].
Future<String?> showCalendarPicker(
  BuildContext context, {
  required String value,
  required String today,
  Map<String, int>? counts,
}) {
  Widget panel(BuildContext ctx) =>
      CalendarPanel(value: value, today: today, counts: counts, onSelect: (iso) => Navigator.of(ctx).pop(iso));
  if (MediaQuery.sizeOf(context).width < 640) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: panel(ctx))),
    );
  }
  return showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface,
      child: SizedBox(width: 352, child: Padding(padding: const EdgeInsets.all(16), child: panel(ctx))),
    ),
  );
}

class CalendarPanel extends StatefulWidget {
  const CalendarPanel({super.key, required this.value, required this.today, this.counts, required this.onSelect});
  final String value;
  final String today;
  final Map<String, int>? counts;
  final ValueChanged<String> onSelect;

  @override
  State<CalendarPanel> createState() => _CalendarPanelState();
}

class _CalendarPanelState extends State<CalendarPanel> {
  late YearMonth _view = yearMonthOf(widget.value);

  void _step(int by) => setState(() => _view = shiftMonth(_view, by));

  @override
  Widget build(BuildContext context) {
    final counts = widget.counts;
    final countsShown = counts != null && sameMonth(widget.value, _view);
    final grid = monthGrid(_view);
    final inSheet = MediaQuery.sizeOf(context).width < 640;

    Widget navButton(IconData icon, String tip, int by) => IconButton(
          tooltip: tip,
          onPressed: () => _step(by),
          icon: Icon(icon, size: 22),
          style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            navButton(Icons.chevron_left, 'เดือนก่อนหน้า', -1),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text.rich(
                  TextSpan(
                    text: '${thMonths[_view.month - 1]} ',
                    children: [
                      TextSpan(
                        text: '${_view.year + 543}',
                        style: const TextStyle(color: AppColors.muted, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            navButton(Icons.chevron_right, 'เดือนถัดไป', 1),
          ],
        ),
        const SizedBox(height: 8),
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      thWeekdaysShort[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: i == 0 ? AppColors.destructive.withValues(alpha: 0.8) : AppColors.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (var w = 0; w < 6; w++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                for (final iso in grid.sublist(w * 7, w * 7 + 7))
                  Expanded(
                    child: _Day(
                      iso: iso,
                      inMonth: sameMonth(iso, _view),
                      selected: iso == widget.value,
                      isToday: iso == widget.today,
                      count: countsShown ? counts[iso] ?? 0 : 0,
                      onTap: () => widget.onSelect(iso),
                    ),
                  ),
              ],
            ),
          ),
        const Divider(height: 16),
        Row(
          children: [
            if (countsShown) ...[
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              const Text('มีออเดอร์', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
            const Spacer(),
            if (inSheet)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: AppColors.muted, minimumSize: const Size(0, 44)),
                child: const Text('ปิด'),
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => widget.onSelect(widget.today),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primarySoft,
                foregroundColor: AppColors.primary,
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 44),
              ),
              child: const Text('วันนี้', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.iso,
    required this.inMonth,
    required this.selected,
    required this.isToday,
    required this.count,
    required this.onTap,
  });
  final String iso;
  final bool inMonth;
  final bool selected;
  final bool isToday;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = [
      formatDateLongTh(iso),
      if (isToday) 'วันนี้',
      if (count > 0) 'มีออเดอร์ $count รายการ',
    ].join(' · ');
    final color = selected
        ? Colors.white
        : isToday
            ? AppColors.primary
            : inMonth
                ? AppColors.ink
                : AppColors.muted.withValues(alpha: 0.5);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Center(
        child: Material(
          color: selected ? AppColors.primary : Colors.transparent,
          shape: CircleBorder(
            side: isToday && !selected ? const BorderSide(color: AppColors.primary) : BorderSide.none,
          ),
          elevation: selected ? 2 : 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    '${int.parse(iso.substring(8))}',
                    style: TextStyle(
                      fontSize: 14,
                      color: color,
                      fontWeight: selected || isToday ? FontWeight.w600 : FontWeight.w400,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      bottom: 6,
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: selected ? Colors.white : AppColors.primary,
                          shape: BoxShape.circle,
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
