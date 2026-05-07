import 'package:flutter/material.dart';

class PageLoadingView extends StatefulWidget {
  const PageLoadingView({
    super.key,
    this.label = 'กำลังโหลดข้อมูล',
  });

  final String label;

  @override
  State<PageLoadingView> createState() => _PageLoadingViewState();
}

class _PageLoadingViewState extends State<PageLoadingView>
    with SingleTickerProviderStateMixin {
  /// ความคืบหน้าแสดงผู้ใช้ (สูงสุด ~90%); ควบด้วย animation เดียว ไม่ใช้ timer เรียง setState
  late AnimationController _progressCtrl;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _progressCtrl.forward();
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelStyle =
        theme.textTheme.bodyMedium?.copyWith(color: Colors.black54);

    return AnimatedBuilder(
      animation: _progressCtrl,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_progressCtrl.value);
        final pct = ((t * 90).clamp(0.0, 90.0)).round();
        final barValue = (t * 0.9).clamp(0.0, 0.9);
        final headStyle =
            theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                ) ??
                const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                );

        return Center(
          child: Container(
            width: 240,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (rect) =>
                      LinearGradient(
                        colors: [scheme.primary, scheme.tertiary],
                      ).createShader(rect),
                  blendMode: BlendMode.srcIn,
                  child: Text(
                    '${pct.toString().padLeft(2, '0')}%',
                    style: headStyle,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: barValue,
                    minHeight: 10,
                    backgroundColor: const Color(0xFFE8EEF5),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(scheme.primary),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.label,
                  style: labelStyle,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
