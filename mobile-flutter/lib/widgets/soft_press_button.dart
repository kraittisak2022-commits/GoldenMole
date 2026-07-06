import 'package:flutter/material.dart';

import '../utils/app_haptics.dart';
import '../utils/device_perf.dart';

/// ขนาดปุ่ม — ยิ่งใหญ่ยิ่งย่อน้อยตอนกด
enum SoftPressSize {
  large(0.98),
  medium(0.96),
  small(0.93);

  const SoftPressSize(this.pressedScale);
  final double pressedScale;
}

/// จังหวะกด/ปล่อย — เข้าเร็ว คลายช้า (เครื่องช้าใช้ curve ง่ายกว่า)
class SoftPressMotion {
  SoftPressMotion._();

  static bool get _lite => DevicePerf.isConstrainedDevice;

  static Duration downDuration() =>
      Duration(milliseconds: _lite ? 50 : 70);

  static Duration upDuration() =>
      Duration(milliseconds: _lite ? 120 : 240);

  static Curve downCurve() => Curves.easeOutCubic;

  static Curve upCurve() =>
      _lite ? Curves.easeOutCubic : Curves.easeOutBack;

  static double highlightAlpha({required bool isDarkSurface}) =>
      isDarkSurface ? 0.07 : 0.05;
}

/// เอฟเฟกต์กดนุ่ม — ใช้เมื่อ parent ควบคุมสถานะ [pressed] เอง
class SoftPressShell extends StatelessWidget {
  const SoftPressShell({
    super.key,
    required this.pressed,
    required this.child,
    this.size = SoftPressSize.medium,
    this.borderRadius = 0,
    this.showHighlight = true,
    this.isDarkSurface = true,
    this.liftWhenIdle = false,
    this.idleLiftY = -2,
  });

  final bool pressed;
  final Widget child;
  final SoftPressSize size;
  final double borderRadius;
  final bool showHighlight;
  final bool isDarkSurface;
  final bool liftWhenIdle;
  final double idleLiftY;

  @override
  Widget build(BuildContext context) {
    final scale = pressed ? size.pressedScale : 1.0;
    final liftY = liftWhenIdle && !pressed ? idleLiftY : 0.0;
    final duration = pressed
        ? SoftPressMotion.downDuration()
        : SoftPressMotion.upDuration();
    final curve =
        pressed ? SoftPressMotion.downCurve() : SoftPressMotion.upCurve();

    return AnimatedScale(
      scale: scale,
      duration: duration,
      curve: curve,
      child: AnimatedSlide(
        offset: Offset(0, liftY / 40),
        duration: duration,
        curve: curve,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            child,
            if (showHighlight && borderRadius > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: pressed ? 1 : 0,
                    duration: SoftPressMotion.downDuration(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: (isDarkSurface ? Colors.white : Colors.black)
                            .withValues(
                          alpha: SoftPressMotion.highlightAlpha(
                            isDarkSurface: isDarkSurface,
                          ),
                        ),
                        borderRadius: BorderRadius.circular(borderRadius),
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

/// ปุ่มกดนุ่ม — สเกล + ไฮไลต์ + haptic ตอนนิ้วลง
///
/// ถ้า [onTap] เป็น null จะแสดงเอฟเฟกต์กดอย่างเดียว (ลูกจัดการ tap เอง)
class SoftPressButton extends StatefulWidget {
  const SoftPressButton({
    super.key,
    required this.child,
    this.onTap,
    this.size = SoftPressSize.medium,
    this.borderRadius = 12,
    this.hapticOnDown = true,
    this.useConfirmHaptic = false,
    this.showHighlight = true,
    this.isDarkSurface = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final SoftPressSize size;
  final double borderRadius;
  final bool hapticOnDown;
  final bool useConfirmHaptic;
  final bool showHighlight;
  final bool isDarkSurface;

  @override
  State<SoftPressButton> createState() => _SoftPressButtonState();
}

class _SoftPressButtonState extends State<SoftPressButton> {
  bool _pressed = false;

  void _onDown() {
    if (_pressed) return;
    setState(() => _pressed = true);
    if (!widget.hapticOnDown) return;
    if (widget.useConfirmHaptic) {
      AppHaptics.confirm();
    } else {
      AppHaptics.tap();
    }
  }

  void _onUp() {
    if (!_pressed) return;
    setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _onDown(),
      onTapUp: (_) {
        _onUp();
        widget.onTap?.call();
      },
      onTapCancel: _onUp,
      child: SoftPressShell(
        pressed: _pressed,
        size: widget.size,
        borderRadius: widget.borderRadius,
        showHighlight: widget.showHighlight,
        isDarkSurface: widget.isDarkSurface,
        child: widget.child,
      ),
    );
  }
}
