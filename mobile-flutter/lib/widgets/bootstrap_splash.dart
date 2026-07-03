import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/device_perf.dart';
import 'app_logo.dart';

/// หน้าโหลดตอน restore session / เปิดแอพ — ธีมมืดล้ำสมัย (ไฮเทค)
class BootstrapSplash extends StatefulWidget {
  const BootstrapSplash({super.key});

  @override
  State<BootstrapSplash> createState() => _BootstrapSplashState();
}

class _BootstrapSplashState extends State<BootstrapSplash>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  static const _neonCyan = Color(0xFF22D3EE);
  static const _neonBlue = Color(0xFF3B82F6);

  @override
  void initState() {
    super.initState();
    if (!DevicePerf.isConstrainedDevice) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 6),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  BoxDecoration get _bgDecoration => const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.35),
          radius: 1.25,
          colors: [Color(0xFF0F2647), Color(0xFF0A1730), Color(0xFF05070F)],
          stops: [0.0, 0.55, 1.0],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) {
      return Scaffold(
        body: DecoratedBox(
          decoration: _bgDecoration,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size.square(150),
                        painter: _OrbitRingsPainter(t: 0),
                      ),
                      _logoCard(),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                _title(),
                const SizedBox(height: 8),
                _subtitle(),
                const SizedBox(height: 30),
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: _neonCyan,
                    backgroundColor: Color(0x2222D3EE),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: DecoratedBox(
        decoration: _bgDecoration,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _TechBackgroundPainter(progress: c)),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: AnimatedBuilder(
                      animation: c,
                      builder: (context, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size.square(170),
                              painter: _OrbitRingsPainter(t: c.value),
                            ),
                            Transform.scale(
                              scale: 1.0 +
                                  0.03 * math.sin(c.value * 2 * math.pi),
                              child: child,
                            ),
                          ],
                        );
                      },
                      child: _logoCard(glow: true),
                    ),
                  ),
                  const SizedBox(height: 34),
                  _title(),
                  const SizedBox(height: 8),
                  _subtitle(),
                  const SizedBox(height: 30),
                  _ProgressBeam(progress: c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoCard({bool glow = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x1AFFFFFF), Color(0x0DFFFFFF)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _neonCyan.withValues(alpha: 0.35), width: 1.2),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: _neonCyan.withValues(alpha: 0.35),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: _neonBlue.withValues(alpha: 0.25),
                  blurRadius: 50,
                  spreadRadius: 6,
                ),
              ]
            : const [],
      ),
      child: const AppLogo(size: 84),
    );
  }

  Widget _title() {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0xFFEAF6FF), _neonCyan, Color(0xFFEAF6FF)],
      ).createShader(bounds),
      child: Text(
        'Golden Mole User',
        style: GoogleFonts.orbitron(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _subtitle() {
    return Text(
      'CONSTRUCTION MANAGEMENT',
      style: GoogleFonts.kanit(
        fontSize: 11.5,
        color: const Color(0xFF8FB3D9),
        letterSpacing: 3.0,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// วงแหวนหมุนรอบโลโก้แบบเครื่องปฏิกรณ์
class _OrbitRingsPainter extends CustomPainter {
  _OrbitRingsPainter({required this.t});

  final double t;
  static const _cyan = Color(0xFF22D3EE);
  static const _blue = Color(0xFF3B82F6);
  static const _violet = Color(0xFF8B5CF6);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = size.width / 2;
    final angle = t * 2 * math.pi;

    // วงแหวนจางเป็นฐาน
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.06);
    canvas.drawCircle(center, base - 6, track);
    canvas.drawCircle(center, base - 20, track);

    // วงโค้งนีออนหมุนตามเข็ม
    final arc1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [_cyan.withValues(alpha: 0), _cyan, _blue],
        stops: const [0.0, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: base - 6));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: base - 6),
      angle,
      math.pi * 1.15,
      false,
      arc1,
    );

    // วงโค้งด้านในหมุนสวนทาง
    final arc2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [_violet.withValues(alpha: 0), _violet, _cyan],
        stops: const [0.0, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: base - 20));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: base - 20),
      -angle * 1.4,
      math.pi * 0.9,
      false,
      arc2,
    );

    // จุดเรืองแสงโคจร
    for (var i = 0; i < 3; i++) {
      final a = angle * (i.isEven ? 1 : -1.3) + i * 2.1;
      final r = base - (i == 1 ? 20 : 6);
      final p = Offset(
        center.dx + r * math.cos(a),
        center.dy + r * math.sin(a),
      );
      final dot = Paint()
        ..color = (i == 1 ? _violet : _cyan)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(p, 3.2, dot);
      canvas.drawCircle(p, 2.0, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitRingsPainter oldDelegate) =>
      oldDelegate.t != t;
}

/// พื้นหลังไฮเทค — กริดจุด + ออร์บเรืองแสง + อนุภาคลอย
class _TechBackgroundPainter extends CustomPainter {
  _TechBackgroundPainter({required this.progress}) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value * 2 * math.pi;

    // ออร์บเรืองแสงเคลื่อนที่
    final orb1 = Offset(
      size.width * 0.2 + 26 * math.sin(t * 0.8),
      size.height * 0.22 + 18 * math.cos(t * 0.55),
    );
    final orb2 = Offset(
      size.width * 0.82 + 22 * math.cos(t * 0.7),
      size.height * 0.8 + 20 * math.sin(t * 0.5),
    );
    final orbPaint = Paint();
    orbPaint.shader = const RadialGradient(
      colors: [Color(0x4022D3EE), Color(0x0022D3EE)],
    ).createShader(Rect.fromCircle(center: orb1, radius: 220));
    canvas.drawCircle(orb1, 220, orbPaint);
    orbPaint.shader = const RadialGradient(
      colors: [Color(0x338B5CF6), Color(0x008B5CF6)],
    ).createShader(Rect.fromCircle(center: orb2, radius: 240));
    canvas.drawCircle(orb2, 240, orbPaint);

    // กริดจุดเทคโนโลยี
    const gap = 34.0;
    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (double y = gap; y < size.height; y += gap) {
      for (double x = gap; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }

    // อนุภาคลอยขึ้น
    final rnd = math.Random(7);
    final particlePaint = Paint();
    for (var i = 0; i < 22; i++) {
      final seed = rnd.nextDouble();
      final speed = 0.4 + seed * 0.7;
      final phase = (progress.value * speed + seed) % 1.0;
      final x = size.width * rnd.nextDouble();
      final y = size.height * (1 - phase);
      final op = (math.sin(phase * math.pi)).clamp(0.0, 1.0) * 0.5;
      particlePaint.color =
          (i.isEven ? const Color(0xFF22D3EE) : const Color(0xFF3B82F6))
              .withValues(alpha: op);
      canvas.drawCircle(Offset(x, y), 1.6 + seed * 1.4, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TechBackgroundPainter oldDelegate) => true;
}

/// แถบโหลดเรืองแสงแบบสแกน
class _ProgressBeam extends StatelessWidget {
  const _ProgressBeam({required this.progress});

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Stack(
          children: [
            Container(color: Colors.white.withValues(alpha: 0.08)),
            AnimatedBuilder(
              animation: progress,
              builder: (context, _) {
                return LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    final barW = w * 0.4;
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
                                  Color(0x0022D3EE),
                                  Color(0xFF22D3EE),
                                  Color(0xFF3B82F6),
                                  Color(0x003B82F6),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF22D3EE)
                                      .withValues(alpha: 0.6),
                                  blurRadius: 8,
                                ),
                              ],
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
