import 'package:flutter/material.dart';

import '../theme/daily_palette.dart';
import '../utils/device_perf.dart';

/// โครงการ์ดนับจำนวนระหว่างโหลด — ไม่เห็นหน้าว่าง/กระพริบ
class CountRecordPanelSkeleton extends StatefulWidget {
  const CountRecordPanelSkeleton({
    super.key,
    required this.isTripMode,
  });

  final bool isTripMode;

  @override
  State<CountRecordPanelSkeleton> createState() =>
      _CountRecordPanelSkeletonState();
}

class _CountRecordPanelSkeletonState extends State<CountRecordPanelSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: DevicePerf.isConstrainedDevice ? 1600 : 1300,
      ),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: AnimatedBuilder(
        animation: _shimmer,
        builder: (context, _) {
          if (widget.isTripMode) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _box(context, _shimmer.value, radius: 22)),
                const SizedBox(height: 8),
                _box(context, _shimmer.value, height: 44, radius: 12),
              ],
            );
          }
          return _box(context, _shimmer.value, radius: 0);
        },
      ),
    );
  }

  Widget _box(
    BuildContext context,
    double t, {
    double? height,
    double radius = 22,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = DailyPalette.of(context);
    final sweep = (t % 1.0) * 2 - 1;
    final colors = widget.isTripMode
        ? (isDark
            ? [
                p.chipSurface,
                p.card,
                p.chipSurface,
              ]
            : const [
                Color(0xFFBBDEFB),
                Color(0xFFE3F2FD),
                Color(0xFFBBDEFB),
              ])
        : (isDark
            ? [
                const Color(0xFF3A1F2C),
                const Color(0xFF2A1520),
                const Color(0xFF3A1F2C),
              ]
            : const [
                Color(0xFFF8BBD0),
                Color(0xFFFCE4EC),
                Color(0xFFF8BBD0),
              ]);
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(sweep - 1, 0),
          end: Alignment(sweep + 1, 0),
          colors: colors,
        ),
      ),
    );
  }
}
