import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// กรอบเมนู «บันทึกและนับจำนวน» — ประหยัดพลังงาน (หน้าจอไม่ดับ)
class CountRecordMenuShell extends StatefulWidget {
  const CountRecordMenuShell({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<CountRecordMenuShell> createState() => _CountRecordMenuShellState();
}

enum _PowerState { active, dimmed, sleeping }

class _CountRecordMenuShellState extends State<CountRecordMenuShell>
    with SingleTickerProviderStateMixin {
  static const _dimAfter = Duration(seconds: 60);
  static const _sleepAfter = Duration(minutes: 10);

  /// ความสว่างตอนหน้าจอพัก — มองเห็น AOD ได้แต่ประหยัดแบต (OLED)
  static const _sleepBrightness = 0.06;

  static const _teal = Color(0xFF11A8BA);
  static const _tealGlow = Color(0xFF4DD0E1);

  Timer? _powerTickTimer;
  DateTime _lastActivity = DateTime.now();
  _PowerState _powerState = _PowerState.active;
  double? _savedBrightness;
  bool _brightnessRestored = true;

  AnimationController? _pulseController;
  Animation<double>? _pulseScale;
  Animation<double>? _pulseOpacity;

  String get _sleepAfterLabel {
    final minutes = _sleepAfter.inMinutes;
    if (minutes >= 1) return 'ไม่ได้ใช้งานเกิน $minutes นาที';
    return 'ไม่ได้ใช้งานเกิน ${_sleepAfter.inSeconds} วินาที';
  }

  TextStyle _kanit({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w600,
    Color color = Colors.white,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.kanit(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_enableKeepAwake());
    _startPowerTick();
  }

  @override
  void dispose() {
    _powerTickTimer?.cancel();
    _stopPulse(dispose: true);
    unawaited(_releaseKeepAwake(restoreBrightness: true));
    super.dispose();
  }

  void _ensurePulseController() {
    if (_pulseController != null) return;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7200),
    );
    _pulseController = ctrl;
    _pulseScale = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: ctrl, curve: Curves.easeInOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.22, end: 0.55).animate(
      CurvedAnimation(parent: ctrl, curve: Curves.easeInOut),
    );
  }

  void _startPulse() {
    _ensurePulseController();
    final ctrl = _pulseController!;
    if (!ctrl.isAnimating) {
      ctrl.repeat(reverse: true);
    }
  }

  void _stopPulse({bool dispose = false}) {
    final ctrl = _pulseController;
    if (ctrl == null) return;
    if (ctrl.isAnimating) {
      ctrl.stop();
      ctrl.value = 0;
    }
    if (dispose) {
      ctrl.dispose();
      _pulseController = null;
      _pulseScale = null;
      _pulseOpacity = null;
    }
  }

