import 'package:flutter/material.dart';

import '../logic/order_status.dart' show BadgeTone;
import '../models/models.dart';
import '../theme/app_theme.dart';

export '../logic/order_status.dart' show BadgeTone;

({Color bg, Color fg, Color border}) toneColors(BadgeTone tone) => switch (tone) {
      BadgeTone.success => (bg: AppColors.successSoft, fg: const Color(0xFF065F46), border: const Color(0xFFA7F3D0)),
      BadgeTone.warning => (bg: AppColors.warningSoft, fg: const Color(0xFF92400E), border: const Color(0xFFFDE68A)),
      BadgeTone.danger => (bg: AppColors.destructiveSoft, fg: const Color(0xFFB91C1C), border: const Color(0xFFFECACA)),
      BadgeTone.info => (bg: AppColors.primarySoft, fg: AppColors.primary, border: const Color(0xFFDBEAFE)),
      BadgeTone.violet => (bg: AppColors.violetSoft, fg: const Color(0xFF6D28D9), border: const Color(0xFFDDD6FE)),
      BadgeTone.neutral => (bg: AppColors.subtle, fg: const Color(0xFF334155), border: AppColors.border),
    };

class AppBadge extends StatelessWidget {
  const AppBadge(this.label, {super.key, this.tone = BadgeTone.neutral, this.icon});
  final String label;
  final BadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: c.fg), const SizedBox(width: 4)],
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.fg, height: 1.4)),
        ],
      ),
    );
  }
}

class SourceBadge extends StatelessWidget {
  const SourceBadge(this.source, {super.key, this.long = false});
  final OrderSource source;
  final bool long;

  @override
  Widget build(BuildContext context) {
    final pit = source == OrderSource.pit;
    final fg = pit ? const Color(0xFF9A3412) : const Color(0xFF334155);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: pit ? const Color(0xFFFFF7ED) : AppColors.subtle,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: pit ? const Color(0xFFFED7AA) : AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(pit ? Icons.landscape_outlined : Icons.storefront_outlined, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            long ? source.label : source.short,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});

  @override
  Widget build(BuildContext context) =>
      const AppBadge('ตัวอย่าง', tone: BadgeTone.violet, icon: Icons.school_outlined);
}

class ErrorBox extends StatelessWidget {
  const ErrorBox(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.destructiveSoft,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: Color(0xFFB91C1C)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 14, color: Color(0xFFB91C1C))),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('ลองใหม่')),
        ],
      ),
    );
  }
}

/// Tinted one-line banner, e.g. a success message after saving.
class Notice extends StatelessWidget {
  const Notice({super.key, required this.text, this.icon = Icons.info_outline, this.tone = BadgeTone.info});
  final String text;
  final IconData icon;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final c = toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.fg),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 14, color: c.fg))),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 30, color: Color(0xFFCBD5E1)),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 6});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: AppColors.subtle, borderRadius: BorderRadius.circular(radius)),
      );
}

/// Placeholder rows shaped like the lists they stand in for.
class LoadingList extends StatelessWidget {
  const LoadingList({super.key, this.rows = 3});
  final int rows;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < rows; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const SkeletonBox(width: 40, height: 40, radius: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FractionallySizedBox(widthFactor: i.isOdd ? 0.5 : 0.66, child: const SkeletonBox()),
                        const SizedBox(height: 8),
                        const FractionallySizedBox(widthFactor: 0.33, child: SkeletonBox(height: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const SkeletonBox(width: 64, height: 16),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.color, this.borderColor});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      padding: padding,
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.muted),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.warn = false,
    this.pending = false,
    this.onTap,
  });
  final String label;
  final String value;
  final String? hint;
  final bool warn;

  /// Data not loaded yet: show a placeholder instead of a misleading 0.
  final bool pending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 4),
          if (pending) ...[
            const SkeletonBox(width: 96, height: 22),
            if (hint != null) ...[const SizedBox(height: 6), const SkeletonBox(width: 64, height: 12)],
          ] else ...[
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: warn ? AppColors.warning : AppColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (hint != null && hint!.isNotEmpty)
              Text(
                hint!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
          ],
        ],
      ),
    );
    return AppCard(
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}

class CountChip extends StatelessWidget {
  const CountChip({super.key, required this.label, required this.active, required this.onTap, this.count});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.primary : AppColors.surface,
      shape: StadiumBorder(side: BorderSide(color: active ? AppColors.primary : AppColors.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: active ? Colors.white : AppColors.ink,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(fontSize: 12, color: active ? Colors.white70 : AppColors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Two-to-four way segmented control in the web's pill style.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.trailingOf,
  });
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final String Function(T)? trailingOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: Material(
                color: v == selected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => onChanged(v),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: labelOf(v)),
                        if (trailingOf != null)
                          TextSpan(
                            text: ' ${trailingOf!(v)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: v == selected ? Colors.white70 : AppColors.muted,
                            ),
                          ),
                      ]),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: v == selected ? Colors.white : AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.bold = false, this.valueColor});
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 15 : 14,
                color: bold ? AppColors.ink : AppColors.muted,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: bold ? 17 : 14,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                color: valueColor ?? AppColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? AppColors.destructive : AppColors.ink,
  ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'ยืนยัน',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.destructive) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Bottom sheet with a title, scrollable body and safe-area padding.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            builder(ctx),
          ],
        ),
      ),
    ),
  );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.label, {super.key, this.child, this.hint});
  final String label;
  final String? hint;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        ?child,
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ],
    );
  }
}

const tabular = [FontFeature.tabularFigures()];
