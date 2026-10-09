import 'package:flutter/material.dart';

import '../logic/format.dart';
import '../models/models.dart';
import '../screens/new_order/wizard_widgets.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Labelled button showing a YYYY-MM-DD date; opens the date picker.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.first, this.last});
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? first;
  final String? last;

  Future<void> _pick(BuildContext context) async {
    final firstDate = toDate(first) ?? DateTime(2020);
    final lastDate = toDate(last) ?? DateTime(DateTime.now().year + 2, 12, 31);
    var initial = toDate(value) ?? DateTime.now();
    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(lastDate)) initial = lastDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: label,
    );
    if (picked != null) onChanged(toIsoDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    return FieldLabel(
      label,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, backgroundColor: AppColors.surface),
        onPressed: () => _pick(context),
        icon: const Icon(Icons.calendar_today_outlined, size: 18),
        label: Text(formatDateShort(value), style: const TextStyle(fontWeight: FontWeight.w400, fontFeatures: tabular)),
      ),
    );
  }
}

/// Cash or transfer, as two large cards ('cash' | 'transfer').
class PayMethodPicker extends StatelessWidget {
  const PayMethodPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.hints,
    this.label = 'ช่องทางการชำระเงิน',
  });
  final String? value;
  final ValueChanged<String> onChanged;
  final ({String cash, String transfer}) hints;
  final String label;

  @override
  Widget build(BuildContext context) {
    Widget card(String m, IconData icon, String hint) => Expanded(
          child: ChoiceCard(
            active: value == m,
            onTap: () => onChanged(m),
            icon: icon,
            title: m == 'cash' ? PaymentMethod.cash.label : PaymentMethod.transfer.label,
            hint: hint,
            minHeight: 88,
          ),
        );
    return FieldLabel(
      label,
      child: Row(
        children: [
          card('cash', Icons.payments_outlined, hints.cash),
          const SizedBox(width: 12),
          card('transfer', Icons.account_balance_outlined, hints.transfer),
        ],
      ),
    );
  }
}

/// Checkbox row for picking orders into a statement or payout.
class PickRow extends StatelessWidget {
  const PickRow({super.key, required this.selected, required this.onToggle, required this.child, this.trailing});
  final bool selected;
  final VoidCallback onToggle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Checkbox(value: selected, onChanged: (_) => onToggle()),
              const SizedBox(width: 4),
              Expanded(child: child),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
