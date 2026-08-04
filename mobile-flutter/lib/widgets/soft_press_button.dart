import 'package:flutter/material.dart';

import '../utils/app_haptics.dart';
import '../utils/device_perf.dart';
import '../utils/touch_profile.dart';

/// ขนาดปุ่ม — ยิ่งใหญ่ยิ่งย่อน้อยตอนกด
enum SoftPressSize {
  large(0.97),
  medium(0.955),
  small(0.93);

  const SoftPressSize(this.pressedScale);
  final double pressedScale;

  double resolveScale(BuildContext context) {
    final profile = TouchProfile.of(context);
    return switch (this) {
      SoftPressSize.large => profile.softPressScaleLarge,
      SoftPressSize.medium => profile.softPressScaleMedium,
      SoftPressSize.small => profile.softPressScaleSmall,
    };
  }
}

/// เงา depth ตอนกด — idle ยกขึ้น กดแล้วเงาเลื่อนลง
class SoftPressDepthShadow {
  const SoftPressDepthShadow({
    this.color = const Color(0x0A0F172A),
    this.blurRadius = 8,
    this.offsetY = 2,
    this.pressedBlurRadius = 3,
    this.pressedOffsetY = 1,
  });

  final Color color;
  final double blurRadius;
  final double offsetY;
  final double pressedBlurRadius;
  final double pressedOffsetY;
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
    this.depthShadow,
  });

  final bool pressed;
  final Widget child;
  final SoftPressSize size;
  final double borderRadius;
  final bool showHighlight;
  final bool isDarkSurface;
  final bool liftWhenIdle;
  final double idleLiftY;
  final SoftPressDepthShadow? depthShadow;

  @override
  Widget build(BuildContext context) {
    final scale = pressed ? size.resolveScale(context) : 1.0;
    final liftY = pressed ? 0.0 : (liftWhenIdle ? idleLiftY : 0.0);
    final duration = pressed
        ? SoftPressMotion.downDuration()
        : SoftPressMotion.upDuration();
    final curve =
        pressed ? SoftPressMotion.downCurve() : SoftPressMotion.upCurve();

    Widget core = Stack(
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
    );

    if (depthShadow != null && !DevicePerf.isConstrainedDevice) {
      final s = depthShadow!;
      // เงาห้ามใช้ curve ที่ overshoot (เช่น easeOutBack) — blurRadius จะติดลบแล้ว assert
      core = AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: s.color,
              blurRadius: pressed ? s.pressedBlurRadius : s.blurRadius,
              offset: Offset(0, pressed ? s.pressedOffsetY : s.offsetY),
            ),
          ],
        ),
        child: core,
      );
    }

    return AnimatedScale(
      scale: scale,
      duration: duration,
      curve: curve,
      child: AnimatedSlide(
        offset: Offset(0, liftY / 40),
        duration: duration,
        curve: curve,
        child: core,
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
    this.liftWhenIdle = false,
    this.idleLiftY = -2,
    this.depthShadow,
    this.hitPadding,
  });

  final Widget child;
  final VoidCallback? onTap;
  final SoftPressSize size;
  final double borderRadius;
  final bool hapticOnDown;
  final bool useConfirmHaptic;
  final bool showHighlight;
  final bool isDarkSurface;
  final bool liftWhenIdle;
  final double idleLiftY;
  final SoftPressDepthShadow? depthShadow;
  final EdgeInsets? hitPadding;

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
    final extra = widget.hitPadding ?? TouchProfile.of(context).extraHitPadding;
    return Padding(
      padding: extra,
      child: GestureDetector(
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
          liftWhenIdle: widget.liftWhenIdle,
          idleLiftY: widget.idleLiftY,
          depthShadow: widget.depthShadow,
          child: widget.child,
        ),
      ),
    );
  }
}
