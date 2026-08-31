import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../theme/daily_palette.dart';
import '../utils/device_perf.dart';
import '../utils/daily_module_transactions.dart';
import 'soft_press_button.dart';

/// การ์ดเมนูบันทึกประจำวัน — มินิมอล อ่านง่าย รองรับแนวตั้งมือถือ
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
    final radius = 16.0;
    final mq = MediaQuery.sizeOf(context);
    final phonePortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait &&
        mq.shortestSide < 600;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 108.0;
        final maxH = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : maxW;
        // แนวตั้งมือถือ 2 คอลัมน์มักกว้างกว่าสูง — ห้ามสลับเป็นแถวแนวนอน
        final useRowLayout = !phonePortrait &&
            (maxW >= 240 && maxH >= 76 && maxW > maxH * 1.28);
        final cardW = maxW;
        final cardH = maxH;
        final scaleRef = useRowLayout
            ? (maxH < maxW ? maxH : maxW)
            : (maxW < maxH ? maxW : maxH);

        final iconGlyph = (scaleRef *
                (useRowLayout ? 0.36 : (phonePortrait ? 0.34 : 0.32)))
            .clamp(
              useRowLayout ? 22.0 : 22.0,
              useRowLayout ? 32.0 : (phonePortrait ? 32.0 : 34.0),
            );
        final wellSize = (iconGlyph * (useRowLayout ? 1.65 : 1.72)).clamp(
          useRowLayout ? 36.0 : 40.0,
          useRowLayout ? 46.0 : (phonePortrait ? 52.0 : 48.0),
        );
        final pad = (scaleRef * (phonePortrait ? 0.085 : 0.09)).clamp(
          phonePortrait ? 10.0 : 10.0,
          phonePortrait ? 12.0 : 14.0,
        );
        final titleSize = (scaleRef * (useRowLayout ? 0.09 : 0.105)).clamp(
          phonePortrait ? 13.0 : 12.0,
          useRowLayout ? 15.0 : 14.0,
        );
        final statusSize = (scaleRef * 0.072).clamp(10.0, 11.5);
        final useLiteChrome = defaultTargetPlatform == TargetPlatform.android ||
            DevicePerf.isConstrainedDevice;

        List<BoxShadow> cardLiftShadows() {
          // เงาชั้นล่าง + ไฮไลต์ขอบบน — ให้ความรู้สึกปุ่มนูน (ไม่ใช้ขอบสีสถานะ)
          final contact = isDark
              ? Colors.black.withValues(alpha: 0.38)
              : Colors.black.withValues(alpha: 0.07);
          final ambient = isDark
              ? Colors.black.withValues(alpha: 0.5)
              : p.shadowLift.withValues(alpha: useLiteChrome ? 0.22 : 0.3);
          final topRim = isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: 0.92);

          if (useLiteChrome) {
            return [
              BoxShadow(
                color: topRim,
                blurRadius: 0,
                offset: const Offset(0, -1),
              ),
              BoxShadow(
                color: contact,
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
              BoxShadow(
                color: ambient,
                blurRadius: 12,
                offset: const Offset(0, 5),
                spreadRadius: -2,
              ),
            ];
          }
          return [
            BoxShadow(
              color: topRim,
              blurRadius: 0,
              offset: const Offset(0, -1),
            ),
            BoxShadow(
              color: contact,
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
            BoxShadow(
              color: p.shadowCard,
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: ambient,
              blurRadius: 20,
              offset: const Offset(0, 8),
              spreadRadius: -4,
            ),
          ];
        }

        Widget iconWell() {
          return SizedBox(
            width: wellSize,
            height: wellSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: isDark ? 0.22 : 0.14),
                    accent.withValues(alpha: isDark ? 0.1 : 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(
                  useRowLayout ? 12 : 14,
                ),
                border: Border.all(
                  color: accent.withValues(alpha: isDark ? 0.32 : 0.18),
                ),
              ),
              child: Icon(icon, size: iconGlyph, color: accent),
            ),
          );
        }

        Widget statusBlock({
          TextAlign align = TextAlign.start,
          bool pill = false,
        }) {
          final text = Text(
            statusLabel,
            textAlign: align,
            maxLines: useRowLayout ? statusMaxLines : 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.kanit(
              fontSize: statusSize,
              fontWeight: FontWeight.w600,
              color: statusColor,
              height: 1.2,
            ),
          );
          if (!pill) return text;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: isDark ? 0.14 : 0.09),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: pad * 0.55,
                vertical: pad * 0.12,
              ),
              child: text,
            ),
          );
        }

        Widget titleText({TextAlign align = TextAlign.start}) {
          return Text(
            title,
            textAlign: align,
            maxLines: useRowLayout ? 2 : 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.kanit(
              fontSize: titleSize,
              fontWeight: FontWeight.w700,
              color: p.ink,
              height: 1.2,
              letterSpacing: -0.2,
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
            padding: EdgeInsets.fromLTRB(
              pad * 0.75,
              pad * 0.65,
              pad * 0.75,
              pad * 0.7,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconWell(),
                SizedBox(height: pad * 0.38),
                titleText(align: TextAlign.center),
                SizedBox(height: pad * 0.24),
                statusBlock(align: TextAlign.center, pill: true),
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
              boxShadow: cardLiftShadows(),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: useRowLayout ? rowContent() : stackedContent(),
            ),
          ),
        );

        return SoftPressButton(
          onTap: onTap,
          size: SoftPressSize.medium,
          borderRadius: radius,
          isDarkSurface: isDark,
          liftWhenIdle: true,
          idleLiftY: useLiteChrome ? -0.5 : -1,
          depthShadow: SoftPressDepthShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.45)
                : p.shadowLift.withValues(alpha: useLiteChrome ? 0.18 : 0.22),
            blurRadius: useLiteChrome ? 10 : 18,
            offsetY: useLiteChrome ? 5 : 7,
            pressedBlurRadius: useLiteChrome ? 3 : 4,
            pressedOffsetY: 1,
          ),
          hitPadding: EdgeInsets.zero,
          child: shapedCard,
        );
      },
    );
  }
}
