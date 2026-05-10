import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Tier ประสิทธิภาพอุปกรณ์ — ใช้ลดการใช้ RAM/CPU บนเครื่องจำกัด
///
/// เรียก [init] หนึ่งครั้งหลัง [WidgetsFlutterBinding.ensureInitialized]
/// และก่อน [runApp].
class DevicePerf {
  DevicePerf._();

  static bool _ready = false;
  static bool _constrained = false;

  /// เครื่องที่ถือว่าจำกัด: Android โหมด low-RAM / RAM ต่ำ / OS เก่า หรือ iOS RAM ต่ำ
  static bool get isConstrainedDevice => _constrained;

  static bool get isReady => _ready;

  static Future<void> init() async {
    if (_ready) return;
    var constrained = false;

    if (kIsWeb) {
      _applyImageCache(constrained: true);
      _constrained = false;
      _ready = true;
      return;
    }

    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        final ramMb = a.physicalRamSize;
        constrained = a.isLowRamDevice ||
            (ramMb > 0 && ramMb < 3072) ||
            a.version.sdkInt < 26;
      } else if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        final ramMb = i.physicalRamSize;
        constrained = ramMb > 0 && ramMb < 3072;
      }
    } catch (e, st) {
      debugPrint('DevicePerf.init: $e\n$st');
    }

    _constrained = constrained;
    _applyImageCache(constrained: constrained);
    _ready = true;
  }

  /// จำกัด image cache — ค่าเริ่มต้นของ Flutter ใหญ่มากสำหรับเครื่อง RAM น้อย
  static void _applyImageCache({required bool constrained}) {
    final cache = PaintingBinding.instance.imageCache;
    if (constrained) {
      cache.maximumSize = 24;
      cache.maximumSizeBytes = 20 << 20; // 20 MiB
    } else {
      cache.maximumSize = 100;
      cache.maximumSizeBytes = 56 << 20; // 56 MiB
    }
  }
}
