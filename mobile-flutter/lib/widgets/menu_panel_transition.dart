import 'package:flutter/material.dart';

import '../utils/device_perf.dart';

/// Transition นุ่มเมื่อสลับเมนูในแผงหลัก (กริด ↔ บันทึกและนับจำนวน)
class MenuPanelTransition {
  MenuPanelTransition._();

  static Duration duration({bool lite = false}) => Duration(
        milliseconds: lite
            ? 200
            : (DevicePerf.isConstrainedDevice ? 260 : 380),
      );

  static Widget build(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(curved);
    final scale = Tween<double>(begin: 0.98, end: 1.0).animate(curved);

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: ScaleTransition(scale: scale, child: child),
      ),
    );
  }
}
