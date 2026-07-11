import 'package:flutter/material.dart';

import '../utils/device_perf.dart';

/// สไตล์เปลี่ยนหน้า — ใช้ร่วมกันทั้งแอพ
enum AppTransitionStyle {
  /// fade + slide จากขวา + scale เบา (Settings, Calendar, Employees)
  drillDown,

  /// fade + slide จากล่าง (Quick Input)
  modalUp,
}

/// Route เปลี่ยนหน้าแบบนุ่ม — duration/curve เดียวกันทั้งแอพ
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({
    required Widget page,
    AppTransitionStyle style = AppTransitionStyle.drillDown,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: _forwardDuration(style),
          reverseTransitionDuration: _reverseDuration(style),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return _AppTransition(
              animation: animation,
              style: style,
              child: child,
            );
          },
        );

  static Duration _forwardDuration(AppTransitionStyle style) {
    if (DevicePerf.isConstrainedDevice) {
      return style == AppTransitionStyle.modalUp
          ? const Duration(milliseconds: 240)
          : const Duration(milliseconds: 260);
    }
    return style == AppTransitionStyle.modalUp
        ? const Duration(milliseconds: 300)
        : const Duration(milliseconds: 320);
  }

  static Duration _reverseDuration(AppTransitionStyle style) {
    if (DevicePerf.isConstrainedDevice) {
      return const Duration(milliseconds: 200);
    }
    return const Duration(milliseconds: 260);
  }
}

class _AppTransition extends StatelessWidget {
  const _AppTransition({
    required this.animation,
    required this.style,
    required this.child,
  });

  final Animation<double> animation;
  final AppTransitionStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );

    final Offset begin;
    final double beginScale;
    switch (style) {
      case AppTransitionStyle.drillDown:
        begin = const Offset(0.08, 0);
        beginScale = 0.98;
      case AppTransitionStyle.modalUp:
        begin = const Offset(0, 0.04);
        beginScale = 1.0;
    }

    final slide = Tween<Offset>(begin: begin, end: Offset.zero).animate(curved);
    final fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    final scale = Tween<double>(begin: beginScale, end: 1.0).animate(curved);

    if (style == AppTransitionStyle.modalUp) {
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );
    }

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: ScaleTransition(scale: scale, child: child),
      ),
    );
  }
}

/// PageTransitionsTheme builder — ใช้ drillDown เป็นค่าเริ่มต้น Android
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _AppTransition(
      animation: animation,
      style: AppTransitionStyle.drillDown,
      child: child,
    );
  }
}
