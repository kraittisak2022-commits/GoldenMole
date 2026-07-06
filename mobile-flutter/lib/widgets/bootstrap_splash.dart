import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/device_perf.dart';
import 'app_logo.dart';
import 'app_version_label.dart';

/// หน้าโหลดตอนเปิดแอพ — โทนสว่างสอดคล้องกับแดชบอร์ด
class BootstrapSplash extends StatefulWidget {
  const BootstrapSplash({super.key});

  @override
  State<BootstrapSplash> createState() => _BootstrapSplashState();
}

class _BootstrapSplashState extends State<BootstrapSplash>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  static const _teal = Color(0xFF11A8BA);
  static const _ink = Color(0xFF17374C);

  @override
  void initState() {
    super.initState();
    if (!DevicePerf.isConstrainedDevice) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: const Color(0xFFF3FBFC),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF3FBFC),
              Color(0xFFE8F6F8),
              Color(0xFFF8FAFC),
            ],
          ),
        ),
        child: Stack(
          children: [
            if (c != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: _SoftGlowPainter(progress: c),
                ),
              ),
            SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _logoHero(c),
                          const SizedBox(height: 28),
                          Text(
                            'Golden Mole',
                            style: GoogleFonts.kanit(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                              letterSpacing: 0.2,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'ระบบบันทึกงานก่อสร้าง',
                            style: GoogleFonts.kanit(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF5C6F82),
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 32),
                          if (c != null)
                            _ProgressBeam(progress: c)
                          else
                            const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.8,
                                color: _teal,
                              ),
                            ),
                          const SizedBox(height: 14),
                          Text(
                            'กำลังเตรียมระบบ...',
                            style: GoogleFonts.kanit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF7A8FA3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Center(
                      child: AppVersionLabel(
                        color: Color(0xFF9AAFBF),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoHero(AnimationController? c) {
    final card = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDCE8F0)),
        boxShadow: [
          BoxShadow(
            color: _teal.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const AppLogo(size: 88),
    );

    if (c == null) return card;

    return AnimatedBuilder(
      animation: c,
      builder: (context, child) {
        final pulse = 1.0 + 0.018 * math.sin(c.value * 2 * math.pi);
        return Transform.scale(scale: pulse, child: child);
      },
      child: card,
    );
  }
}

class _SoftGlowPainter extends CustomPainter {
  _SoftGlowPainter({required this.progress}) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value * 2 * math.pi;
    final top = Offset(
      size.width * 0.78 + 12 * math.cos(t * 0.6),
      size.height * 0.12 + 10 * math.sin(t * 0.5),
    );
    final bottom = Offset(
      size.width * 0.12 + 10 * math.sin(t * 0.45),
      size.height * 0.88 + 12 * math.cos(t * 0.55),
    );
    final paint = Paint();
    paint.shader = const RadialGradient(
      colors: [Color(0x3311A8BA), Color(0x0011A8BA)],
    ).createShader(Rect.fromCircle(center: top, radius: 180));
    canvas.drawCircle(top, 180, paint);
    paint.shader = const RadialGradient(
      colors: [Color(0x240D8A99), Color(0x000D8A99)],
    ).createShader(Rect.fromCircle(center: bottom, radius: 200));
    canvas.drawCircle(bottom, 200, paint);
  }

  @override
  bool shouldRepaint(covariant _SoftGlowPainter oldDelegate) => true;
}

class _ProgressBeam extends StatelessWidget {
  const _ProgressBeam({required this.progress});

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Stack(
          children: [
            Container(color: const Color(0xFFD8E8EE)),
            AnimatedBuilder(
              animation: progress,
              builder: (context, _) {
                return LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    const barW = 56.0;
                    final loop = (progress.value * 2) % 1.0;
                    final x = -barW + (w + barW) * loop;
                    return Stack(
                      children: [
                        Positioned(
                          left: x,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: barW,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0x0011A8BA),
                                  Color(0xFF11A8BA),
                                  Color(0xFF0D8A99),
                                  Color(0x000D8A99),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
