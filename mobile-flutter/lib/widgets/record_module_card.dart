import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/device_perf.dart';
import '../utils/daily_module_transactions.dart';
import 'soft_press_button.dart';

Color _iconTint(Color accent) {
  return Color.lerp(accent, const Color(0xFF334155), 0.28)!;
}

const _cardDepthShadow = SoftPressDepthShadow(
  color: Color(0x180F172A),
  blurRadius: 17,
  offsetY: 6,
  pressedBlurRadius: 4,
  pressedOffsetY: 1,
);

/// การ์ดเมนูบันทึกประจำวัน — จัตุรัสในแนวตั้ง / สี่เหลี่ยมผืนผ้าในแนวนอน
class RecordModuleCard extends StatelessWidget {
  const RecordModuleCard({
    super.key,
    required this.title,
    required this.icon,
    required this.fillStatus,
    required this.onTap,
    this.tileColor = const Color(0xFF4FC3F7),
    this.showLightStyle = false,
    this.completeStatusLabelOverride,
    this.statusMaxLines = 2,
  });

  final String title;
  final IconData icon;
  final DailyModuleFillStatus fillStatus;
  final VoidCallback onTap;
  final Color tileColor;
  final bool showLightStyle;
  final String? completeStatusLabelOverride;
  final int statusMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final status = fillStatus;
    final recorded = status == DailyModuleFillStatus.complete;
    final partial = status == DailyModuleFillStatus.incomplete;

    final overrideComplete = completeStatusLabelOverride?.trim();
    final hasDetailOverride =
        overrideComplete != null && overrideComplete.isNotEmpty;
    final statusLabel = hasDetailOverride && (recorded || partial)
        ? overrideComplete
        : recorded
        ? l10n.statusComplete
        : partial
        ? l10n.statusIncomplete
        : l10n.statusTapToRecord;

    final statusColor = recorded
        ? const Color(0xFF15803D)
        : partial
        ? const Color(0xFFB45309)
        : const Color(0xFF94A3B8);

    final accent = tileColor;
    final iconColor = _iconTint(accent);
    final borderColor = recorded
        ? const Color(0xFFBBF7D0)
        : partial
        ? const Color(0xFFFDE68A)
        : Color.lerp(const Color(0xFFE8EDF3), accent, 0.2)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 108.0;
        final maxH = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : maxW;
        final isLandscapeCell = maxW > maxH * 1.08;
        final cardW = isLandscapeCell ? maxW : (maxW < maxH ? maxW : maxH);
        final cardH = isLandscapeCell ? maxH : cardW;
        final scaleRef = isLandscapeCell
            ? (maxH < maxW ? maxH : maxW)
            : cardW;
        final iconSize = (scaleRef * (isLandscapeCell ? 0.54 : 0.5))
            .clamp(isLandscapeCell ? 32.0 : 40.0, isLandscapeCell ? 50.0 : 66.0);
        final pad = (scaleRef * 0.1).clamp(8.0, 14.0);
        final titleSize = (scaleRef * 0.11).clamp(11.5, 14.5);
        final statusSize = (scaleRef * 0.09).clamp(10.0, 12.0);
        final radius = isLandscapeCell ? 12.0 : 14.0;
        final textMaxWidth = isLandscapeCell
            ? (cardW - iconSize - pad * 3).clamp(48.0, cardW)
            : cardW - (pad * 2);

        Widget statusBlock() {
          if (recorded) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: (pad * 0.45).clamp(6.0, 10.0),
                  vertical: (pad * 0.18).clamp(2.0, 4.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: (statusSize + 2).clamp(11.0, 14.0),
                      color: const Color(0xFF15803D),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        statusLabel,
                        textAlign: TextAlign.center,
                        maxLines: statusMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: statusSize,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF15803D),
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return Text(
            statusLabel,
            textAlign: TextAlign.center,
            maxLines: statusMaxLines,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: statusSize,
              fontWeight: FontWeight.w500,
              color: statusColor,
              height: 1.15,
            ),
          );
        }

        Widget titleBlock() {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: textMaxWidth,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: isLandscapeCell ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E293B),
                    height: 1.2,
                  ),
                ),
              ),
              SizedBox(height: pad * 0.28),
              SizedBox(
                width: textMaxWidth,
                child: statusBlock(),
              ),
            ],
          );
        }

        Widget centeredContent() {
          if (isLandscapeCell) {
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: pad * 0.5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: iconSize,
                    color: iconColor,
                  ),
                  SizedBox(width: pad * 0.65),
                  Flexible(child: titleBlock()),
                ],
              ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: iconSize,
                color: iconColor,
              ),
              SizedBox(height: pad * 0.5),
              titleBlock(),
            ],
          );
        }

        final useLiteChrome = defaultTargetPlatform == TargetPlatform.android ||
            DevicePerf.isConstrainedDevice;

        // เครื่องช้า: SoftPress ไม่ใส่ depthShadow — ใส่เงาที่การ์ดแทนให้ยังดูนูน
        final surfaceShadow = useLiteChrome
            ? const [
                BoxShadow(
                  color: Color(0x180F172A),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ]
            : null;

        final shapedCard = SizedBox(
          width: cardW,
          height: cardH,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: surfaceShadow,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(child: centeredContent()),
                Positioned(
                  top: pad * 0.5,
                  right: pad * 0.5,
                  child: _StatusDot(
                    recorded: recorded,
                    partial: partial,
                  ),
                ),
              ],
            ),
          ),
        );

        return Align(
          alignment: Alignment.center,
          child: SoftPressButton(
            onTap: onTap,
            size: SoftPressSize.medium,
            borderRadius: radius,
            isDarkSurface: false,
            liftWhenIdle: !useLiteChrome,
            depthShadow: useLiteChrome ? null : _cardDepthShadow,
            child: shapedCard,
          ),
        );
      },
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.recorded,
    required this.partial,
  });

  final bool recorded;
  final bool partial;

  @override
  Widget build(BuildContext context) {
    if (recorded) {
      return Container(
        width: 18,
        height: 18,
        decoration: const BoxDecoration(
          color: Color(0xFFECFDF5),
          shape: BoxShape.circle,
          border: Border.fromBorderSide(
            BorderSide(color: Color(0xFFBBF7D0)),
          ),
        ),
        child: const Icon(
          Icons.check_rounded,
          size: 12,
          color: Color(0xFF15803D),
        ),
      );
    }
    final color = partial
        ? const Color(0xFFF59E0B)
        : const Color(0xFFCBD5E1);
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
