import 'package:flutter/material.dart';

/// ค่าสัมผัสตามขนาดจอ — มือถือ vs แท็บเล็ต
class TouchProfile {
  const TouchProfile._({
    required this.isTablet,
    required this.isLargeTablet,
  });

  final bool isTablet;
  final bool isLargeTablet;

  static const double tabletBreakpoint = 600;
  static const double largeTabletBreakpoint = 700;

  factory TouchProfile.of(BuildContext context) {
    final side = MediaQuery.sizeOf(context).shortestSide;
    return TouchProfile._(
      isTablet: side >= tabletBreakpoint,
      isLargeTablet: side >= largeTabletBreakpoint,
    );
  }

  double get minTapTarget => isTablet ? 52.0 : 48.0;

  double get navBarHeight => isTablet ? 72.0 : 64.0;

  double get gridGap => isTablet ? 14.0 : 10.0;

  /// scale ตอนกด — แท็บเล็ตย่อน้อยกว่า (นิ้วใหญ่กว่า)
  double get softPressScaleMedium =>
      isTablet ? 0.97 : (isLargeTablet ? 0.965 : 0.955);

  double get softPressScaleLarge => isTablet ? 0.98 : 0.97;

  double get softPressScaleSmall => isTablet ? 0.94 : 0.93;

  /// padding เพิ่มรอบ hit area บนแท็บเล็ต
  EdgeInsets get extraHitPadding => isTablet
      ? const EdgeInsets.symmetric(horizontal: 4, vertical: 6)
      : EdgeInsets.zero;
}
