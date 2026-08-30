import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../theme/daily_palette.dart';
import '../utils/device_perf.dart';
import '../utils/daily_module_transactions.dart';
import 'soft_press_button.dart';

/// การ์ดเมนูบันทึกประจำวัน — เติมเซลล์เต็มในแนวตั้ง / แถวในแนวนอน
/// ไอคอนในบ่อสีอ่อน + ลำดับตัวอักษรชัด (Kanit) + SoftPress
class RecordModuleCard extends StatelessWidget {
  const RecordModuleCard({
    super.key,
    required this.title,
    required this.icon,
    required this.fillStatus,
    required this.onTap,
    this.tileColor = const Color(0xFF4FC3F7),
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
    final depthShadow = SoftPressDepthShadow(
      color: p.shadowCard,
      blurRadius: 10,
      offsetY: 3,
      pressedBlurRadius: 4,
      pressedOffsetY: 1,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 108.0;
        final maxH = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : maxW;
        final isLandscapeCell = maxW > maxH * 1.08;
        // มือถือ 2 คอลัมน์: เซลล์กว้าง ≥ ~140
        final phoneWidePortrait = !isLandscapeCell && maxW >= 140;
        // เติมเซลล์เต็ม — ไม่หดเป็นจัตุรัสลอยกลางช่อง (รู้สึกแบบเว็บแดชบอร์ด)
        final cardW = maxW;
        final cardH = maxH;
        final scaleRef = isLandscapeCell
            ? (maxH < maxW ? maxH : maxW)
            : (maxW < maxH ? maxW : maxH);

        final iconGlyph = (scaleRef *
                (isLandscapeCell
                    ? 0.42
                    : phoneWidePortrait
                        ? 0.22
                        : 0.36))
            .clamp(
              isLandscapeCell ? 26.0 : (phoneWidePortrait ? 22.0 : 28.0),
              isLandscapeCell ? 36.0 : (phoneWidePortrait ? 28.0 : 40.0),
            );
        final wellSize = (iconGlyph * (phoneWidePortrait ? 1.85 : 1.75)).clamp(
          isLandscapeCell ? 40.0 : (phoneWidePortrait ? 40.0 : 44.0),
          isLandscapeCell ? 52.0 : (phoneWidePortrait ? 52.0 : 64.0),
        );
        final pad = (scaleRef * (phoneWidePortrait ? 0.085 : 0.1)).clamp(
          phoneWidePortrait ? 10.0 : 8.0,
          phoneWidePortrait ? 14.0 : 14.0,
        );
        final titleSize = (scaleRef * (phoneWidePortrait ? 0.095 : 0.11)).clamp(
          phoneWidePortrait ? 13.0 : 11.5,
          phoneWidePortrait ? 15.5 : 14.5,
        );
        final statusSize = (scaleRef * (phoneWidePortrait ? 0.078 : 0.09)).clamp(
          phoneWidePortrait ? 11.0 : 10.0,
          phoneWidePortrait ? 12.5 : 12.0,
        );
        final radius = isLandscapeCell
            ? 16.0
            : (phoneWidePortrait ? 18.0 : 18.0);
        final wellRadius = phoneWidePortrait ? 14.0 : 12.0;
        final useLiteChrome = defaultTargetPlatform == TargetPlatform.android ||
            DevicePerf.isConstrainedDevice;

        Widget iconWell() {
          return SizedBox(
            width: wellSize,
            height: wellSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(wellRadius),
              ),
              child: Icon(icon, size: iconGlyph, color: accent),
            ),
          );
        }

        Widget statusBlock({TextAlign align = TextAlign.center}) {
          if (recorded) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: align == TextAlign.left
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: (statusSize + 1).clamp(12.0, 14.0),
                  color: p.statusComplete,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    statusLabel,
                    textAlign: align,
                    maxLines: statusMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.kanit(
                      fontSize: statusSize,
                      fontWeight: FontWeight.w600,
                      color: p.statusComplete,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            );
          }
          return Text(
            statusLabel,
            textAlign: align,
            maxLines: statusMaxLines,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.kanit(
              fontSize: statusSize,
              fontWeight: FontWeight.w500,
              color: statusColor,
              height: 1.2,
            ),
          );
        }

