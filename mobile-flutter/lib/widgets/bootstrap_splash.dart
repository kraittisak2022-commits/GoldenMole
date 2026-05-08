import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_logo.dart';

/// หน้าโหลดตอน restore session / เปิดแอพ — ใช้โลโก้และอนิเมชันเดียวกับ login
class BootstrapSplash extends StatefulWidget {
  const BootstrapSplash({super.key});

  @override
  State<BootstrapSplash> createState() => _BootstrapSplashState();
}

class _BootstrapSplashState extends State<BootstrapSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = const Color(0xFF1B2735);
    final textSecondary = const Color(0xFF73849A);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _SplashGraphicPainter(progress: _controller),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final pulse =
                          1.0 + 0.02 * math.sin(_controller.value * 2 * math.pi);
                      return Transform.scale(scale: pulse, child: child);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE3EAF2)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const AppLogo(size: 96),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Golden Mole User',
                    style: GoogleFonts.kanit(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Construction Management',
                    style: GoogleFonts.kanit(fontSize: 13.5, color: textSecondary),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: const Color(0xFF2D8CFF),
                      backgroundColor: const Color(0xFFDCE6F2),
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
}

class _SplashGraphicPainter extends CustomPainter {
  _SplashGraphicPainter({required this.progress}) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value * 2 * math.pi;
    final paint = Paint()..style = PaintingStyle.fill;

    final orb1 = Offset(
      size.width * 0.18 + 14 * math.sin(t * 0.85),
      size.height * 0.2 + 10 * math.cos(t * 0.6),
    );
    final orb2 = Offset(
      size.width * 0.82 + 12 * math.cos(t * 0.72),
      size.height * 0.78 + 10 * math.sin(t * 0.52),
    );

    paint.shader = const RadialGradient(
      colors: [Color(0x262D8CFF), Color(0x002D8CFF)],
    ).createShader(Rect.fromCircle(center: orb1, radius: 170));
    canvas.drawCircle(orb1, 170, paint);

    paint.shader = const RadialGradient(
      colors: [Color(0x1F11A8BA), Color(0x0011A8BA)],
    ).createShader(Rect.fromCircle(center: orb2, radius: 190));
    canvas.drawCircle(orb2, 190, paint);

    final linePaint = Paint()
      ..color = const Color(0x1F7D90A8)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(-40, size.height * 0.6)
      ..quadraticBezierTo(
        size.width * 0.35 + 14 * math.sin(t * 0.9),
        size.height * 0.53,
        size.width + 40,
        size.height * 0.64,
      );
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SplashGraphicPainter oldDelegate) => true;
}
