import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// พูด "บันทึกสำเร็จค่ะ" หลังบันทึกเที่ยว/รอบสำเร็จ
/// ถ้าแพลตฟอร์มไม่มี flutter_tts (MissingPluginException) จะปิดเสียงเงียบๆ
class RecordSuccessSpeaker {
  RecordSuccessSpeaker._();

  static final RecordSuccessSpeaker instance = RecordSuccessSpeaker._();

  FlutterTts? _tts;
  bool _ready = false;
  bool _unavailable = false;
  Future<void>? _initFuture;

  static bool get _mayUseNativeTts {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return true;
      default:
        return false;
    }
  }

  Future<void> _ensureReady() async {
    if (_unavailable || _ready) return;
    _initFuture ??= _init();
    await _initFuture;
  }

  Future<void> _init() async {
    if (!_mayUseNativeTts) {
      _unavailable = true;
      return;
    }
    try {
      final tts = FlutterTts();
      final langOk = await _configureLanguage(tts);
      if (!langOk) {
        _unavailable = true;
        return;
      }
      await tts.setSpeechRate(0.46);
      await tts.setPitch(1.08);
      await tts.setVolume(1.0);
      _tts = tts;
      _ready = true;
    } on MissingPluginException catch (e, st) {
      debugPrint('RecordSuccessSpeaker: plugin missing — $e\n$st');
      _unavailable = true;
    } on PlatformException catch (e, st) {
      debugPrint('RecordSuccessSpeaker: platform error — $e\n$st');
      _unavailable = true;
    } catch (e, st) {
      debugPrint('RecordSuccessSpeaker: init failed — $e\n$st');
      _unavailable = true;
    }
  }

  Future<bool> _configureLanguage(FlutterTts tts) async {
    for (final code in const ['th-TH', 'th']) {
      try {
        final result = await tts.setLanguage(code);
        if (result == 1 || result == true) return true;
      } on MissingPluginException {
        rethrow;
      } catch (_) {}
    }
    try {
      await tts.setLanguage('th-TH');
      return true;
    } on MissingPluginException {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  Future<void> warmUp() async {
    try {
      await _ensureReady();
    } catch (_) {
      _unavailable = true;
    }
  }

  Future<void> speakSuccess() async {
    if (_unavailable) return;
    try {
      await _ensureReady();
      if (!_ready || _tts == null) return;
      await _tts!.stop();
      await _tts!.speak('บันทึกสำเร็จค่ะ');
    } on MissingPluginException {
      _unavailable = true;
    } on PlatformException {
      _unavailable = true;
    } catch (_) {}
  }
}
