import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// ขอสิทธิ์กล้อง/แกลเลอรีก่อนเลือกรูปบำรุงรักษา
class MaintenanceImagePermissions {
  MaintenanceImagePermissions._();

  /// คืนข้อความภาษาไทยเมื่อไม่สามารถดำเนินการต่อได้ (null = พร้อมเลือกรูป)
  static Future<String?> ensureFor(ImageSource source) async {
    if (source == ImageSource.camera) {
      return _ensureCamera();
    }
    return _ensureGallery();
  }

  static Future<String?> _ensureCamera() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (status.isGranted) return null;
    if (status.isPermanentlyDenied) {
      return 'ไม่มีสิทธิ์ใช้กล้อง — เปิดในการตั้งค่าแอพ';
    }
    return 'ไม่ได้รับอนุญาตให้ใช้กล้อง';
  }

  static Future<String?> _ensureGallery() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;

    if (Platform.isAndroid) {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      // Android 13+ uses system Photo Picker — no READ_MEDIA permission needed.
      if (sdk >= 33) return null;
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      if (status.isGranted) return null;
      if (status.isPermanentlyDenied) {
        return 'ไม่มีสิทธิ์เข้าถึงรูปภาพ — เปิดในการตั้งค่าแอพ';
      }
      return 'ไม่ได้รับอนุญาตให้เข้าถึงรูปภาพ';
    }

    var status = await Permission.photos.status;
    if (!status.isGranted && !status.isLimited) {
      status = await Permission.photos.request();
    }
    if (status.isGranted || status.isLimited) return null;
    if (status.isPermanentlyDenied) {
      return 'ไม่มีสิทธิ์เข้าถึงรูปภาพ — เปิดในการตั้งค่าแอพ';
    }
    return 'ไม่ได้รับอนุญาตให้เข้าถึงรูปภาพ';
  }
}

String maintenanceImagePickErrorMessage(Object error) {
  final msg = error.toString();
  if (msg.contains('MissingPluginException')) {
    return 'ฟีเจอร์รูปภาพยังไม่พร้อม — ปิดแอพแล้วเปิดใหม่ หรือติดตั้งเวอร์ชันล่าสุด';
  }
  if (msg.contains('already_active')) {
    return 'กำลังเลือกรูปอยู่แล้ว กรุณารอสักครู่';
  }
  if (msg.contains('photo_access_denied') ||
      msg.contains('camera_access_denied') ||
      msg.contains('Permission')) {
    return 'ไม่ได้รับอนุญาตให้เข้าถึงรูปภาพหรือกล้อง';
  }
  return 'เลือกรูปไม่สำเร็จ';
}
