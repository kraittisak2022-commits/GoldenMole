import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
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

  static const _teal = Color(0xFF00897B);
  static const _tealGlow = Color(0xFF4DD0E1);
  static const _ink = Color(0xFF0D1B2A);

  Timer? _powerTickTimer;
  DateTime _lastActivity = DateTime.now();
  _PowerState _powerState = _PowerState.active;
  double? _savedBrightness;
  bool _brightnessRestored = true;

  late AnimationController _pulseController;
  late Animation<double> _pulseScale;
  late Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    unawaited(_enableKeepAwake());
    _startPowerTick();
  }

  @override
  void dispose() {
    _powerTickTimer?.cancel();
    _pulseController.dispose();
    unawaited(_releaseKeepAwake(restoreBrightness: true));
    super.dispose();
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
      await _restoreBrightness();
    }
  }

  Future<void> _restoreBrightness() async {
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

  void _noteActivity() {
    if (_powerState == _PowerState.sleeping) {
      unawaited(_wakeUp());
      return;
    }
    _lastActivity = DateTime.now();
    if (_powerState != _PowerState.active) {
      setState(() => _powerState = _PowerState.active);
    }
  }

  Future<void> _enterSleep() async {
    if (!mounted || _powerState == _PowerState.sleeping) return;
    setState(() => _powerState = _PowerState.sleeping);
    try {
      if (_brightnessRestored) {
        _savedBrightness = await ScreenBrightness().application;
        _brightnessRestored = false;
      }
      await ScreenBrightness().setApplicationScreenBrightness(0);
    } catch (_) {}
    await _releaseKeepAwake(restoreBrightness: false);
  }

  Future<void> _wakeUp() async {
    await _restoreBrightness();
    await _enableKeepAwake();
    if (!mounted) return;
    setState(() {
      _powerState = _PowerState.active;
      _lastActivity = DateTime.now();
    });
  }

  Widget _buildDimOverlay() {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.42),
                  Colors.black.withValues(alpha: 0.28),
                  Colors.black.withValues(alpha: 0.52),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.16),
                          Colors.white.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _teal.withValues(alpha: 0.85),
                                _tealGlow.withValues(alpha: 0.65),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.battery_saver_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'โหมดประหยัดพลังงาน',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'แตะหน้าจอเพื่อกลับใช้งาน',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSleepOverlay() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_wakeUp()),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF071018),
              Color(0xFF0F2433),
              Color(0xFF0A1F1C),
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: -80,
              right: -40,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _teal.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -60,
              left: -30,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _tealGlow.withValues(alpha: 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.scale(
                              scale: _pulseScale.value,
                              child: Container(
                                width: 112,
                                height: 112,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _tealGlow.withValues(
                                      alpha: _pulseOpacity.value * 0.55,
                                    ),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    _teal.withValues(alpha: 0.95),
                                    const Color(0xFF00695C),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _tealGlow.withValues(alpha: 0.28),
                                    blurRadius: 28,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.touch_app_rounded,
                                size: 40,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 22,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'หน้าจอพักเพื่อประหยัดแบต',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'แตะที่ใดก็ได้เพื่อใช้งานต่อ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.68),
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: _ink.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: _tealGlow.withValues(alpha: 0.28),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 15,
                                  color: _tealGlow.withValues(alpha: 0.9),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'ไม่ได้ใช้งานเกิน 10 นาที',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withValues(alpha: 0.78),
                                  ),
                                ),
                              ],
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

  @override
  Widget build(BuildContext context) {
    final dimmed = _powerState == _PowerState.dimmed;
    final sleeping = _powerState == _PowerState.sleeping;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _noteActivity(),
      onPointerMove: (_) => _noteActivity(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          IgnorePointer(
            ignoring: !dimmed,
            child: AnimatedOpacity(
              opacity: dimmed ? 1 : 0,
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeInOut,
              child: _buildDimOverlay(),
            ),
          ),
          IgnorePointer(
            ignoring: !sleeping,
            child: AnimatedOpacity(
              opacity: sleeping ? 1 : 0,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOut,
              child: _buildSleepOverlay(),
            ),
          ),
        ],
      ),
    );
  }
}
