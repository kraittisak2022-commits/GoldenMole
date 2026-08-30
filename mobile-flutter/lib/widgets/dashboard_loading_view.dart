import 'package:flutter/material.dart';

import '../theme/daily_palette.dart';
import '../utils/device_perf.dart';

/// โครงหน้าแดชบอร์ดแบบ skeleton — โหลดครั้งแรกไม่เห็นหน้าว่าง
class DashboardLoadingView extends StatefulWidget {
  const DashboardLoadingView({super.key});

  @override
  State<DashboardLoadingView> createState() => _DashboardLoadingViewState();
}

class _DashboardLoadingViewState extends State<DashboardLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: DevicePerf.isConstrainedDevice ? 1800 : 1400,
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
    final p = DailyPalette.of(context);
    return ColoredBox(
      color: p.surface,
      child: AnimatedBuilder(
        animation: _shimmer,
        builder: (context, _) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ShimmerBox(
                  t: _shimmer.value,
                  height: 92,
                  radius: 20,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: p.hairline),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          const gap = 10.0;
                          const cols = 3;
                          final cellW =
                              (c.maxWidth - gap * (cols - 1)) / cols;
                          final cellH = cellW.clamp(88.0, 148.0);
                          return Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: List.generate(
                              9,
                              (i) => _ShimmerBox(
                                t: _shimmer.value + i * 0.07,
                                width: cellW,
                                height: cellH,
                                radius: 22,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.t,
    this.width,
    required this.height,
    required this.radius,
  });

  final double t;
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? p.chipSurface : const Color(0xFFE8EEF4);
    final peak = dark ? p.card : const Color(0xFFF5F8FB);
    final sweep = (t % 1.0) * 2 - 1;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(sweep - 1, 0),
          end: Alignment(sweep + 1, 0),
          colors: [base, peak, base],
        ),
      ),
    );
  }
}
