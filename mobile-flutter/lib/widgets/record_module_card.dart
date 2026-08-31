import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../theme/daily_palette.dart';
import '../utils/device_perf.dart';
import '../utils/daily_module_transactions.dart';
import 'soft_press_button.dart';

/// การ์ดเมนูบันทึกประจำวัน — มินิมอล แบน อ่านง่าย
class RecordModuleCard extends StatelessWidget {
  const RecordModuleCard({
    super.key,
    required this.title,
    required this.icon,
    required this.fillStatus,
    required this.onTap,
    this.tileColor = const Color(0xFF0D9488),
    this.completeStatusLabelOverride,
    this.statusMaxLines = 2,
  });

  final String title;
  final IconData icon;
  final DailyModuleFillStatus fillStatus;
  final VoidCallback onTap;
  final Color tileColor;
  final String? completeStatusLabelOverride;
  final int statusMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = DailyPalette.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
        ? p.statusComplete
        : partial
        ? p.statusIncomplete
        : p.statusPending;

    final accent = tileColor;
    final radius = 14.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 108.0;
        final maxH = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : maxW;
        final isLandscapeCell = maxW > maxH * 1.08;
        final phoneWidePortrait = !isLandscapeCell && maxW >= 140;
        final cardW = maxW;
        final cardH = maxH;
        final scaleRef = isLandscapeCell
            ? (maxH < maxW ? maxH : maxW)
            : (maxW < maxH ? maxW : maxH);

        final iconGlyph = (scaleRef *
                (isLandscapeCell
                    ? 0.38
                    : phoneWidePortrait
                    ? 0.26
                    : 0.32))
            .clamp(
              isLandscapeCell ? 22.0 : (phoneWidePortrait ? 22.0 : 24.0),
              isLandscapeCell ? 32.0 : (phoneWidePortrait ? 30.0 : 34.0),
            );
        final wellSize = (iconGlyph * 1.65).clamp(
          isLandscapeCell ? 36.0 : (phoneWidePortrait ? 40.0 : 38.0),
          isLandscapeCell ? 46.0 : (phoneWidePortrait ? 50.0 : 48.0),
        );
        final pad = (scaleRef * 0.09).clamp(10.0, 14.0);
        final titleSize = (scaleRef * (phoneWidePortrait ? 0.09 : 0.1)).clamp(
          phoneWidePortrait ? 13.0 : 12.0,
          phoneWidePortrait ? 15.0 : 14.0,
        );
        final statusSize = (scaleRef * 0.075).clamp(10.5, 12.0);
        final useLiteChrome = defaultTargetPlatform == TargetPlatform.android ||
            DevicePerf.isConstrainedDevice;

        List<BoxShadow> cardLiftShadows() {
          if (useLiteChrome) {
            return [
              BoxShadow(
                color: p.shadowLift.withValues(alpha: isDark ? 0.42 : 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
                spreadRadius: -2,
              ),
            ];
          }
          return [
            BoxShadow(
              color: p.shadowCard,
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: p.shadowLift,
              blurRadius: 18,
              offset: const Offset(0, 7),
              spreadRadius: -3,
            ),
          ];
        }

        Widget iconWell() {
          return SizedBox(
            width: wellSize,
            height: wellSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.14 : 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: accent.withValues(alpha: isDark ? 0.35 : 0.22),
                ),
              ),
              child: Icon(icon, size: iconGlyph, color: accent),
            ),
          );
        }

        Widget statusBlock({TextAlign align = TextAlign.start}) {
          return Text(
            statusLabel,
            textAlign: align,
            maxLines: statusMaxLines,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.kanit(
              fontSize: statusSize,
              fontWeight: FontWeight.w500,
              color: statusColor,
              height: 1.25,
            ),
          );
        }

        Widget titleText({TextAlign align = TextAlign.start}) {
          return Text(
            title,
            textAlign: align,
            maxLines: isLandscapeCell ? 2 : (phoneWidePortrait ? 2 : 3),
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.kanit(
              fontSize: titleSize,
              fontWeight: FontWeight.w600,
              color: p.ink,
              height: 1.25,
              letterSpacing: -0.1,
            ),
          );
        }

        Widget trailingChevron() {
          return Icon(
            Icons.chevron_right_rounded,
            size: (titleSize + 4).clamp(18.0, 22.0),
            color: p.inkMuted.withValues(alpha: 0.45),
          );
        }

        Widget rowContent() {
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: pad,
              vertical: pad * 0.85,
            ),
            child: Row(
              children: [
                iconWell(),
                SizedBox(width: pad * 0.7),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleText(),
                      SizedBox(height: pad * 0.18),
                      statusBlock(),
                    ],
                  ),
                ),
                trailingChevron(),
              ],
            ),
          );
        }

        Widget stackedContent() {
          return Padding(
            padding: EdgeInsets.all(pad * 0.9),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconWell(),
                SizedBox(height: pad * 0.45),
                titleText(align: TextAlign.center),
                SizedBox(height: pad * 0.2),
                statusBlock(align: TextAlign.center),
              ],
            ),
          );
        }

        final shapedCard = SizedBox(
          width: cardW,
          height: cardH,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: recorded
                    ? p.statusComplete.withValues(alpha: isDark ? 0.35 : 0.28)
                    : partial
                    ? p.statusIncomplete.withValues(alpha: isDark ? 0.3 : 0.22)
                    : p.hairline.withValues(alpha: isDark ? 0.85 : 1),
              ),
              boxShadow: cardLiftShadows(),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: isLandscapeCell || phoneWidePortrait
                  ? rowContent()
                  : stackedContent(),
            ),
          ),
        );

        return SoftPressButton(
          onTap: onTap,
          size: SoftPressSize.medium,
          borderRadius: radius,
          isDarkSurface: isDark,
          liftWhenIdle: true,
          idleLiftY: useLiteChrome ? -1 : -1.5,
          depthShadow: useLiteChrome
              ? null
              : SoftPressDepthShadow(
                  color: p.shadowLift.withValues(alpha: isDark ? 0.5 : 0.16),
                  blurRadius: 16,
                  offsetY: 6,
                  pressedBlurRadius: 5,
                  pressedOffsetY: 2,
                ),
          hitPadding: EdgeInsets.zero,
          child: shapedCard,
        );
      },
    );
  }
}
