import 'package:flutter/material.dart';

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
                Expanded(child: _box(_shimmer.value, radius: 22)),
                const SizedBox(height: 8),
                _box(_shimmer.value, height: 44, radius: 12),
              ],
            );
          }
          return _box(_shimmer.value, radius: 0);
        },
      ),
    );
  }

  Widget _box(double t, {double? height, double radius = 22}) {
    final sweep = (t % 1.0) * 2 - 1;
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(sweep - 1, 0),
          end: Alignment(sweep + 1, 0),
          colors: widget.isTripMode
              ? const [
                  Color(0xFFBBDEFB),
                  Color(0xFFE3F2FD),
                  Color(0xFFBBDEFB),
                ]
              : const [
                  Color(0xFFF8BBD0),
                  Color(0xFFFCE4EC),
                  Color(0xFFF8BBD0),
                ],
        ),
      ),
    );
  }
}
