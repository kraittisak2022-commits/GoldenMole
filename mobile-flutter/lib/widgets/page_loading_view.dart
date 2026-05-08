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
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: const Color(0xFF6B7B8F),
      fontWeight: FontWeight.w500,
    );

    return AnimatedBuilder(
      animation: _progressCtrl,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_progressCtrl.value);
        final pct = ((t * 90).clamp(0.0, 90.0)).round();
        final barValue = (t * 0.9).clamp(0.0, 0.9);
        final shimmerX = -1.3 + (_progressCtrl.value * 2.6);
        final headStyle =
            theme.textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF1B2A3A),
                  fontWeight: FontWeight.w800,
                  fontSize: 38,
                ) ??
                const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1B2A3A),
                );

        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFEFF5FA), Color(0xFFF8FBFE)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              top: -120 + 20 * t,
              left: -50,
              child: IgnorePointer(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0x222D8CFF), Color(0x002D8CFF)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -130 + 18 * t,
              right: -60,
              child: IgnorePointer(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0x1E11A8BA), Color(0x0011A8BA)],
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Container(
                width: 300,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE1E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShaderMask(
                      shaderCallback: (rect) => LinearGradient(
                        colors: [scheme.primary, scheme.tertiary],
                      ).createShader(rect),
                      blendMode: BlendMode.srcIn,
                      child: Text('${pct.toString().padLeft(2, '0')}%', style: headStyle),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: Stack(
                        children: [
                          LinearProgressIndicator(
                            value: barValue,
                            minHeight: 11,
                            backgroundColor: const Color(0xFFE3EAF3),
                            valueColor:
                                AlwaysStoppedAnimation<Color>(scheme.primary),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment(shimmerX, 0),
                                    end: Alignment(shimmerX + 0.9, 0),
                                    colors: const [
                                      Color(0x00FFFFFF),
                                      Color(0x66FFFFFF),
                                      Color(0x00FFFFFF),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 11),
                    Text(widget.label, style: labelStyle),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
