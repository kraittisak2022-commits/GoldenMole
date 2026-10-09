import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'tour_controller.dart';
import 'tour_overlay.dart';
import 'tour_steps.dart';

class TourMenuCard extends StatefulWidget {
  const TourMenuCard({super.key});

  @override
  State<TourMenuCard> createState() => _TourMenuCardState();
}

class _TourMenuCardState extends State<TourMenuCard> {
  bool _ending = false;

  Future<void> _finish(TourController tour) async {
    final ok = await confirmDialog(
      context,
      title: 'เลิกสอนใช้งาน?',
      message: 'ลบข้อมูลสาธิตทั้งหมดและเลิกสอนใช้งาน?',
      confirmLabel: 'ลบและเลิกสอน',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _ending = true);
    await tour.end();
    if (mounted) setState(() => _ending = false);
  }

  @override
  Widget build(BuildContext context) {
    final tour = TourScope.maybeOf(context);
    if (tour == null) return const SizedBox.shrink();
    final state = tour.state;
    final violetButton = FilledButton.styleFrom(backgroundColor: violet600);

    final text = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: violet600, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.school_outlined, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('สอนใช้งาน', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                state != null
                    ? '${state.paused ? 'พักไว้ที่' : 'กำลังสอนอยู่ ·'} ขั้น ${state.step + 1}/${tourSteps.length} — ข้อมูลที่มีป้าย "สาธิต" จะถูกลบเมื่อจบ'
                    : 'พาทำจริงทีละขั้น ตั้งแต่สร้างออเดอร์ ออกบิล รับเงิน จนวางบิลและเคลียร์บิล ใช้เวลาประมาณ 10 นาที '
                          'ข้อมูลที่สร้างเป็นข้อมูลสาธิต คนอื่นไม่เห็น และถูกลบเมื่อจบ',
                style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted),
              ),
              if (tour.error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(tour.error, style: const TextStyle(fontSize: 14, color: AppColors.destructive)),
              ],
            ],
          ),
        ),
      ],
    );

    final List<Widget> buttons = state != null
        ? [
            if (state.paused)
              Expanded(
                child: FilledButton.icon(
                  style: violetButton,
                  onPressed: tour.resume,
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text('สอนต่อ'),
                ),
              ),
            if (state.paused) const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _ending ? null : () => _finish(tour),
                icon: const Icon(Icons.delete_outline, size: 20),
                label: Text(_ending ? 'กำลังลบ…' : 'เลิกสอน'),
              ),
            ),
          ]
        : [
            Expanded(
              child: FilledButton.icon(
                style: violetButton,
                onPressed: tour.starting ? null : tour.start,
                icon: const Icon(Icons.play_arrow, size: 20),
                label: Text(tour.starting ? 'กำลังเตรียม…' : 'เริ่มสอนใช้งาน'),
              ),
            ),
          ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: violet200),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [violet50, AppColors.surface],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          text,
          const SizedBox(height: 16),
          Row(children: buttons),
        ],
      ),
    );
  }
}
