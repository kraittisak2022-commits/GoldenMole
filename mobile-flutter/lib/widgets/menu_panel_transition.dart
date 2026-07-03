import 'package:flutter/material.dart';

import '../utils/device_perf.dart';

/// Transition นุ่มเมื่อสลับเมนูในแผงหลัก (กริด ↔ บันทึกและนับจำนวน)
class MenuPanelTransition {
  MenuPanelTransition._();

  static Duration duration({bool lite = false}) => Duration(
        milliseconds: lite
            ? 200
            : (DevicePerf.isConstrainedDevice ? 260 : 340),
      );

  static Widget build(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
