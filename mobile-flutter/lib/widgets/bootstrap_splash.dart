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
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF050510), Color(0xFF0A0A1A), Color(0xFF101028)],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: -60,
              left: -20,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value * 2 * math.pi;
                  return Transform.translate(
                    offset: Offset(10 * math.sin(t * 0.7), 8 * math.cos(t)),
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [const Color(0x330096FF), Colors.transparent],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final pulse =
                        1.0 + 0.05 * math.sin(_controller.value * 2 * math.pi);
                    return Transform.scale(
                      scale: pulse,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: const Color(0x3300C8FF)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x4400C8FF),
                              blurRadius: 28,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: const AppLogo(size: 112),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                Text(
                  'Goldenmole',
                  style: GoogleFonts.kanit(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Construction Management',
                  style: GoogleFonts.kanit(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 36),
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFF00C8FF),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
