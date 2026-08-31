import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/device_perf.dart';
import 'app_version_label.dart';

/// Launch splash — branded dark + gold reveal (~1.5–2.5s), then login/home.
///
/// Uses `assets/branding/splash_logo.png` (mole + GOLDEN/MOLE lockup).
/// Login/header keep [AppLogo] / `app_logo.png`.
class BootstrapSplash extends StatefulWidget {
  const BootstrapSplash({super.key});

  @override
  State<BootstrapSplash> createState() => _BootstrapSplashState();
}

class _BootstrapSplashState extends State<BootstrapSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final bool _reduceMotion;
  late final bool _lite;

  static const _bg = Color(0xFF000000);
  static const _gold = Color(0xFFC5A55A);

  @override
  void initState() {
    super.initState();
    _reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _lite = _reduceMotion || DevicePerf.isConstrainedDevice;

    final durationMs = _reduceMotion
        ? 520
        : (DevicePerf.isConstrainedDevice ? 1100 : 2100);

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    )..forward();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final shortest = MediaQuery.sizeOf(context).shortestSide;
            // Full lockup (mole + stacked GOLDEN/MOLE) — leave side margin on phones.
            final logoSize = (shortest * 0.62).clamp(200.0, 300.0);

            return Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: _bg),
                if (!_lite) _GoldAtmosphere(progress: t),
                SafeArea(
                  child: Stack(
                    children: [
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _LogoReveal(
                                progress: t,
                                lite: _lite,
                                reduceMotion: _reduceMotion,
                                size: logoSize,
                              ),
                              SizedBox(height: _lite ? 18 : 22),
                              _FadeSlide(
                                progress: t,
                                begin: _lite ? 0.30 : 0.42,
                                end: _lite ? 0.60 : 0.68,
                                child: Text(
                                  'กำลังโหลด . . .',
                                  textAlign: TextAlign.center,
                                  // Pubspec-bundled Kanit — avoid GoogleFonts
                                  // async load during splash animation frames.
                                  style: const TextStyle(
                                    fontFamily: 'Kanit',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF9A8F78),
                                    letterSpacing: 0.25,
                                  ),
                                ),
                              ),
                              SizedBox(height: _lite ? 24 : 36),
                              _FadeSlide(
                                progress: t,
                                begin: _lite ? 0.45 : 0.58,
                                end: _lite ? 0.75 : 0.82,
                                child: _lite
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: _gold,
                                        ),
                                      )
                                    : _GoldProgressRail(progress: t),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 12,
                        child: Center(
                          child: Opacity(
                            opacity: (_lite
                                    ? Curves.easeOut.transform(
                                        ((t - 0.4) / 0.4).clamp(0.0, 1.0),
                                      )
                                    : Curves.easeOut.transform(
                                        ((t - 0.55) / 0.35).clamp(0.0, 1.0),
                                      ))
                                .clamp(0.0, 1.0),
                            child: const AppVersionLabel(
                              color: Color(0xFF6B6558),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LogoReveal extends StatelessWidget {
  const _LogoReveal({
    required this.progress,
    required this.lite,
    required this.reduceMotion,
    required this.size,
  });

  final double progress;
  final bool lite;
  final bool reduceMotion;
  final double size;

  static const _gold = Color(0xFFC5A55A);

  @override
  Widget build(BuildContext context) {
    final reveal = Curves.easeOutCubic.transform(
      ((progress - (lite ? 0.0 : 0.06)) / (lite ? 0.45 : 0.42))
          .clamp(0.0, 1.0),
    );
    final scale = reduceMotion ? 1.0 : (0.88 + 0.12 * reveal);
    final glow = lite
        ? 0.0
        : Curves.easeOut.transform(
            ((progress - 0.2) / 0.5).clamp(0.0, 1.0),
          );

    return Opacity(
      opacity: reveal,
      child: Transform.scale(
        scale: scale,
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: lite
                ? null
                : [
                    BoxShadow(
                      color: _gold.withValues(alpha: 0.08 + 0.18 * glow),
                      blurRadius: 48 + 16 * glow,
                      spreadRadius: 2,
                    ),
                  ],
          ),
          child: Semantics(
            label: 'โลโก้ Golden Mole',
            child: Image.asset(
              'assets/branding/splash_logo.png',
              width: size,
              height: size,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}

class _FadeSlide extends StatelessWidget {
  const _FadeSlide({
    required this.progress,
    required this.begin,
    required this.end,
    required this.child,
  });

  final double progress;
  final double begin;
  final double end;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final span = (end - begin).clamp(0.01, 1.0);
    final t = Curves.easeOutCubic.transform(
      ((progress - begin) / span).clamp(0.0, 1.0),
    );
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (1 - t) * 10),
        child: child,
      ),
    );
  }
}

class _GoldAtmosphere extends StatelessWidget {
  const _GoldAtmosphere({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final appear = Curves.easeOut.transform(
      ((progress - 0.02) / 0.35).clamp(0.0, 1.0),
    );
    final breathe = 0.85 + 0.15 * math.sin(progress * math.pi);
    return Opacity(
      opacity: appear * 0.95,
      child: CustomPaint(
        painter: _GoldGlowPainter(intensity: breathe),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GoldGlowPainter extends CustomPainter {
  _GoldGlowPainter({required this.intensity});

  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.42);
    final radius = size.shortestSide * (0.42 + 0.04 * intensity);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.fromRGBO(197, 165, 90, 0.22 * intensity),
          Color.fromRGBO(197, 165, 90, 0.06 * intensity),
          const Color(0x00000000),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);

    final top = Offset(size.width * 0.72, size.height * 0.08);
    paint.shader = RadialGradient(
      colors: [
        Color.fromRGBO(212, 188, 122, 0.10 * intensity),
        const Color(0x00000000),
      ],
    ).createShader(Rect.fromCircle(center: top, radius: 140));
    canvas.drawCircle(top, 140, paint);
  }

  @override
  bool shouldRepaint(covariant _GoldGlowPainter oldDelegate) =>
      oldDelegate.intensity != intensity;
}

class _GoldProgressRail extends StatelessWidget {
  const _GoldProgressRail({required this.progress});

  final double progress;

  static const _gold = Color(0xFFC5A55A);
  static const _goldDark = Color(0xFF8B7A3E);

  @override
  Widget build(BuildContext context) {
    final fill = Curves.easeInOutCubic.transform(
      ((progress - 0.55) / 0.4).clamp(0.0, 1.0),
    );
    return SizedBox(
      width: 148,
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF2A261C)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fill,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_goldDark, _gold, Color(0xFFE8D5A3)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
