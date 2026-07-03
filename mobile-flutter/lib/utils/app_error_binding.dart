import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../screens/app_fatal_error_screen.dart';
import 'mobile_error_report_auto_submit.dart';
import 'mobile_error_screen_tracker.dart';

/// จับ error ที่ไม่ได้รับใน try/catch แล้วเปิดหน้าส่งรายงาน (ต้องมี [navigatorKey] บน MaterialApp)
class AppErrorBinding {
  AppErrorBinding._();

  static bool _routeOpen = false;

  static bool _isBenignLayoutError(Object error) {
    final msg = error.toString();
    return msg.contains('RenderFlex overflowed') ||
        msg.contains('overflowed by');
  }

  static void install(GlobalKey<NavigatorState> navigatorKey) {
    FlutterError.onError = (FlutterErrorDetails details) {
      if (_isBenignLayoutError(details.exception)) {
        if (kDebugMode) FlutterError.presentError(details);
        return;
      }
      FlutterError.presentError(details);
      _tryOpen(
        navigatorKey,
        details.exception,
        details.stack,
        'uncaught_flutter',
      );
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      if (_isBenignLayoutError(error)) {
        if (kDebugMode) {
          debugPrint('Layout overflow (suppressed fatal route): $error');
        }
        return true;
      }
      _tryOpen(navigatorKey, error, stack, 'uncaught_zone');
      return true;
    };
  }

  static void _tryOpen(
    GlobalKey<NavigatorState> navigatorKey,
    Object error,
    StackTrace? stack,
    String source,
  ) {
    if (_routeOpen) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    MobileErrorReportAutoSubmit.fire(
      error: error,
      stackTrace: stack,
      source: source,
      screenPage: MobileErrorScreenTracker.page,
      screenAction: MobileErrorScreenTracker.module,
    );

    _routeOpen = true;
    scheduleMicrotask(() {
      final n = navigatorKey.currentState;
      if (n == null || !n.mounted) {
        _routeOpen = false;
        return;
      }
      unawaited(
        n
            .push<void>(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (ctx) => AppFatalErrorScreen(
                  error: error,
                  stackTrace: stack,
                  source: source,
                ),
              ),
            )
            .whenComplete(() {
              _routeOpen = false;
            }),
      );
    });
  }
}
