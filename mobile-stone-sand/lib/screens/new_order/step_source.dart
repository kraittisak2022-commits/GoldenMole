import 'package:flutter/material.dart';

import '../../logic/format.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import 'wizard_widgets.dart';

class StepSource extends StatelessWidget {
  const StepSource({
    super.key,
    required this.sources,
    required this.source,
    required this.onSelect,
    required this.orderDate,
    required this.onDateChange,
  });

  /// Sources this account may create; one means it is fixed.
  final List<OrderSource> sources;
  final OrderSource? source;
  final ValueChanged<OrderSource> onSelect;

  /// '' means today.
  final String orderDate;
  final ValueChanged<String> onDateChange;

  Future<void> _pick(BuildContext context, String date) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: toDate(date) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      helpText: 'เลือกวันที่ออเดอร์',
    );
    if (picked == null) return;
    final iso = toIsoDate(picked);
    onDateChange(iso == toIsoDate() ? '' : iso);
  }

  @override
  Widget build(BuildContext context) {
    final today = toIsoDate();
    final date = orderDate.isEmpty ? today : orderDate;
    final isToday = date == today;
    final options = [
      (OrderSource.shop, Icons.storefront_outlined, 'ลูกค้าสั่งผ่านร้านวัสดุก่อสร้าง', 'เลขที่ DO…'),
      (OrderSource.pit, Icons.landscape_outlined, 'ลูกค้าสั่งกับท่าทรายโดยตรง', 'เลขที่ TS…'),
    ].where((o) => sources.contains(o.$1)).toList();
    final wide = MediaQuery.sizeOf(context).width >= 600;

    final cards = [
      for (final o in options)
        ChoiceCard(
          active: source == o.$1,
          onTap: () => onSelect(o.$1),
          icon: o.$2,
          title: 'ออเดอร์${o.$1.label}',
          hint: o.$3,
          footnote: o.$4,
          horizontal: !wide,
          minHeight: 128,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle(
          'ประเภทออเดอร์',
          subtitle: 'เลือกวันที่ แล้วเลือกว่ามาจากร้านวัสดุก่อสร้าง หรือสั่งที่ท่าทรายโดยตรง',
        ),
        const SizedBox(height: 20),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.calendar_month_outlined, size: 18, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('วันที่ออเดอร์', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  CountChip(label: 'วันนี้', active: isToday, onTap: () => onDateChange('')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pick(context, date),
                      icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                      label: Text(formatDateTh(date)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${isToday ? 'ลงวันที่วันนี้' : date.compareTo(today) < 0 ? 'ลงวันที่ย้อนหลัง' : 'ลงวันที่ล่วงหน้า'}'
                ' · ${formatDateLongTh(date)}',
                style: TextStyle(
                  fontSize: 14,
                  color: isToday ? AppColors.muted : AppColors.warning,
                  fontWeight: isToday ? FontWeight.w400 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (sources.length == 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'บัญชีนี้สร้างได้เฉพาะออเดอร์${sources.first.label}',
              style: const TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ),
        if (wide)
          Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: cards[i]),
              ],
            ],
          )
        else
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            cards[i],
          ],
      ],
    );
  }
}
