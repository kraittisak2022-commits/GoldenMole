import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// พูด "บันทึกสำเร็จค่ะ" หลังบันทึกเที่ยว/รอบสำเร็จ
/// ใช้ TTS ในเครื่อง — ไม่ต้องมีอินเทอร์เน็ต (ทำงานออฟไลน์ได้บน Android/iOS)
class RecordSuccessSpeaker {
  RecordSuccessSpeaker._();

  static final RecordSuccessSpeaker instance = RecordSuccessSpeaker._();

  static const _phrase = 'บันทึกสำเร็จค่ะ';

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
      await tts.setVolume(1.0);
      await tts.setSpeechRate(0.46);
      await tts.setPitch(1.08);
      await tts.awaitSpeakCompletion(false);
      _tts = tts;
      _ready = true;
      await _trySetThaiLanguage(tts);
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

  /// ตั้งภาษาไทยถ้าได้ — ไม่ทำให้ TTS ใช้ไม่ได้ถ้าตั้งไม่สำเร็จ (ออฟไลน์ยังพูดได้)
  Future<void> _trySetThaiLanguage(FlutterTts tts) async {
    for (final code in const ['th-TH', 'th']) {
      try {
        await tts.setLanguage(code);
        return;
      } catch (e) {
        debugPrint('RecordSuccessSpeaker: setLanguage($code) skipped — $e');
      }
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
      final tts = _tts!;
      await tts.stop();
      await tts.speak(_phrase);
    } on MissingPluginException {
      _unavailable = true;
    } on PlatformException catch (e, st) {
      debugPrint('RecordSuccessSpeaker.speak: $e\n$st');
    } catch (e, st) {
      debugPrint('RecordSuccessSpeaker.speak: $e\n$st');
    }
  }
}
