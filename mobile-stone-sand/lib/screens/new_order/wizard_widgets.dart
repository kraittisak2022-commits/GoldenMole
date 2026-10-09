import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../logic/format.dart';
import '../../theme/app_theme.dart';

class StepTitle extends StatelessWidget {
  const StepTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(subtitle!, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
          ),
      ],
    );
  }
}

/// Large radio card (source, fulfillment, payment method).
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.active,
    required this.onTap,
    required this.icon,
    required this.title,
    this.hint,
    this.footnote,
    this.horizontal = false,
    this.minHeight = 112,
  });
  final bool active;
  final VoidCallback? onTap;
  final IconData icon;
  final String title;
  final String? hint;
  final String? footnote;
  final bool horizontal;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final texts = Column(
      crossAxisAlignment: horizontal ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: horizontal ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: horizontal ? 18 : 16,
            fontWeight: FontWeight.w600,
            color: active && !horizontal ? AppColors.primary : AppColors.ink,
          ),
        ),
        if (hint != null)
          Text(
            hint!,
            textAlign: horizontal ? TextAlign.left : TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        if (footnote != null)
          Text(footnote!, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: [FontFeature.tabularFigures()])),
      ],
    );
    final iconWidget = horizontal
        ? Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? AppColors.primary : AppColors.subtle,
            ),
            child: Icon(icon, size: 30, color: active ? Colors.white : AppColors.primary),
          )
        : Icon(icon, size: 26, color: active ? AppColors.primary : AppColors.ink);
    return Semantics(
      selected: active,
      button: true,
      child: Material(
        color: active ? AppColors.primarySoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadius),
          side: BorderSide(color: active ? AppColors.primary : AppColors.border, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: EdgeInsets.all(horizontal ? 20 : 16),
              child: horizontal
                  ? Row(children: [iconWidget, const SizedBox(width: 16), Expanded(child: texts)])
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [iconWidget, const SizedBox(height: 8), texts],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

String _numText(num v) => v == 0 ? '' : formatNumber(v).replaceAll(',', '');

/// Numeric input bound to a value; external changes rewrite the text, typing reports parsed numbers.
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.value,
    required this.onChanged,
    this.decimal = true,
    this.hintText = '0',
    this.textAlign = TextAlign.start,
    this.enabled = true,
    this.dense = false,
    this.semanticLabel,
    this.style,
  });
  final TextStyle? style;
  final num value;
  final ValueChanged<double> onChanged;
  final bool decimal;
  final String hintText;
  final TextAlign textAlign;
  final bool enabled;
  final bool dense;
  final String? semanticLabel;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final _c = TextEditingController(text: _numText(widget.value));

  @override
  void didUpdateWidget(covariant NumberField old) {
    super.didUpdateWidget(old);
    final current = double.tryParse(_c.text) ?? 0;
    if (current != widget.value) {
      final text = _numText(widget.value);
      _c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _c,
      enabled: widget.enabled,
      textAlign: widget.textAlign,
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
      textInputAction: TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.allow(widget.decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]')),
      ],
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]).merge(widget.style),
      decoration: InputDecoration(
        hintText: widget.hintText,
        isDense: widget.dense,
        contentPadding: widget.dense ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10) : null,
      ),
      onChanged: (t) => widget.onChanged(double.tryParse(t) ?? 0),
    );
    return widget.semanticLabel == null ? field : Semantics(label: widget.semanticLabel, child: field);
  }
}

class CheckRow extends StatelessWidget {
  const CheckRow({super.key, required this.value, required this.onChanged, required this.child, this.boxed = true});
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget child;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final row = InkWell(
      borderRadius: BorderRadius.circular(kRadius),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: EdgeInsets.all(boxed ? 12 : 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            ),
            const SizedBox(width: 12),
            Expanded(child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 14), child: child)),
          ],
        ),
      ),
    );
    if (!boxed) return row;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
        side: const BorderSide(color: AppColors.border),
      ),
      child: row,
    );
  }
}
