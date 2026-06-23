import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// กรอบเมนู «บันทึกและนับจำนวน» — ปัดซ้ายกลับเมนูหลัก + ประหยัดพลังงาน
class CountRecordMenuShell extends StatefulWidget {
  const CountRecordMenuShell({
    super.key,
    required this.child,
    required this.onSwipeBack,
  });

  final Widget child;
  final VoidCallback onSwipeBack;

  @override
  State<CountRecordMenuShell> createState() => _CountRecordMenuShellState();
}

enum _PowerState { active, dimmed, sleeping }

class _CountRecordMenuShellState extends State<CountRecordMenuShell> {
  static const _dimAfter = Duration(seconds: 60);
  static const _sleepAfter = Duration(minutes: 10);

  Timer? _powerTickTimer;
  DateTime _lastActivity = DateTime.now();
  _PowerState _powerState = _PowerState.active;
  double? _savedBrightness;
  bool _brightnessRestored = true;

  @override
  void initState() {
    super.initState();
    unawaited(_enableKeepAwake());
    _startPowerTick();
  }

  @override
  void dispose() {
    _powerTickTimer?.cancel();
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

  double _dragDx = 0;

  void _trySwipeBack(DragEndDetails details) {
    if (_powerState == _PowerState.sleeping) return;
    final velocity = details.primaryVelocity ?? 0;
    if (_dragDx < -72 || velocity < -280) {
      widget.onSwipeBack();
    }
    _dragDx = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _noteActivity(),
      onPointerMove: (_) => _noteActivity(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _dragDx = 0,
        onHorizontalDragUpdate: (d) => _dragDx += d.delta.dx,
        onHorizontalDragEnd: _trySwipeBack,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (_powerState == _PowerState.dimmed)
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 350),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.58),
                  ),
                ),
              ),
            if (_powerState == _PowerState.sleeping)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(_wakeUp()),
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            size: 52,
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'แตะที่หน้าจอเพื่อปลุก',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'ไม่ได้ใช้งานเกิน 10 นาที',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.42),
                            ),
                          ),
                        ],
                      ),
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