  Future<void> _enableKeepAwake() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  }

  Future<void> _releaseKeepAwake({required bool restoreBrightness}) async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    if (restoreBrightness) {
      await _restoreBrightnessImmediate();
    }
  }

  Future<void> _restoreBrightnessImmediate() async {
    if (_brightnessRestored) return;
    try {
      final saved = _savedBrightness;
      if (saved != null) {
        await ScreenBrightness().setApplicationScreenBrightness(saved);
      } else {
        await ScreenBrightness().resetApplicationScreenBrightness();
      }
    } catch (_) {}
    _brightnessRestored = true;
    _savedBrightness = null;
  }

  Future<void> _fadeBrightnessUp() async {
    if (_brightnessRestored) return;
    final target = _savedBrightness ?? 1.0;
    try {
      const steps = 10;
      for (var i = 1; i <= steps; i++) {
        if (!mounted || _powerState != _PowerState.active) return;
        final t = Curves.easeOutCubic.transform(i / steps);
        final level = _sleepBrightness + (target - _sleepBrightness) * t;
        await ScreenBrightness().setApplicationScreenBrightness(level);
        await Future<void>.delayed(const Duration(milliseconds: 32));
      }
      if (_savedBrightness != null) {
        await ScreenBrightness().setApplicationScreenBrightness(
          _savedBrightness!,
        );
      } else {
        await ScreenBrightness().resetApplicationScreenBrightness();
      }
    } catch (_) {}
    _brightnessRestored = true;
    _savedBrightness = null;
  }

  void _startPowerTick() {
    _powerTickTimer?.cancel();
    _powerTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _powerState == _PowerState.sleeping) return;
      final idle = DateTime.now().difference(_lastActivity);
      if (idle >= _sleepAfter) {
        unawaited(_enterSleep());
      } else if (idle >= _dimAfter) {
        if (_powerState != _PowerState.dimmed) {
          setState(() => _powerState = _PowerState.dimmed);
        }
      } else if (_powerState != _PowerState.active) {
        setState(() => _powerState = _PowerState.active);
      }
    });
  }

  void _noteActiveUse() {
    _lastActivity = DateTime.now();
  }

  void _wakeFromDim() {
    if (_powerState != _PowerState.dimmed) return;
    _noteActiveUse();
    setState(() => _powerState = _PowerState.active);
  }

  Future<void> _enterSleep() async {
    if (!mounted || _powerState == _PowerState.sleeping) return;
    setState(() => _powerState = _PowerState.sleeping);
    _startPulse();
    try {
      if (_brightnessRestored) {
        _savedBrightness = await ScreenBrightness().application;
        _brightnessRestored = false;
      }
      await ScreenBrightness().setApplicationScreenBrightness(_sleepBrightness);
    } catch (_) {}
    await _releaseKeepAwake(restoreBrightness: false);
  }

  Future<void> _wakeUp() async {
    if (_powerState != _PowerState.sleeping) return;
    _stopPulse();
    _noteActiveUse();
    setState(() => _powerState = _PowerState.active);
    unawaited(_fadeBrightnessUp());
    unawaited(_enableKeepAwake());
  }

  Widget _buildDimOverlay() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _wakeFromDim,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black.withValues(alpha: 0.22)),
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _PowerHintPill(
                  icon: Icons.battery_saver_rounded,
                  title: 'โหมดประหยัดพลังงาน',
                  subtitle: 'แตะหน้าจอเพื่อกลับใช้งาน',
                  styleBuilder: _kanit,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dimmed = _powerState == _PowerState.dimmed;
    final sleeping = _powerState == _PowerState.sleeping;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (_powerState == _PowerState.active) _noteActiveUse();
      },
      onPointerMove: (_) {
        if (_powerState == _PowerState.active) _noteActiveUse();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (dimmed)
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: 1,
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                child: _buildDimOverlay(),
              ),
            ),
          if (sleeping)
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: 1,
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                child: _buildSleepOverlayWithPulse(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSleepOverlayWithPulse() {
    _ensurePulseController();
    final scale = _pulseScale!;
    final opacity = _pulseOpacity!;
    final ctrl = _pulseController!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_wakeUp()),
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _SleepClock(),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 72),
                    AnimatedBuilder(
                      animation: ctrl,
                      builder: (context, _) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.scale(
                              scale: scale.value,
                              child: Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _tealGlow.withValues(
                                      alpha: opacity.value * 0.45,
                                    ),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _teal.withValues(alpha: 0.18),
                                border: Border.all(
                                  color: _teal.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Icon(
                                Icons.touch_app_rounded,
                                size: 32,
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'หน้าจอพักเพื่อประหยัดแบต',
                      textAlign: TextAlign.center,
                      style: _kanit(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.82),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'แตะที่ใดก็ได้เพื่อใช้งานต่อ',
                      textAlign: TextAlign.center,
                      style: _kanit(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.48),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _sleepAfterLabel,
                            style: _kanit(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _KanitStyleBuilder = TextStyle Function({
  required double fontSize,
  FontWeight fontWeight,
  Color color,
  double? height,
  double? letterSpacing,
});

class _PowerHintPill extends StatelessWidget {
  const _PowerHintPill({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.styleBuilder,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final _KanitStyleBuilder styleBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF4DD0E1), size: 18),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: styleBuilder(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
                Text(
                  subtitle,
                  style: styleBuilder(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// นาฬิกา AOD จางๆ บนพื้นดำ
class _SleepClock extends StatefulWidget {
  const _SleepClock();

  @override
  State<_SleepClock> createState() => _SleepClockState();
}

class _SleepClockState extends State<_SleepClock> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Text(
            '$hh:$mm',
            style: GoogleFonts.kanit(
              fontSize: 56,
              fontWeight: FontWeight.w300,
              color: Colors.white.withValues(alpha: 0.28),
              letterSpacing: 2,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