        Widget titleText({TextAlign align = TextAlign.center}) {
          return Text(
            title,
            textAlign: align,
            maxLines: isLandscapeCell ? 2 : (phoneWidePortrait ? 2 : 3),
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.kanit(
              fontSize: titleSize,
              fontWeight: FontWeight.w700,
              color: p.ink,
              height: 1.25,
              letterSpacing: -0.15,
            ),
          );
        }

        Widget portraitContent() {
          // ไอคอนบนซ้าย + สถานะมุมขวา · ชื่อ/สถานะยึดด้านล่าง — สแกนง่ายบนมือถือ
          return Padding(
            padding: EdgeInsets.fromLTRB(pad, pad * 0.85, pad * 0.85, pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconWell(),
                    const Spacer(),
                    Padding(
                      padding: EdgeInsets.only(top: pad * 0.15),
                      child: _StatusMark(partial: partial),
                    ),
                  ],
                ),
                const Spacer(flex: 2),
                titleText(align: TextAlign.left),
                SizedBox(height: pad * 0.28),
                statusBlock(align: TextAlign.left),
              ],
            ),
          );
        }

        Widget landscapeContent() {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: pad * 0.75),
            child: Row(
              children: [
                iconWell(),
                SizedBox(width: pad * 0.75),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleText(align: TextAlign.left),
                      SizedBox(height: pad * 0.22),
                      statusBlock(align: TextAlign.left),
                    ],
                  ),
                ),
                _StatusMark(partial: partial),
              ],
            ),
          );
        }

        // แท็บเล็ตแนวตั้งคอลัมน์เดียวแคบ: คงสแต็กกลางแบบเดิม แต่ใส่บ่อไอคอน
        Widget narrowPortraitContent() {
          return Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconWell(),
                SizedBox(height: pad * 0.55),
                titleText(),
                SizedBox(height: pad * 0.28),
                statusBlock(),
              ],
            ),
          );
        }

        final surfaceShadow = useLiteChrome
            ? [
                BoxShadow(
                  color: p.shadowCard,
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null;

        final shapedCard = SizedBox(
          width: cardW,
          height: cardH,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: p.hairline.withValues(alpha: isDark ? 0.9 : 0.85),
                width: 1,
              ),
              boxShadow: surfaceShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: isLandscapeCell
                  ? landscapeContent()
                  : (phoneWidePortrait
                      ? portraitContent()
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            narrowPortraitContent(),
                            Positioned(
                              top: pad * 0.45,
                              right: pad * 0.45,
                              child: _StatusMark(partial: partial),
                            ),
                          ],
                        )),
            ),
          ),
        );

        return SoftPressButton(
          onTap: onTap,
          size: SoftPressSize.medium,
          borderRadius: radius,
          isDarkSurface: isDark,
          liftWhenIdle: !useLiteChrome,
          depthShadow: useLiteChrome ? null : depthShadow,
          // ห้ามให้ SoftPress หดการ์ดด้วย Align/padding นอกเซลล์
          hitPadding: EdgeInsets.zero,
          child: shapedCard,
        );
      },
    );
  }
}

class _StatusMark extends StatelessWidget {
  const _StatusMark({required this.partial});

  final bool partial;

  @override
  Widget build(BuildContext context) {
    // มุมขวา: จุดเหลืองเฉพาะสถานะค้าง — ครบแล้วใช้เช็คในบรรทัดสถานะพอ
    if (!partial) {
      return const SizedBox(width: 8, height: 8);
    }
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(top: 4, right: 2),
      decoration: const BoxDecoration(
        color: DailyPalette.statusIncompleteDot,
        shape: BoxShape.circle,
      ),
    );
  }
}
