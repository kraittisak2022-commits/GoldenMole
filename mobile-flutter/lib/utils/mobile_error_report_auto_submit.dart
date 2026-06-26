import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user.dart';
import '../services/mobile_error_report_service.dart';
import '../services/session_service.dart';
import 'mobile_error_report_submit_guard.dart';
import 'save_error_message.dart';

/// ผลการส่งรายงานอัตโนมัติ
class MobileErrorReportAutoSubmitResult {
  const MobileErrorReportAutoSubmitResult({
    required this.success,
    this.reportId,
    this.message,
    this.rateLimited = false,
  });

  final bool success;
  final String? reportId;
  final String? message;
  final bool rateLimited;
}

/// ส่งรายงานข้อผิดพลาดเข้าเว็บอัตโนมัติ (ตาราง `mobile_error_reports`)
class MobileErrorReportAutoSubmit {
  MobileErrorReportAutoSubmit._();

  static final Map<String, Future<MobileErrorReportAutoSubmitResult>> _inFlight =
      {};

  static String _dedupeKey({
    required String source,
    required Object error,
  }) {
    final t = error.toString();
    final clip = t.length <= 120 ? t : t.substring(0, 120);
    return '${source.trim()}|$clip';
  }

  /// ส่งรายงาน — รายงานเดียวกันที่กำลังส่งจะไม่ยิงซ้ำ
  static Future<MobileErrorReportAutoSubmitResult> submit({
    required Object error,
    StackTrace? stackTrace,
    required String source,
    String userNote = '',
    AdminUser? reporter,
    SaveErrorContext? saveContext,
    String? screenPage,
    String? screenAction,
    String? screenButton,
    String? errorField,
  }) {
    final key = _dedupeKey(source: source, error: error);
    return _inFlight.putIfAbsent(key, () async {
      try {
        return await _submitOnce(
          error: error,
          stackTrace: stackTrace,
          source: source,
          userNote: userNote,
          reporter: reporter,
          saveContext: saveContext,
          screenPage: screenPage,
          screenAction: screenAction,
          screenButton: screenButton,
          errorField: errorField,
        );
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  static void fire({
    required Object error,
    StackTrace? stackTrace,
    required String source,
    String userNote = '',
    AdminUser? reporter,
    SaveErrorContext? saveContext,
    String? screenPage,
    String? screenAction,
    String? screenButton,
    String? errorField,
  }) {
    unawaited(
      submit(
        error: error,
        stackTrace: stackTrace,
        source: source,
        userNote: userNote,
        reporter: reporter,
        saveContext: saveContext,
        screenPage: screenPage,
        screenAction: screenAction,
        screenButton: screenButton,
        errorField: errorField,
      ),
    );
  }

  static Future<MobileErrorReportAutoSubmitResult> _submitOnce({
    required Object error,
    StackTrace? stackTrace,
    required String source,
    String userNote = '',
    AdminUser? reporter,
    SaveErrorContext? saveContext,
    String? screenPage,
    String? screenAction,
    String? screenButton,
    String? errorField,
  }) async {
    try {
      final who = reporter ?? await SessionService().getSavedAdmin();
      final id = await MobileErrorReportService(Supabase.instance.client).submit(
        error: error,
        stackTrace: stackTrace,
        source: source,
        userNote: userNote,
        reporter: who,
        saveContext: saveContext,
        screenPage: screenPage,
        screenAction: screenAction,
        screenButton: screenButton,
        errorField: errorField,
      );
      return MobileErrorReportAutoSubmitResult(success: true, reportId: id);
    } on MobileErrorReportRateLimitException catch (e) {
      return MobileErrorReportAutoSubmitResult(
        success: false,
        message: e.message,
        rateLimited: true,
      );
    } catch (e) {
      return MobileErrorReportAutoSubmitResult(
        success: false,
        message: e.toString(),
      );
    }
  }
}
