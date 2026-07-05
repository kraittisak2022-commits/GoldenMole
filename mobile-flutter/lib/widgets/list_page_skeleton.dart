import 'package:flutter/material.dart';

import '../utils/device_perf.dart';

/// โครง skeleton สำหรับหน้าลิสต์ (พนักงาน/ธุรกรรม/โครงการ/ปฏิทิน)
/// — แทนวงกลมหมุน ให้ผู้ใช้เห็นโครงหน้าทันทีระหว่างโหลด
class ListPageSkeleton extends StatefulWidget {
  const ListPageSkeleton({
    super.key,
    this.rowCount = 7,
    this.showHeaderBlock = false,
  });

  final int rowCount;

  /// true = มีบล็อกใหญ่ด้านบน (เช่น ปฏิทิน/แถบกรอง) ก่อนรายการ
  final bool showHeaderBlock;

  @override
  State<ListPageSkeleton> createState() => _ListPageSkeletonState();
}

class _ListPageSkeletonState extends State<ListPageSkeleton>
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
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        final t = _shimmer.value;
        return ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          children: [
            if (widget.showHeaderBlock) ...[
              _SkeletonBox(t: t, height: 220, radius: 20),
              const SizedBox(height: 16),
            ],
            for (var i = 0; i < widget.rowCount; i++) ...[
              _SkeletonRow(t: t + i * 0.06),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEAF1F5)),
      ),
      child: Row(
        children: [
          _SkeletonBox(t: t, width: 44, height: 44, radius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(t: t, width: 160, height: 14, radius: 7),
                const SizedBox(height: 8),
                _SkeletonBox(t: t + 0.03, width: 100, height: 11, radius: 6),
              ],
            ),
          ),
          _SkeletonBox(t: t + 0.05, width: 52, height: 16, radius: 8),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
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
    final sweep = (t % 1.0) * 2 - 1;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(sweep - 1, 0),
          end: Alignment(sweep + 1, 0),
          colors: const [
            Color(0xFFE8EEF4),
            Color(0xFFF5F8FB),
            Color(0xFFE8EEF4),
          ],
        ),
      ),
    );
  }
}
